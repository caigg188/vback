package restic

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/google/uuid"

	"github.com/caigg188/vback/internal/config"
	"github.com/caigg188/vback/internal/domain"
	"github.com/caigg188/vback/internal/events"
	"github.com/caigg188/vback/internal/secrets"
	"github.com/caigg188/vback/internal/store"
)

type Runner struct {
	cfg    config.Config
	store  *store.Store
	hub    *events.Hub
	mu     sync.Mutex
	locks  map[string]*sync.Mutex
	active map[string]context.CancelFunc
}

func New(cfg config.Config, store *store.Store, hub *events.Hub) *Runner {
	return &Runner{cfg: cfg, store: store, hub: hub, locks: map[string]*sync.Mutex{}, active: map[string]context.CancelFunc{}}
}

func (r *Runner) StartBackup(ctx context.Context, jobID string, dryRun bool) (domain.Run, error) {
	job, err := r.store.Job(ctx, jobID)
	if err != nil {
		return domain.Run{}, err
	}
	run := domain.Run{
		ID: uuid.NewString(), JobID: job.ID, RepositoryID: job.RepositoryID,
		Kind: "backup", Status: "queued", StartedAt: time.Now().UTC(), DryRun: dryRun,
	}
	if err := r.store.CreateRun(ctx, run); err != nil {
		return run, err
	}
	r.emit(ctx, run.ID, "queued", "Backup queued", nil)
	runContext, cancel := context.WithCancel(context.Background())
	r.setActive(run.ID, cancel)
	go r.executeBackup(runContext, cancel, job, run)
	return run, nil
}

func (r *Runner) executeBackup(ctx context.Context, cancel context.CancelFunc, job domain.Job, run domain.Run) {
	lock := r.repoLock(job.RepositoryID)
	lock.Lock()
	defer lock.Unlock()

	defer cancel()
	defer r.removeActive(run.ID)

	if errors.Is(ctx.Err(), context.Canceled) {
		r.finish(run, "cancelled", errors.New("cancelled by user"))
		return
	}
	run.Status = "running"
	_ = r.store.UpdateRun(ctx, run)
	r.emit(ctx, run.ID, "started", "Backup started", nil)

	repo, err := r.store.Repository(ctx, job.RepositoryID)
	if err != nil {
		r.finishSetupError(ctx, run, err)
		return
	}
	args, cleanup, err := r.backupArgs(ctx, job, run)
	if err != nil {
		r.finishSetupError(ctx, run, err)
		return
	}
	defer cleanup()

	exitCode, err := r.runJSON(ctx, repo, run.ID, args, &run, job.LowResource)
	switch {
	case errors.Is(ctx.Err(), context.Canceled):
		r.finish(run, "cancelled", errors.New("cancelled by user"))
	case exitCode == 3:
		r.finish(run, "partial", fmt.Errorf("restic created an incomplete snapshot: %w", err))
	case err != nil:
		r.finish(run, "failed", err)
	default:
		if !run.DryRun {
			r.applyRetention(ctx, repo, job, run.ID)
		}
		r.finish(run, "success", nil)
	}
}

func (r *Runner) finishSetupError(ctx context.Context, run domain.Run, err error) {
	if errors.Is(ctx.Err(), context.Canceled) || errors.Is(err, context.Canceled) {
		r.finish(run, "cancelled", errors.New("cancelled by user"))
		return
	}
	r.finish(run, "failed", err)
}

