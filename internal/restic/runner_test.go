package restic

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/caigg188/vback/internal/config"
	"github.com/caigg188/vback/internal/domain"
	"github.com/caigg188/vback/internal/events"
	"github.com/caigg188/vback/internal/secrets"
	"github.com/caigg188/vback/internal/store"
)

func TestBackupSuccessAndPartial(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell fixture")
	}
	for _, test := range []struct {
		name, exit, want string
	}{
		{"success", "0", "success"},
		{"partial", "3", "partial"},
	} {
		t.Run(test.name, func(t *testing.T) {
			cfg, st, runner, job := fixture(t, test.exit)
			_ = cfg
			run, err := runner.StartBackup(context.Background(), job.ID, false)
			if err != nil {
				t.Fatal(err)
			}
			deadline := time.Now().Add(5 * time.Second)
			for time.Now().Before(deadline) {
				current, err := st.Run(context.Background(), run.ID)
				if err != nil {
					t.Fatal(err)
				}
				if current.Status == test.want {
					if test.want == "success" && current.SnapshotID != "abc123" {
						t.Fatalf("snapshot id not recorded: %#v", current)
					}
					return
				}
				time.Sleep(20 * time.Millisecond)
			}
			current, _ := st.Run(context.Background(), run.ID)
			t.Fatalf("run did not reach %s: %#v", test.want, current)
		})
	}
}

func TestBackupCanBeCancelledImmediately(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell fixture")
	}
	cfg, st, runner, job := fixture(t, "0")
	script := "#!/bin/sh\nsleep 10\n"
	if err := os.WriteFile(cfg.ResticPath, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	run, err := runner.StartBackup(context.Background(), job.ID, false)
	if err != nil {
		t.Fatal(err)
	}
	if !runner.Cancel(run.ID) {
		t.Fatal("newly queued run was not cancellable")
	}
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		current, _ := st.Run(context.Background(), run.ID)
		if current.Status == "cancelled" {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	current, _ := st.Run(context.Background(), run.ID)
	t.Fatalf("run was not cancelled: %#v", current)
}

func fixture(t *testing.T, exitCode string) (config.Config, *store.Store, *Runner, domain.Job) {
	t.Helper()
	dir := t.TempDir()
	fake := filepath.Join(dir, "restic")
	script := "#!/bin/sh\n" +
		"if [ \"$1\" = backup ]; then\n" +
		"echo '{\"message_type\":\"status\",\"total_files\":2,\"files_done\":1,\"total_bytes\":100,\"bytes_done\":50}'\n" +
		"echo '{\"message_type\":\"summary\",\"snapshot_id\":\"abc123\",\"data_added\":42,\"total_files_processed\":2,\"total_bytes_processed\":100}'\n" +
		"exit " + exitCode + "\nfi\nexit 0\n"
	if err := os.WriteFile(fake, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	cfg := config.Config{DataDir: dir, ResticPath: fake, SQLitePath: "sqlite3"}
	if err := cfg.EnsureDirs(); err != nil {
		t.Fatal(err)
	}
	st, err := store.Open(cfg.DBPath())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	repoID := uuid.NewString()
	secretPath, err := secrets.Write(cfg.SecretDir(), repoID, domain.Secret{AccessKey: "key", SecretKey: "secret", ResticPassword: "password"})
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC()
	repo := domain.Repository{ID: repoID, Name: "test", Endpoint: "localhost:9000", Bucket: "backup", Prefix: "v2", Region: "us-east-1", SecretFile: secretPath, Health: "unknown", CreatedAt: now, UpdatedAt: now}
	if err := st.UpsertRepository(context.Background(), repo); err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(dir, "source")
	if err := os.Mkdir(source, 0o700); err != nil {
		t.Fatal(err)
	}
	job := domain.Job{ID: uuid.NewString(), Name: "test", RepositoryID: repoID, Sources: []domain.Source{{Path: source, Alias: "source"}}, Retention: domain.Retention{Last: 7}, CreatedAt: now, UpdatedAt: now}
	if err := st.UpsertJob(context.Background(), job); err != nil {
		t.Fatal(err)
	}
	return cfg, st, New(cfg, st, events.New()), job
}
