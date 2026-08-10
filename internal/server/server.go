package server

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"net/url"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/robfig/cron/v3"

	"github.com/caigg188/vback/internal/auth"
	"github.com/caigg188/vback/internal/config"
	"github.com/caigg188/vback/internal/domain"
	"github.com/caigg188/vback/internal/events"
	"github.com/caigg188/vback/internal/restic"
	"github.com/caigg188/vback/internal/scheduler"
	"github.com/caigg188/vback/internal/secrets"
	"github.com/caigg188/vback/internal/store"
	"github.com/caigg188/vback/internal/webui"
)

type Server struct {
	cfg       config.Config
	store     *store.Store
	runner    *restic.Runner
	hub       *events.Hub
	auth      *auth.Manager
	scheduler *scheduler.Scheduler
	mux       *http.ServeMux
}

func New(cfg config.Config, st *store.Store, runner *restic.Runner, hub *events.Hub, authManager *auth.Manager, sched *scheduler.Scheduler) *Server {
	s := &Server{cfg: cfg, store: st, runner: runner, hub: hub, auth: authManager, scheduler: sched, mux: http.NewServeMux()}
	s.routes()
	return s
}

func (s *Server) Handler() http.Handler { return securityHeaders(s.auth.Middleware(s.mux)) }

func (s *Server) ListenAndServe() error {
	server := &http.Server{Addr: s.cfg.Listen, Handler: s.Handler(), ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 90 * time.Second, MaxHeaderBytes: 1 << 20}
	if s.cfg.TLSCert != "" && s.cfg.TLSKey != "" {
		return server.ListenAndServeTLS(s.cfg.TLSCert, s.cfg.TLSKey)
	}
	return server.ListenAndServe()
}

func (s *Server) routes() {
	s.mux.HandleFunc("/api/v1/health", s.health)
	s.mux.HandleFunc("/api/v1/setup", s.setup)
	s.mux.HandleFunc("/api/v1/login", s.login)
	s.mux.HandleFunc("/api/v1/logout", s.logout)
	s.mux.HandleFunc("/api/v1/session", s.session)
	s.mux.HandleFunc("/api/v1/overview", s.overview)
	s.mux.HandleFunc("/api/v1/repositories", s.repositories)
	s.mux.HandleFunc("/api/v1/repositories/", s.repositoryAction)
	s.mux.HandleFunc("/api/v1/jobs", s.jobs)
	s.mux.HandleFunc("/api/v1/jobs/", s.jobAction)
	s.mux.HandleFunc("/api/v1/runs", s.runs)
	s.mux.HandleFunc("/api/v1/runs/", s.runAction)
	s.mux.HandleFunc("/api/v1/snapshots", s.snapshots)
	s.mux.HandleFunc("/api/v1/snapshots/", s.snapshotAction)
	s.mux.HandleFunc("/api/v1/restore", s.restore)
	s.mux.HandleFunc("/api/v1/maintenance", s.maintenance)
	s.mux.HandleFunc("/api/v1/settings", s.settings)
	static, _ := fs.Sub(webui.Files, "dist")
	fileServer := http.FileServer(http.FS(static))
	s.mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/") {
			notFound(w)
			return
		}
		name := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if name == "" {
			name = "index.html"
		}
		if _, err := fs.Stat(static, name); err != nil {
			name = "index.html"
			r.URL.Path = "/" + name
		}
		fileServer.ServeHTTP(w, r)
	})
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, map[string]any{"status": "ok", "version": "2.0.0-dev", "setup_required": !s.store.IsSetup(r.Context())})
}