func (r *Runner) backupArgs(ctx context.Context, job domain.Job, run domain.Run) ([]string, func(), error) {
	if len(job.Sources) == 0 {
		return nil, func() {}, errors.New("job has no sources")
	}
	args := []string{"backup", "--json", "--tag", "vback:" + job.ID}
	if job.LowResource {
		args = append(args, "-o", "s3.connections=2")
	}
	if run.DryRun {
		args = append(args, "--dry-run")
	}
	if job.OneFileSystem {
		args = append(args, "--one-file-system")
	}
	if job.BandwidthKB > 0 {
		args = append(args, "--limit-upload", strconv.Itoa(job.BandwidthKB))
	}
	for _, pattern := range job.Excludes {
		if strings.TrimSpace(pattern) != "" {
			args = append(args, "--exclude", pattern)
		}
	}
	cleanup := func() {}
	if len(job.SQLiteSources) > 0 {
		stage := filepath.Join(r.cfg.StagingDir(), run.ID, "sqlite")
		if err := os.MkdirAll(stage, 0o700); err != nil {
			return nil, cleanup, err
		}
		cleanup = func() { _ = os.RemoveAll(filepath.Join(r.cfg.StagingDir(), run.ID)) }
		for _, source := range job.SQLiteSources {
			alias := safeAlias(source.Alias)
			if alias == "" {
				alias = safeAlias(filepath.Base(source.Path))
			}
			if alias == "" {
				return nil, cleanup, fmt.Errorf("invalid sqlite alias for %s", source.Path)
			}
			target := filepath.Join(stage, alias)
			cmd := exec.CommandContext(ctx, r.cfg.SQLitePath, source.Path, ".backup "+quoteSQLite(target))
			output, err := cmd.CombinedOutput()
			if err != nil {
				return nil, cleanup, fmt.Errorf("sqlite backup %s: %s", source.Path, redact(string(output)))
			}
		}
		args = append(args, stage)
	}
	for _, source := range job.Sources {
		info, err := os.Stat(source.Path)
		if err != nil {
			return nil, cleanup, fmt.Errorf("source %s: %w", source.Path, err)
		}
		if !info.IsDir() && !info.Mode().IsRegular() {
			return nil, cleanup, fmt.Errorf("unsupported source type: %s", source.Path)
		}
		args = append(args, source.Path)
	}
	return args, cleanup, nil
}

func (r *Runner) runJSON(ctx context.Context, repo domain.Repository, runID string, args []string, run *domain.Run, lowResource bool) (int, error) {
	cmd, cleanup, err := r.command(ctx, repo, args...)
	if err != nil {
		return -1, err
	}
	defer cleanup()
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return -1, err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return -1, err
	}
	if err := cmd.Start(); err != nil {
		return -1, err
	}
	go r.scanErrors(ctx, runID, stderr)
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 64*1024), 2*1024*1024)
	lastProgress := time.Time{}
	for scanner.Scan() {
		line := append([]byte(nil), scanner.Bytes()...)
		var message struct {
			MessageType         string  `json:"message_type"`
			PercentDone         float64 `json:"percent_done"`
			TotalFiles          int64   `json:"total_files"`
			FilesDone           int64   `json:"files_done"`
			TotalBytes          int64   `json:"total_bytes"`
			BytesDone           int64   `json:"bytes_done"`
			SnapshotID          string  `json:"snapshot_id"`
			DataAdded           int64   `json:"data_added"`
			TotalFilesProcessed int64   `json:"total_files_processed"`
			TotalBytesProcessed int64   `json:"total_bytes_processed"`
		}
		if json.Unmarshal(line, &message) != nil {
			continue
		}
		switch message.MessageType {
		case "status":
			if lowResource && !lastProgress.IsZero() && time.Since(lastProgress) < 2*time.Second {
				continue
			}
			lastProgress = time.Now()
			run.BytesTotal, run.BytesDone, run.FilesTotal, run.FilesDone = message.TotalBytes, message.BytesDone, message.TotalFiles, message.FilesDone
			_ = r.store.UpdateRun(ctx, *run)
			r.emit(ctx, runID, "progress", "Backup progress", line)
		case "summary":
			run.SnapshotID = message.SnapshotID
			run.DataAdded = message.DataAdded
			if run.BytesTotal == 0 {
				run.BytesTotal = message.TotalBytesProcessed
			}
			if run.FilesTotal == 0 {
				run.FilesTotal = message.TotalFilesProcessed
			}
			run.BytesDone, run.FilesDone = run.BytesTotal, run.FilesTotal
			_ = r.store.UpdateRun(ctx, *run)
			r.emit(ctx, runID, "summary", "Snapshot created", line)
		case "error":
			r.emit(ctx, runID, "warning", "restic reported a file error", line)
		}
	}
	waitErr := cmd.Wait()
	if scanErr := scanner.Err(); scanErr != nil && waitErr == nil {
		waitErr = scanErr
	}
	if waitErr == nil {
		return 0, nil
	}
	var exitErr *exec.ExitError
	if errors.As(waitErr, &exitErr) {
		return exitErr.ExitCode(), waitErr
	}
	return -1, waitErr
}

