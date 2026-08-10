package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"

	"github.com/caigg188/vback/internal/auth"
	"github.com/caigg188/vback/internal/config"
	"github.com/caigg188/vback/internal/events"
	"github.com/caigg188/vback/internal/migratev1"
	"github.com/caigg188/vback/internal/restic"
	"github.com/caigg188/vback/internal/scheduler"
	"github.com/caigg188/vback/internal/server"
	"github.com/caigg188/vback/internal/store"
)

const version = "2.0.0-dev"

type application struct {
	cfg       config.Config
	store     *store.Store
	runner    *restic.Runner
	scheduler *scheduler.Scheduler
	auth      *auth.Manager
	hub       *events.Hub
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "vback:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	command := "serve"
	if len(args) > 0 {
		command = args[0]
		args = args[1:]
	}
	if command == "version" || command == "--version" || command == "-v" {
		fmt.Println("vback", version)
		return nil
	}
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	if err := cfg.EnsureDirs(); err != nil {
		return err
	}
	st, err := store.Open(cfg.DBPath())
	if err != nil {
		return err
	}
	defer st.Close()
	hub := events.New()
	runner := restic.New(cfg, st, hub)
	sched := scheduler.New(st, runner)
	authManager := auth.New(cfg, st)
	app := application{cfg: cfg, store: st, runner: runner, scheduler: sched, auth: authManager, hub: hub}
	switch command {
	case "serve":
		return app.serve()
	case "backup":
		return app.backup(args)
	case "snapshots":
		return app.snapshots(args)
	case "restore":
		return app.restore(args)
	case "check":
		return app.check(args)
	case "doctor":
		return app.doctor()
	case "import-v1":
		return app.importV1(args)
	case "help", "--help", "-h":
		usage()
		return nil
	default:
		return fmt.Errorf("unknown command %q", command)
	}
}

func (a application) serve() error {
	lockFile, err := os.OpenFile(a.cfg.ServiceLockPath(), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return err
	}
	defer lockFile.Close()
	if err := syscall.Flock(int(lockFile.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return errors.New("another vback service is already using this data directory")
	}
	defer syscall.Flock(int(lockFile.Fd()), syscall.LOCK_UN)
	if err := a.store.RecoverInterruptedRuns(context.Background()); err != nil {
		return err
	}
	token, err := a.auth.EnsureSetupToken()
	if err != nil {
		return err
	}
	if token != "" {
		log.Printf("First-run setup token: %s", token)
	}
	if err := a.scheduler.Reload(context.Background()); err != nil {
		log.Printf("scheduler disabled: %v", err)
	}
	defer a.scheduler.Stop()
	srv := server.New(a.cfg, a.store, a.runner, a.hub, a.auth, a.scheduler)
	scheme := "http"
	if a.cfg.TLSCert != "" {
		scheme = "https"
	}
	log.Printf("vback %s listening on %s://%s", version, scheme, a.cfg.Listen)
	err = srv.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

func (a application) backup(args []string) error {
	flags := flag.NewFlagSet("backup", flag.ContinueOnError)
	dry := flags.Bool("dry-run", false, "preview without writing data")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 1 {
		return errors.New("usage: vback backup <job-id> [--dry-run]")
	}
	run, err := a.runner.StartBackup(context.Background(), flags.Arg(0), *dry)
	if err != nil {
		return err
	}
	fmt.Println(run.ID)
	for {
		time.Sleep(500 * time.Millisecond)
		current, err := a.store.Run(context.Background(), run.ID)
		if err != nil {
			return err
		}
		switch current.Status {
		case "success":
			return nil
		case "failed", "partial", "cancelled":
			return fmt.Errorf("%s: %s", current.Status, current.Error)
		}
	}
}

func (a application) snapshots(args []string) error {
	if len(args) != 1 {
		return errors.New("usage: vback snapshots <job-id>")
	}
	items, err := a.runner.Snapshots(context.Background(), args[0])
	if err != nil {
		return err
	}
	return printJSON(items)
}

func (a application) restore(args []string) error {
	flags := flag.NewFlagSet("restore", flag.ContinueOnError)
	jobID := flags.String("job", "", "job id")
	include := flags.String("path", "", "optional path inside snapshot")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 1 || *jobID == "" {
		return errors.New("usage: vback restore <snapshot-id> --job <job-id> [--path <path>]")
	}
	run, err := a.runner.Restore(context.Background(), *jobID, flags.Arg(0), *include)
	if err != nil {
		return err
	}
	fmt.Println(run.ID)
	return nil
}

func (a application) check(args []string) error {
	if len(args) != 1 {
		return errors.New("usage: vback check <repository-id>")
	}
	run, err := a.runner.Check(context.Background(), args[0])
	if err != nil {
		return err
	}
	fmt.Println(run.ID)
	return nil
}

func (a application) doctor() error {
	result := map[string]any{"version": version, "data_dir": a.cfg.DataDir, "database": "ok", "listen": a.cfg.Listen}
	for name, path := range map[string]string{"restic": a.cfg.ResticPath, "sqlite3": a.cfg.SQLitePath} {
		resolved, err := exec.LookPath(path)
		if err != nil {
			result[name] = "missing"
		} else {
			result[name] = resolved
		}
	}
	return printJSON(result)
}

func (a application) importV1(args []string) error {
	flags := flag.NewFlagSet("import-v1", flag.ContinueOnError)
	from := flags.String("from", "", "v1 data directory")
	password := flags.String("restic-password", "", "restic repository password")
	confirm := flags.Bool("confirm", false, "write imported configuration")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *from == "" {
		return errors.New("usage: vback import-v1 --from <dir> [--confirm]")
	}
	doc, err := migratev1.LoadDir(*from)
	if err != nil {
		return err
	}
	preview := migratev1.Inspect(doc)
	if !*confirm {
		return printJSON(preview)
	}
	if *password == "" {
		return errors.New("--restic-password is required with --confirm; save it offline before importing")
	}
	imported, err := migratev1.Import(context.Background(), a.cfg, a.store, *from, *password)
	if err != nil {
		return err
	}
	return printJSON(imported)
}

func printJSON(value any) error {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	return encoder.Encode(value)
}
func usage() {
	fmt.Print(strings.TrimSpace(`
vback 2 — lightweight local backup panel

Usage:
  vback serve
  vback backup <job-id> [--dry-run]
  vback snapshots <job-id>
  vback restore <snapshot-id> --job <job-id> [--path <path>]
  vback check <repository-id>
  vback doctor
  vback import-v1 --from ~/.vback [--confirm --restic-password <password>]
  vback version
`) + "\n")
}