func (s *Server) setup(w http.ResponseWriter, r *http.Request) {
	if r.Method == "GET" {
		writeJSON(w, 200, map[string]bool{"setup_required": !s.store.IsSetup(r.Context())})
		return
	}
	if r.Method != "POST" {
		methodNotAllowed(w)
		return
	}
	var input struct {
		Token    string `json:"token"`
		Password string `json:"password"`
	}
	if !decode(w, r, &input) {
		return
	}
	if err := s.auth.Setup(r.Context(), input.Token, input.Password); err != nil {
		writeError(w, 400, err)
		return
	}
	writeJSON(w, 201, map[string]string{"status": "configured"})
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		methodNotAllowed(w)
		return
	}
	var input struct {
		Password string `json:"password"`
	}
	if !decode(w, r, &input) {
		return
	}
	token, csrf, err := s.auth.Login(r.Context(), input.Password)
	if err != nil {
		writeError(w, 401, err)
		return
	}
	http.SetCookie(w, &http.Cookie{Name: "vback_session", Value: token, Path: "/", HttpOnly: true, Secure: secureRequest(r), SameSite: http.SameSiteStrictMode, MaxAge: 86400})
	writeJSON(w, 200, map[string]string{"csrf_token": csrf})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		methodNotAllowed(w)
		return
	}
	if cookie, err := r.Cookie("vback_session"); err == nil {
		_ = s.auth.Logout(r.Context(), cookie.Value)
	}
	http.SetCookie(w, &http.Cookie{Name: "vback_session", Value: "", Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode, MaxAge: -1})
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) session(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		methodNotAllowed(w)
		return
	}
	writeJSON(w, 200, map[string]string{"csrf_token": auth.CSRF(r.Context())})
}

func (s *Server) overview(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		methodNotAllowed(w)
		return
	}
	value, err := s.store.Overview(r.Context())
	if err != nil {
		writeError(w, 500, err)
		return
	}
	writeJSON(w, 200, value)
}

func (s *Server) repositories(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case "GET":
		items, err := s.store.Repositories(r.Context())
		if err != nil {
			writeError(w, 500, err)
			return
		}
		writeJSON(w, 200, items)
	case "POST":
		var input domain.RepositoryInput
		if !decode(w, r, &input) {
			return
		}
		if strings.TrimSpace(input.Name) == "" || strings.TrimSpace(input.Endpoint) == "" || strings.TrimSpace(input.Bucket) == "" {
			writeError(w, 400, errors.New("name, endpoint and bucket are required"))
			return
		}
		endpointURL := input.Endpoint
		if !strings.Contains(endpointURL, "://") {
			endpointURL = "https://" + endpointURL
		}
		parsedEndpoint, endpointErr := url.Parse(endpointURL)
		if endpointErr != nil || parsedEndpoint.Host == "" || (parsedEndpoint.Scheme != "http" && parsedEndpoint.Scheme != "https") || parsedEndpoint.User != nil || parsedEndpoint.RawQuery != "" || parsedEndpoint.Fragment != "" {
			writeError(w, 400, errors.New("endpoint must be an HTTP(S) URL without embedded credentials"))
			return
		}
		if strings.Contains(input.Prefix, "..") {
			writeError(w, 400, errors.New("repository prefix may not contain '..'"))
			return
		}
		now := time.Now().UTC()
		id := input.ID
		if id == "" {
			id = uuid.NewString()
		}
		secretPath := ""
		if old, err := s.store.Repository(r.Context(), id); err == nil {
			secretPath = old.SecretFile
		}
		if input.AccessKey != "" || input.SecretKey != "" || input.ResticPassword != "" {
			if secretPath == "" {
				secretPath = filepath.Join(s.cfg.SecretDir(), id+".json")
			}
			existing := domain.Secret{}
			if old, err := secrets.Read(secretPath); err == nil {
				existing = old
			}
			if input.AccessKey != "" {
				existing.AccessKey = input.AccessKey
			}
			if input.SecretKey != "" {
				existing.SecretKey = input.SecretKey
			}
			if input.ResticPassword != "" {
				existing.ResticPassword = input.ResticPassword
			}
			var err error
			secretPath, err = secrets.Write(s.cfg.SecretDir(), id, existing)
			if err != nil {
				writeError(w, 500, err)
				return
			}
		}
		repo := domain.Repository{ID: id, Name: input.Name, Provider: input.Provider, Endpoint: input.Endpoint, Bucket: input.Bucket, Prefix: strings.Trim(input.Prefix, "/"), Region: input.Region, SecretFile: secretPath, Health: "unknown", CreatedAt: now, UpdatedAt: now}
		if old, err := s.store.Repository(r.Context(), id); err == nil {
			repo.CreatedAt = old.CreatedAt
		}
		if err := s.store.UpsertRepository(r.Context(), repo); err != nil {
			writeError(w, 500, err)
			return
		}
		_ = s.store.Audit(r.Context(), "upsert", "repository", id, "repository configuration updated")
		saved, _ := s.store.Repository(r.Context(), id)
		writeJSON(w, 201, saved)
	default:
		methodNotAllowed(w)
	}
}