func (r *Runner) scanErrors(ctx context.Context, runID string, reader io.Reader) {
	scanner := bufio.NewScanner(reader)
	for scanner.Scan() {
		line := strings.TrimSpace(redact(scanner.Text()))
		if line != "" {
			r.emit(ctx, runID, "log", line, nil)
		}
	}
}

func (r *Runner) finish(run domain.Run, status string, runErr error) {
	now := time.Now().UTC()
	run.Status = status
	run.FinishedAt = &now
	if runErr != nil {
		run.Error = redact(runErr.Error())
	}
	_ = r.store.UpdateRun(context.Background(), run)
	message := "Run completed"
	if runErr != nil {
		message = run.Error
	}
	r.emit(context.Background(), run.ID, status, message, nil)
	if status == "failed" || status == "partial" {
		go r.notifyFailure(run)
	}
}

func (r *Runner) notifyFailure(run domain.Run) {
	url, err := r.store.Setting(context.Background(), "webhook_url")
	if err != nil || strings.TrimSpace(url) == "" {
		return
	}
	payload, _ := json.Marshal(map[string]any{
		"event": "vback.run_failed", "run_id": run.ID, "job_id": run.JobID,
		"repository_id": run.RepositoryID, "status": run.Status, "error": run.Error,
		"time": time.Now().UTC().Format(time.RFC3339),
	})
	request, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return
	}
	request.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 10 * time.Second}
	response, err := client.Do(request)
	if err == nil {
		_ = response.Body.Close()
	}
}

func (r *Runner) applyRetention(ctx context.Context, repo domain.Repository, job domain.Job, runID string) {
	p := job.Retention
	args := []string{"forget", "--tag", "vback:" + job.ID, "--group-by", "tags"}
	add := func(flag string, n int) {
		if n > 0 {
			args = append(args, flag, strconv.Itoa(n))
		}
	}
	add("--keep-last", p.Last)
	add("--keep-hourly", p.Hourly)
	add("--keep-daily", p.Daily)
	add("--keep-weekly", p.Weekly)
	add("--keep-monthly", p.Monthly)
	if len(args) == 5 {
		return
	}
	cmd, cleanup, err := r.command(ctx, repo, args...)
	if err != nil {
		return
	}
	defer cleanup()
	output, err := cmd.CombinedOutput()
	if err != nil {
		r.emit(ctx, runID, "warning", "Retention failed: "+redact(string(output)), nil)
	} else {
		r.emit(ctx, runID, "retention", "Retention policy applied", nil)
	}
}

func (r *Runner) Snapshots(ctx context.Context, jobID string) ([]domain.Snapshot, error) {
	job, err := r.store.Job(ctx, jobID)
	if err != nil {
		return nil, err
	}
	repo, err := r.store.Repository(ctx, job.RepositoryID)
	if err != nil {
		return nil, err
	}
	cmd, cleanup, err := r.command(ctx, repo, "snapshots", "--json", "--tag", "vback:"+job.ID)
	if err != nil {
		return nil, err
	}
	defer cleanup()
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	var snapshots []domain.Snapshot
	if err := json.Unmarshal(output, &snapshots); err != nil {
		return nil, err
	}
	return snapshots, nil
}

func (r *Runner) SnapshotFiles(ctx context.Context, jobID, snapshotID, prefix string) ([]domain.SnapshotFile, error) {
	job, err := r.store.Job(ctx, jobID)
	if err != nil {
		return nil, err
	}
	repo, err := r.store.Repository(ctx, job.RepositoryID)
	if err != nil {
		return nil, err
	}
	args := []string{"ls", "--json", snapshotID}
	if strings.TrimSpace(prefix) != "" {
		args = append(args, prefix)
	}
	cmd, cleanup, err := r.command(ctx, repo, args...)
	if err != nil {
		return nil, err
	}
	defer cleanup()
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 64*1024), 2*1024*1024)
	var files []domain.SnapshotFile
	for scanner.Scan() {
		var node struct {
			MessageType string    `json:"message_type"`
			StructType  string    `json:"struct_type"`
			Path        string    `json:"path"`
			Name        string    `json:"name"`
			Type        string    `json:"type"`
			Size        int64     `json:"size"`
			ModTime     time.Time `json:"mtime"`
		}
		if json.Unmarshal(scanner.Bytes(), &node) != nil {
			continue
		}
		if node.StructType != "node" && node.MessageType != "node" {
			continue
		}
		if len(files) < 500 {
			files = append(files, domain.SnapshotFile{Path: node.Path, Name: node.Name, Type: node.Type, Size: node.Size, ModifiedAt: node.ModTime})
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if err := cmd.Wait(); err != nil {
		return nil, fmt.Errorf("browse snapshot: %s", redact(stderr.String()))
	}
	return files, nil
}

func (r *Runner) Dump(ctx context.Context, jobID, snapshotID, filePath string) (io.ReadCloser, func() error, error) {
	if strings.TrimSpace(filePath) == "" || unsafeSnapshotPath(filePath) {
		return nil, func() error { return nil }, errors.New("a safe snapshot file path is required")
	}
	job, err := r.store.Job(ctx, jobID)
	if err != nil {
		return nil, func() error { return nil }, err
	}
	repo, err := r.store.Repository(ctx, job.RepositoryID)
	if err != nil {
		return nil, func() error { return nil }, err
	}
	cmd, cleanup, err := r.command(ctx, repo, "dump", snapshotID, filePath)
	if err != nil {
		return nil, func() error { return nil }, err
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		cleanup()
		return nil, func() error { return nil }, err
	}
	if err := cmd.Start(); err != nil {
		cleanup()
		return nil, func() error { return nil }, err
	}
	finish := func() error {
		defer cleanup()
		if err := cmd.Wait(); err != nil {
			return fmt.Errorf("snapshot download: %s", redact(stderr.String()))
		}
		return nil
	}
	return stdout, finish, nil
}

func (r *Runner) Diff(ctx context.Context, jobID, snapshotA, snapshotB string) (json.RawMessage, error) {
	job, err := r.store.Job(ctx, jobID)
	if err != nil {
		return nil, err
	}
	repo, err := r.store.Repository(ctx, job.RepositoryID)
	if err != nil {
		return nil, err
	}
	cmd, cleanup, err := r.command(ctx, repo, "diff", "--json", snapshotA, snapshotB)
	if err != nil {
		return nil, err
	}
	defer cleanup()
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	scanner := bufio.NewScanner(bytes.NewReader(output))
	scanner.Buffer(make([]byte, 64*1024), 2*1024*1024)
	items := make([]json.RawMessage, 0)
	for scanner.Scan() {
		line := append([]byte(nil), scanner.Bytes()...)
		if len(bytes.TrimSpace(line)) == 0 {
			continue
		}
		if !json.Valid(line) {
			return nil, errors.New("restic returned invalid diff JSON")
		}
		items = append(items, line)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return json.Marshal(items)
}

func (r *Runner) Check(ctx context.Context, repositoryID string) (domain.Run, error) {
	return r.startCheck(ctx, repositoryID, false)
}

func (r *Runner) FullCheck(ctx context.Context, repositoryID string) (domain.Run, error) {
	return r.startCheck(ctx, repositoryID, true)
}

func (r *Runner) startCheck(ctx context.Context, repositoryID string, readData bool) (domain.Run, error) {
	repo, err := r.store.Repository(ctx, repositoryID)
	if err != nil {
		return domain.Run{}, err
	}
	kind := "check"
	args := []string{"check", "--json"}
	if readData {
		kind = "check-full"
		args = append(args, "--read-data")
	}
	run := domain.Run{ID: uuid.NewString(), RepositoryID: repositoryID, Kind: kind, Status: "queued", StartedAt: time.Now().UTC()}
	if err := r.store.CreateRun(ctx, run); err != nil {
		return run, err
	}
	lock := r.repoLock(repositoryID)
	runContext, cancel := context.WithCancel(context.Background())
	r.setActive(run.ID, cancel)
	go func() {
		defer cancel()
		defer r.removeActive(run.ID)
		lock.Lock()
		defer lock.Unlock()
		run.Status = "running"
		_ = r.store.UpdateRun(context.Background(), run)
		cmd, cleanup, err := r.command(runContext, repo, args...)
		if err == nil {
			output, commandErr := cmd.CombinedOutput()
			if commandErr != nil {
				err = fmt.Errorf("%s: %s", kind, redact(string(output)))
			}
		}
		cleanup()
		if errors.Is(runContext.Err(), context.Canceled) {
			r.finish(run, "cancelled", errors.New("cancelled by user"))
		} else if err != nil {
			_ = r.store.SetRepositoryHealth(context.Background(), repo.ID, "error")
			r.finish(run, "failed", err)
		} else {
			_ = r.store.SetRepositoryHealth(context.Background(), repo.ID, "healthy")
			r.finish(run, "success", nil)
		}
	}()
	return run, nil
}

func (r *Runner) InitRepository(ctx context.Context, repositoryID string) error {
	ctx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	repo, err := r.store.Repository(ctx, repositoryID)
	if err != nil {
		return err
	}
	lock := r.repoLock(repositoryID)
	lock.Lock()
	defer lock.Unlock()

	cmd, cleanup, err := r.command(ctx, repo, "init", "--repository-version", "2")
	if err != nil {
		return err
	}
	defer cleanup()
	output, err := cmd.CombinedOutput()
	if err != nil {
		text := strings.ToLower(string(output))
		if strings.Contains(text, "already initialized") || strings.Contains(text, "config file already exists") {
			probe, probeCleanup, probeErr := r.command(ctx, repo, "snapshots", "--json", "--latest", "1")
			if probeErr != nil {
				return probeErr
			}
			probeOutput, probeErr := probe.CombinedOutput()
			probeCleanup()
			if probeErr != nil {
				return fmt.Errorf("repository exists but credentials or recovery key are invalid: %s", redact(string(probeOutput)))
			}
			_ = r.store.SetRepositoryHealth(ctx, repositoryID, "healthy")
			return nil
		}
		return fmt.Errorf("initialize repository: %s", redact(string(output)))
	}
	_ = r.store.SetRepositoryHealth(ctx, repositoryID, "healthy")
	return nil
}

func (r *Runner) TestRepository(ctx context.Context, repositoryID string) error {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	repo, err := r.store.Repository(ctx, repositoryID)
	if err != nil {
		return err
	}
	cmd, cleanup, err := r.command(ctx, repo, "snapshots", "--json", "--latest", "1")
	if err != nil {
		return err
	}
	defer cleanup()
	output, err := cmd.CombinedOutput()
	if err != nil {
		_ = r.store.SetRepositoryHealth(ctx, repositoryID, "error")
		return fmt.Errorf("repository test failed: %s", redact(string(output)))
	}
	_ = r.store.SetRepositoryHealth(ctx, repositoryID, "healthy")
	return nil
}

func (r *Runner) Restore(ctx context.Context, jobID, snapshotID, path string) (domain.Run, error) {
	job, err := r.store.Job(ctx, jobID)
	if err != nil {
		return domain.Run{}, err
	}
	repo, err := r.store.Repository(ctx, job.RepositoryID)
	if err != nil {
		return domain.Run{}, err
	}
	run := domain.Run{ID: uuid.NewString(), JobID: job.ID, RepositoryID: repo.ID, Kind: "restore", Status: "queued", StartedAt: time.Now().UTC()}
	if err := r.store.CreateRun(ctx, run); err != nil {
		return run, err
	}
	target := filepath.Join(r.cfg.RestoreDir(), run.ID)
	lock := r.repoLock(repo.ID)
	runContext, cancel := context.WithCancel(context.Background())
	r.setActive(run.ID, cancel)
	go func() {
		defer cancel()
		defer r.removeActive(run.ID)
		lock.Lock()
		defer lock.Unlock()
		run.Status = "running"
		_ = r.store.UpdateRun(context.Background(), run)
		if err := r.ensureRestoreSpace(runContext, repo, snapshotID); err != nil {
			r.finishSetupError(runContext, run, err)
			return
		}
		args := []string{"restore", snapshotID, "--target", target, "--json"}
		if strings.TrimSpace(path) != "" {
			if unsafeSnapshotPath(path) {
				r.finish(run, "failed", errors.New("restore path contains an unsafe parent segment"))
				return
			}
			args = append(args, "--include", path)
		}
		cmd, cleanup, err := r.command(runContext, repo, args...)
		if err == nil {
			output, commandErr := cmd.CombinedOutput()
			if commandErr != nil {
				err = fmt.Errorf("restore: %s", redact(string(output)))
			}
		}
		cleanup()
		if errors.Is(runContext.Err(), context.Canceled) {
			r.finish(run, "cancelled", errors.New("cancelled by user"))
		} else if err != nil {
			r.finish(run, "failed", err)
		} else {
			r.emit(context.Background(), run.ID, "restore", "Cryptographically verified restore completed at "+target, nil)
			r.finish(run, "success", nil)
		}
	}()
	return run, nil
}

func (r *Runner) ensureRestoreSpace(ctx context.Context, repo domain.Repository, snapshotID string) error {
	cmd, cleanup, err := r.command(ctx, repo, "stats", "--mode", "restore-size", "--json", snapshotID)
	if err != nil {
		return err
	}
	output, err := cmd.CombinedOutput()
	cleanup()
	if err != nil {
		return fmt.Errorf("estimate restore size: %s", redact(string(output)))
	}
	var stats struct {
		TotalSize int64 `json:"total_size"`
	}
	if err := json.Unmarshal(output, &stats); err != nil {
		return fmt.Errorf("parse restore size: %w", err)
	}
	var filesystem syscall.Statfs_t
	if err := syscall.Statfs(r.cfg.RestoreDir(), &filesystem); err != nil {
		return fmt.Errorf("check restore space: %w", err)
	}
	available := uint64(filesystem.Bavail) * uint64(filesystem.Bsize)
	required := uint64(max(stats.TotalSize, 0))
	reserve := required / 20
	if reserve < 16*1024*1024 {
		reserve = 16 * 1024 * 1024
	}
	if available < required+reserve {
		return fmt.Errorf("insufficient restore space: need %d bytes plus reserve, have %d bytes", required, available)
	}
	return nil
}

func (r *Runner) Maintenance(ctx context.Context, repositoryID, action string) (domain.Run, error) {
	var args []string
	switch action {
	case "prune":
		args = []string{"prune"}
	case "unlock":
		args = []string{"unlock"}
	default:
		return domain.Run{}, errors.New("maintenance action must be prune or unlock")
	}
	repo, err := r.store.Repository(ctx, repositoryID)
	if err != nil {
		return domain.Run{}, err
	}
	run := domain.Run{ID: uuid.NewString(), RepositoryID: repositoryID, Kind: action, Status: "queued", StartedAt: time.Now().UTC()}
	if err := r.store.CreateRun(ctx, run); err != nil {
		return run, err
	}
	lock := r.repoLock(repositoryID)
	runContext, cancel := context.WithCancel(context.Background())
	r.setActive(run.ID, cancel)
	go func() {
		defer cancel()
		defer r.removeActive(run.ID)
		lock.Lock()
		defer lock.Unlock()
		run.Status = "running"
		_ = r.store.UpdateRun(context.Background(), run)
		cmd, cleanup, err := r.command(runContext, repo, args...)
		if err == nil {
			output, commandErr := cmd.CombinedOutput()
			if commandErr != nil {
				err = fmt.Errorf("%s: %s", action, redact(string(output)))
			}
		}
		cleanup()
		if errors.Is(runContext.Err(), context.Canceled) {
			r.finish(run, "cancelled", errors.New("cancelled by user"))
		} else if err != nil {
			r.finish(run, "failed", err)
		} else {
			r.finish(run, "success", nil)
		}
	}()
	return run, nil
}

func (r *Runner) Cancel(runID string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	cancel, ok := r.active[runID]
	if ok {
		cancel()
	}
	return ok
}

func (r *Runner) setActive(runID string, cancel context.CancelFunc) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.active[runID] = cancel
}

func (r *Runner) removeActive(runID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.active, runID)
}