func (s *Server) repositoryAction(w http.ResponseWriter, r *http.Request) {
	parts := splitTail(r.URL.Path, "/api/v1/repositories/")
	if len(parts) < 2 {
		notFound(w)
		return
	}
	id, action := parts[0], parts[1]
	if r.Method == "POST" && action == "init" {
		if err := s.runner.InitRepository(r.Context(), id); err != nil {
			writeError(w, 400, err)
			return
		}
		writeJSON(w, 200, map[string]string{"status": "initialized"})
		return
	}
	if r.Method == "POST" && action == "test" {
		if err := s.runner.TestRepository(r.Context(), id); err != nil {
			writeError(w, 400, err)
			return
		}
		writeJSON(w, 200, map[string]string{"status": "healthy"})
		return
	}
	if r.Method == "POST" && action == "check" {
		run, err := s.runner.Check(r.Context(), id)
		if err != nil {
			writeError(w, 400, err)
			return
		}
		writeJSON(w, 202, run)
		return
	}
	notFound(w)
}

func (s *Server) jobs(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case "GET":
		items, err := s.store.Jobs(r.Context())
		if err != nil {
			writeError(w, 500, err)
			return
		}
		writeJSON(w, 200, items)
	case "POST":
		var input domain.Job
		if !decode(w, r, &input) {
			return
		}
		if input.ID == "" {
			input.ID = uuid.NewString()
		}
		if input.Name == "" || input.RepositoryID == "" || len(input.Sources) == 0 {
			writeError(w, 400, errors.New("name, repository and at least one source are required"))
			return
		}
		if input.Timezone == "" {
			input.Timezone = "UTC"
		}
		if input.Retention.Last == 0 && input.Retention.Daily == 0 {
			input.Retention.Last = 7
		}
		now := time.Now().UTC()
		if old, err := s.store.Job(r.Context(), input.ID); err == nil {
			input.CreatedAt = old.CreatedAt
		} else {
			input.CreatedAt = now
		}
		input.UpdatedAt = now
		if err := validateJob(input); err != nil {
			writeError(w, 400, err)
			return
		}
		if err := s.store.UpsertJob(r.Context(), input); err != nil {
			writeError(w, 500, err)
			return
		}
		if err := s.scheduler.Reload(r.Context()); err != nil {
			writeError(w, 400, err)
			return
		}
		_ = s.store.Audit(r.Context(), "upsert", "job", input.ID, "job configuration updated")
		saved, _ := s.store.Job(r.Context(), input.ID)
		writeJSON(w, 201, saved)
	default:
		methodNotAllowed(w)
	}
}

func (s *Server) jobAction(w http.ResponseWriter, r *http.Request) {
	parts := splitTail(r.URL.Path, "/api/v1/jobs/")
	if len(parts) == 0 {
		notFound(w)
		return
	}
	id := parts[0]
	if len(parts) == 1 && r.Method == "DELETE" {
		if err := s.store.DeleteJob(r.Context(), id); err != nil {
			writeError(w, 404, err)
			return
		}
		_ = s.scheduler.Reload(r.Context())
		w.WriteHeader(204)
		return
	}
	if len(parts) >= 2 && parts[1] == "run" && r.Method == "POST" {
		var input struct {
			DryRun bool `json:"dry_run"`
		}
		_ = json.NewDecoder(r.Body).Decode(&input)
		run, err := s.runner.StartBackup(r.Context(), id, input.DryRun)
		if err != nil {
			writeError(w, 400, err)
			return
		}
		writeJSON(w, 202, run)
		return
	}
	notFound(w)
}

func (s *Server) runs(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		methodNotAllowed(w)
		return
	}
	items, err := s.store.Runs(r.Context(), 100)
	if err != nil {
		writeError(w, 500, err)
		return
	}
	writeJSON(w, 200, items)
}