func (r *Runner) command(ctx context.Context, repo domain.Repository, args ...string) (*exec.Cmd, func(), error) {
	secret, err := secrets.Read(repo.SecretFile)
	if err != nil {
		return nil, func() {}, err
	}
	passwordFile, err := secrets.PasswordFile(repo.SecretFile)
	if err != nil {
		return nil, func() {}, err
	}
	cleanup := func() { _ = os.Remove(passwordFile) }
	endpoint := strings.TrimSuffix(repo.Endpoint, "/")
	endpoint = strings.TrimPrefix(strings.TrimPrefix(endpoint, "https://"), "http://")
	scheme := "https://"
	if strings.HasPrefix(repo.Endpoint, "http://") {
		scheme = "http://"
	}
	repository := "s3:" + scheme + endpoint + "/" + strings.Trim(repo.Bucket, "/")
	if prefix := strings.Trim(repo.Prefix, "/"); prefix != "" {
		repository += "/" + prefix
	}
	cmd := exec.CommandContext(ctx, r.cfg.ResticPath, args...)
	cmd.Env = append(os.Environ(),
		"RESTIC_REPOSITORY="+repository,
		"RESTIC_PASSWORD_FILE="+passwordFile,
		"AWS_ACCESS_KEY_ID="+secret.AccessKey,
		"AWS_SECRET_ACCESS_KEY="+secret.SecretKey,
		"AWS_DEFAULT_REGION="+repo.Region,
		"TMPDIR="+r.cfg.StagingDir(),
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return os.ErrProcessDone
		}
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
	}
	cmd.WaitDelay = 5 * time.Second
	return cmd, cleanup, nil
}