func (s *Server) runAction(w http.ResponseWriter, r *http.Request) {
	parts := splitTail(r.URL.Path, "/api/v1/runs/")
	if len(parts) == 0 {
		notFound(w)
		return
	}
	id := parts[0]
	if len(parts) == 1 && r.Method == "GET" {
		item, err := s.store.Run(r.Context(), id)
		if err != nil {
			writeError(w, 404, err)
			return
		}
		writeJSON(w, 200, item)
		return
	}
	if len(parts) >= 2 && parts[1] == "cancel" && r.Method == "POST" {
		if !s.runner.Cancel(id) {
			writeError(w, 409, errors.New("run is not active"))
			return
		}
		writeJSON(w, 202, map[string]string{"status": "cancelling"})
		return
	}
	if len(parts) >= 2 && parts[1] == "retry" && r.Method == "POST" {
		previous, err := s.store.Run(r.Context(), id)
		if err != nil {
			writeError(w, 404, err)
			return
		}
		if previous.Kind != "backup" || previous.JobID == "" || !strings.Contains("failed partial cancelled", previous.Status) {
			writeError(w, 409, errors.New("only failed, partial or cancelled backups can be retried"))
			return
		}
		run, err := s.runner.StartBackup(r.Context(), previous.JobID, previous.DryRun)
		if err != nil {
			writeError(w, 400, err)
			return
		}
		_ = s.store.Audit(r.Context(), "retry", "run", id, "created retry run "+run.ID)
		writeJSON(w, 202, run)
		return
	}
	if len(parts) >= 2 && parts[1] == "events" && r.Method == "GET" {
		s.runEvents(w, r, id)
		return
	}
	notFound(w)
}

func (s *Server) runEvents(w http.ResponseWriter, r *http.Request, runID string) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, 500, errors.New("streaming unsupported"))
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("X-Accel-Buffering", "no")
	after, _ := strconv.ParseInt(r.Header.Get("Last-Event-ID"), 10, 64)
	items, _ := s.store.Events(r.Context(), runID, after)
	for _, event := range items {
		writeSSE(w, event)
		after = event.Sequence
	}
	flusher.Flush()
	ch, unsubscribe := s.hub.Subscribe(runID)
	defer unsubscribe()
	heartbeat := time.NewTicker(20 * time.Second)
	defer heartbeat.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case event := <-ch:
			writeSSE(w, event)
			flusher.Flush()
		case <-heartbeat.C:
			fmt.Fprint(w, ": keepalive\n\n")
			flusher.Flush()
		}
	}
}

func (s *Server) snapshots(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		methodNotAllowed(w)
		return
	}
	jobID := r.URL.Query().Get("job_id")
	items, err := s.runner.Snapshots(r.Context(), jobID)
	if err != nil {
		writeError(w, 400, err)
		return
	}
	writeJSON(w, 200, items)
}

func (s *Server) snapshotAction(w http.ResponseWriter, r *http.Request) {
	action := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/snapshots/"), "/")
	jobID, snapshotID := r.URL.Query().Get("job_id"), r.URL.Query().Get("snapshot_id")
	switch {
	case action == "tree" && r.Method == "GET":
		items, err := s.runner.SnapshotFiles(r.Context(), jobID, snapshotID, r.URL.Query().Get("path"))
		if err != nil {
			writeError(w, 400, err)
			return
		}
		writeJSON(w, 200, items)
	case action == "download" && r.Method == "GET":
		filePath := r.URL.Query().Get("path")
		content, finish, err := s.runner.Dump(r.Context(), jobID, snapshotID, filePath)
		if err != nil {
			writeError(w, 400, err)
			return
		}
		defer content.Close()
		w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, strings.ReplaceAll(filepath.Base(filePath), `"`, "")))
		w.Header().Set("Content-Type", "application/octet-stream")
		_, _ = io.Copy(w, content)
		_ = finish()
	case action == "diff" && r.Method == "GET":
		diff, err := s.runner.Diff(r.Context(), jobID, r.URL.Query().Get("from"), r.URL.Query().Get("to"))
		if err != nil {
			writeError(w, 400, err)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(diff)
	default:
		notFound(w)
	}
}

func (s *Server) restore(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		methodNotAllowed(w)
		return
	}
	var input struct {
		JobID      string `json:"job_id"`
		SnapshotID string `json:"snapshot_id"`
		Path       string `json:"path"`
	}
	if !decode(w, r, &input) {
		return
	}
	run, err := s.runner.Restore(r.Context(), input.JobID, input.SnapshotID, input.Path)
	if err != nil {
		writeError(w, 400, err)
		return
	}
	writeJSON(w, 202, run)
}

func (s *Server) maintenance(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		methodNotAllowed(w)
		return
	}
	var input struct {
		RepositoryID string `json:"repository_id"`
		Action       string `json:"action"`
	}
	if !decode(w, r, &input) {
		return
	}
	if input.Action == "check" {
		run, err := s.runner.Check(r.Context(), input.RepositoryID)
		if err != nil {
			writeError(w, 400, err)
			return
		}
		writeJSON(w, 202, run)
		return
	}
	if input.Action == "full-check" {
		run, err := s.runner.FullCheck(r.Context(), input.RepositoryID)
		if err != nil {
			writeError(w, 400, err)
			return
		}
		writeJSON(w, 202, run)
		return
	}
	run, err := s.runner.Maintenance(r.Context(), input.RepositoryID, input.Action)
	if err != nil {
		writeError(w, 400, err)
		return
	}
	writeJSON(w, 202, run)
}

func (s *Server) settings(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case "GET":
		webhook, _ := s.store.Setting(r.Context(), "webhook_url")
		monthly, _ := s.store.Setting(r.Context(), "monthly_full_check")
		pruneSchedule, _ := s.store.Setting(r.Context(), "prune_schedule")
		writeJSON(w, 200, map[string]any{"webhook_url": webhook, "monthly_full_check": monthly == "true", "prune_schedule": pruneSchedule})
	case "POST":
		var input struct {
			WebhookURL       string `json:"webhook_url"`
			MonthlyFullCheck bool   `json:"monthly_full_check"`
			PruneSchedule    string `json:"prune_schedule"`
		}
		if !decode(w, r, &input) {
			return
		}
		if input.WebhookURL != "" {
			webhookURL, err := url.Parse(input.WebhookURL)
			if err != nil || webhookURL.Scheme != "https" || webhookURL.Host == "" || webhookURL.User != nil {
				writeError(w, 400, errors.New("webhook URL must be HTTPS and must not contain embedded credentials"))
				return
			}
		}
		if input.PruneSchedule != "" {
			if _, err := cron.ParseStandard(input.PruneSchedule); err != nil {
				writeError(w, 400, fmt.Errorf("prune schedule: %w", err))
				return
			}
		}
		if err := s.store.SetSetting(r.Context(), "webhook_url", strings.TrimSpace(input.WebhookURL)); err != nil {
			writeError(w, 500, err)
			return
		}
		_ = s.store.SetSetting(r.Context(), "monthly_full_check", strconv.FormatBool(input.MonthlyFullCheck))
		_ = s.store.SetSetting(r.Context(), "prune_schedule", strings.TrimSpace(input.PruneSchedule))
		if err := s.scheduler.Reload(r.Context()); err != nil {
			writeError(w, 400, err)
			return
		}
		writeJSON(w, 200, map[string]string{"status": "saved"})
	default:
		methodNotAllowed(w)
	}
}

func validateJob(job domain.Job) error {
	aliases := map[string]bool{}
	for _, source := range job.Sources {
		if !filepath.IsAbs(source.Path) {
			return fmt.Errorf("source must be absolute: %s", source.Path)
		}
		alias := source.Alias
		if alias == "" {
			alias = filepath.Base(source.Path)
		}
		if aliases[alias] {
			return fmt.Errorf("duplicate source alias: %s", alias)
		}
		aliases[alias] = true
	}
	if _, err := time.LoadLocation(job.Timezone); err != nil {
		return fmt.Errorf("timezone: %w", err)
	}
	if job.Schedule != "" {
		spec := job.Schedule
		if job.Timezone != "" {
			spec = "CRON_TZ=" + job.Timezone + " " + spec
		}
		if _, err := cron.ParseStandard(spec); err != nil {
			return fmt.Errorf("schedule: %w", err)
		}
	}
	return nil
}

func decode(w http.ResponseWriter, r *http.Request, value any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(value); err != nil {
		writeError(w, 400, err)
		return false
	}
	return true
}
func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]string{"error": err.Error()})
}
func notFound(w http.ResponseWriter)         { writeError(w, 404, errors.New("not found")) }
func methodNotAllowed(w http.ResponseWriter) { writeError(w, 405, errors.New("method not allowed")) }
func splitTail(value, prefix string) []string {
	tail := strings.Trim(strings.TrimPrefix(value, prefix), "/")
	if tail == "" {
		return nil
	}
	return strings.Split(tail, "/")
}
func writeSSE(w http.ResponseWriter, event domain.Event) {
	payload, _ := json.Marshal(event)
	fmt.Fprintf(w, "id: %d\nevent: %s\ndata: %s\n\n", event.Sequence, event.Type, payload)
}
func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'")
		next.ServeHTTP(w, r)
	})
}

func secureRequest(r *http.Request) bool {
	return r.TLS != nil || strings.EqualFold(strings.TrimSpace(strings.Split(r.Header.Get("X-Forwarded-Proto"), ",")[0]), "https")
}