func (r *Runner) repoLock(id string) *sync.Mutex {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.locks[id] == nil {
		r.locks[id] = &sync.Mutex{}
	}
	return r.locks[id]
}

func (r *Runner) emit(ctx context.Context, runID, eventType, message string, data []byte) {
	event, err := r.store.AppendEvent(ctx, domain.Event{RunID: runID, Time: time.Now().UTC(), Type: eventType, Message: redact(message), Data: data})
	if err == nil {
		r.hub.Publish(event)
	}
}

func safeAlias(value string) string {
	value = strings.TrimSpace(value)
	if value == "" || value == "." || value == ".." {
		return ""
	}
	value = filepath.Base(value)
	if strings.ContainsAny(value, `/\\`) {
		return ""
	}
	return value
}

func quoteSQLite(value string) string { return "'" + strings.ReplaceAll(value, "'", "''") + "'" }

func unsafeSnapshotPath(value string) bool {
	if strings.ContainsRune(value, '\x00') {
		return true
	}
	for _, segment := range strings.FieldsFunc(value, func(r rune) bool { return r == '/' || r == '\\' }) {
		if segment == ".." {
			return true
		}
	}
	return false
}

func redact(value string) string {
	for _, marker := range []string{"AWS_SECRET_ACCESS_KEY", "RESTIC_PASSWORD", "secret_key", "password", "cookie"} {
		if strings.Contains(strings.ToLower(value), strings.ToLower(marker)) {
			return "sensitive output redacted"
		}
	}
	return strings.TrimSpace(value)
}
