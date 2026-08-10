package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/caigg188/vback/internal/domain"
	_ "modernc.org/sqlite"
)

type Store struct{ db *sql.DB }

func Open(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)&_pragma=journal_mode(WAL)")
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	s := &Store{db: db}
	if err := s.migrate(context.Background()); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) migrate(ctx context.Context) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)`,
		`CREATE TABLE IF NOT EXISTS repositories (
			id TEXT PRIMARY KEY, name TEXT NOT NULL, provider TEXT NOT NULL, endpoint TEXT NOT NULL,
			bucket TEXT NOT NULL, prefix TEXT NOT NULL, region TEXT NOT NULL, secret_file TEXT NOT NULL,
			health TEXT NOT NULL DEFAULT 'unknown', last_checked_at TEXT,
			created_at TEXT NOT NULL, updated_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS jobs (
			id TEXT PRIMARY KEY, name TEXT NOT NULL, repository_id TEXT NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
			sources_json TEXT NOT NULL, sqlite_sources_json TEXT NOT NULL DEFAULT '[]', excludes_json TEXT NOT NULL,
			schedule TEXT NOT NULL, timezone TEXT NOT NULL, retention_json TEXT NOT NULL,
			bandwidth_kb INTEGER NOT NULL DEFAULT 0, one_file_system INTEGER NOT NULL DEFAULT 0,
			low_resource INTEGER NOT NULL DEFAULT 1, enabled INTEGER NOT NULL DEFAULT 1,
			next_run_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS runs (
			id TEXT PRIMARY KEY, job_id TEXT, repository_id TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
			started_at TEXT NOT NULL, finished_at TEXT, snapshot_id TEXT NOT NULL DEFAULT '',
			bytes_total INTEGER NOT NULL DEFAULT 0, bytes_done INTEGER NOT NULL DEFAULT 0,
			files_total INTEGER NOT NULL DEFAULT 0, files_done INTEGER NOT NULL DEFAULT 0,
			data_added INTEGER NOT NULL DEFAULT 0, error TEXT NOT NULL DEFAULT '', dry_run INTEGER NOT NULL DEFAULT 0
		)`,
		`CREATE TABLE IF NOT EXISTS events (
			id INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
			sequence INTEGER NOT NULL, time TEXT NOT NULL, type TEXT NOT NULL, message TEXT NOT NULL, data_json BLOB
		)`,
		`CREATE INDEX IF NOT EXISTS events_run_sequence_idx ON events(run_id, sequence)`,
		`CREATE INDEX IF NOT EXISTS runs_started_idx ON runs(started_at DESC)`,
		`CREATE TABLE IF NOT EXISTS sessions (
			token_hash TEXT PRIMARY KEY, csrf_token TEXT NOT NULL, expires_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS audit (
			id INTEGER PRIMARY KEY AUTOINCREMENT, time TEXT NOT NULL, action TEXT NOT NULL,
			resource_type TEXT NOT NULL, resource_id TEXT NOT NULL, detail TEXT NOT NULL
		)`,
	}
	for _, statement := range statements {
		if _, err := s.db.ExecContext(ctx, statement); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) Setting(ctx context.Context, key string) (string, error) {
	var value string
	err := s.db.QueryRowContext(ctx, `SELECT value FROM settings WHERE key=?`, key).Scan(&value)
	return value, err
}

func (s *Store) SetSetting(ctx context.Context, key, value string) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`, key, value)
	return err
}

func (s *Store) IsSetup(ctx context.Context) bool {
	value, err := s.Setting(ctx, "admin_password")
	return err == nil && value != ""
}

func (s *Store) UpsertRepository(ctx context.Context, r domain.Repository) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO repositories
		(id,name,provider,endpoint,bucket,prefix,region,secret_file,health,last_checked_at,created_at,updated_at)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(id) DO UPDATE SET name=excluded.name,provider=excluded.provider,endpoint=excluded.endpoint,
		bucket=excluded.bucket,prefix=excluded.prefix,region=excluded.region,secret_file=excluded.secret_file,updated_at=excluded.updated_at`,
		r.ID, r.Name, r.Provider, r.Endpoint, r.Bucket, r.Prefix, r.Region, r.SecretFile, r.Health,
		formatTimePtr(r.LastCheckedAt), r.CreatedAt.Format(time.RFC3339Nano), r.UpdatedAt.Format(time.RFC3339Nano))
	return err
}

func (s *Store) Repositories(ctx context.Context) ([]domain.Repository, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id,name,provider,endpoint,bucket,prefix,region,secret_file,health,last_checked_at,created_at,updated_at FROM repositories ORDER BY created_at`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []domain.Repository
	for rows.Next() {
		r, err := scanRepository(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, r)
	}
	return result, rows.Err()
}

func (s *Store) Repository(ctx context.Context, id string) (domain.Repository, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id,name,provider,endpoint,bucket,prefix,region,secret_file,health,last_checked_at,created_at,updated_at FROM repositories WHERE id=?`, id)
	return scanRepository(row)
}

type scanner interface{ Scan(...any) error }

func scanRepository(row scanner) (domain.Repository, error) {
	var r domain.Repository
	var checked sql.NullString
	var created, updated string
	err := row.Scan(&r.ID, &r.Name, &r.Provider, &r.Endpoint, &r.Bucket, &r.Prefix, &r.Region, &r.SecretFile, &r.Health, &checked, &created, &updated)
	if err != nil {
		return r, err
	}
	r.CreatedAt, _ = time.Parse(time.RFC3339Nano, created)
	r.UpdatedAt, _ = time.Parse(time.RFC3339Nano, updated)
	if checked.Valid {
		t, _ := time.Parse(time.RFC3339Nano, checked.String)
		r.LastCheckedAt = &t
	}
	r.HasCredentials = r.SecretFile != ""
	return r, nil
}

func (s *Store) SetRepositoryHealth(ctx context.Context, id, health string) error {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	_, err := s.db.ExecContext(ctx, `UPDATE repositories SET health=?,last_checked_at=?,updated_at=? WHERE id=?`, health, now, now, id)
	return err
}

func (s *Store) UpsertJob(ctx context.Context, j domain.Job) error {
	sources, _ := json.Marshal(j.Sources)
	sqliteSources, _ := json.Marshal(j.SQLiteSources)
	excludes, _ := json.Marshal(j.Excludes)
	retention, _ := json.Marshal(j.Retention)
	_, err := s.db.ExecContext(ctx, `INSERT INTO jobs
		(id,name,repository_id,sources_json,sqlite_sources_json,excludes_json,schedule,timezone,retention_json,
		bandwidth_kb,one_file_system,low_resource,enabled,next_run_at,created_at,updated_at)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(id) DO UPDATE SET name=excluded.name,repository_id=excluded.repository_id,sources_json=excluded.sources_json,
		sqlite_sources_json=excluded.sqlite_sources_json,excludes_json=excluded.excludes_json,schedule=excluded.schedule,
		timezone=excluded.timezone,retention_json=excluded.retention_json,bandwidth_kb=excluded.bandwidth_kb,
		one_file_system=excluded.one_file_system,low_resource=excluded.low_resource,enabled=excluded.enabled,
		next_run_at=excluded.next_run_at,updated_at=excluded.updated_at`,
		j.ID, j.Name, j.RepositoryID, string(sources), string(sqliteSources), string(excludes), j.Schedule, j.Timezone, string(retention),
		j.BandwidthKB, j.OneFileSystem, j.LowResource, j.Enabled, formatTimePtr(j.NextRunAt), j.CreatedAt.Format(time.RFC3339Nano), j.UpdatedAt.Format(time.RFC3339Nano))
	return err
}

func (s *Store) Jobs(ctx context.Context) ([]domain.Job, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id,name,repository_id,sources_json,sqlite_sources_json,excludes_json,schedule,timezone,retention_json,bandwidth_kb,one_file_system,low_resource,enabled,next_run_at,created_at,updated_at FROM jobs ORDER BY created_at`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []domain.Job
	for rows.Next() {
		j, err := scanJob(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, j)
	}
	return result, rows.Err()
}

func (s *Store) Job(ctx context.Context, id string) (domain.Job, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id,name,repository_id,sources_json,sqlite_sources_json,excludes_json,schedule,timezone,retention_json,bandwidth_kb,one_file_system,low_resource,enabled,next_run_at,created_at,updated_at FROM jobs WHERE id=?`, id)
	return scanJob(row)
}

func scanJob(row scanner) (domain.Job, error) {
	var j domain.Job
	var sources, sqliteSources, excludes, retention string
	var oneFS, low, enabled bool
	var next sql.NullString
	var created, updated string
	err := row.Scan(&j.ID, &j.Name, &j.RepositoryID, &sources, &sqliteSources, &excludes, &j.Schedule, &j.Timezone, &retention, &j.BandwidthKB, &oneFS, &low, &enabled, &next, &created, &updated)
	if err != nil {
		return j, err
	}
	_ = json.Unmarshal([]byte(sources), &j.Sources)
	_ = json.Unmarshal([]byte(sqliteSources), &j.SQLiteSources)
	_ = json.Unmarshal([]byte(excludes), &j.Excludes)
	_ = json.Unmarshal([]byte(retention), &j.Retention)
	j.OneFileSystem, j.LowResource, j.Enabled = oneFS, low, enabled
	j.CreatedAt, _ = time.Parse(time.RFC3339Nano, created)
	j.UpdatedAt, _ = time.Parse(time.RFC3339Nano, updated)
	if next.Valid {
		t, _ := time.Parse(time.RFC3339Nano, next.String)
		j.NextRunAt = &t
	}
	return j, nil
}

func (s *Store) UpdateJobNextRun(ctx context.Context, id string, next *time.Time) error {
	_, err := s.db.ExecContext(ctx, `UPDATE jobs SET next_run_at=?,updated_at=? WHERE id=?`, formatTimePtr(next), time.Now().UTC().Format(time.RFC3339Nano), id)
	return err
}

func (s *Store) CreateRun(ctx context.Context, r domain.Run) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO runs(id,job_id,repository_id,kind,status,started_at,dry_run) VALUES(?,?,?,?,?,?,?)`,
		r.ID, r.JobID, r.RepositoryID, r.Kind, r.Status, r.StartedAt.Format(time.RFC3339Nano), r.DryRun)
	return err
}

func (s *Store) UpdateRun(ctx context.Context, r domain.Run) error {
	_, err := s.db.ExecContext(ctx, `UPDATE runs SET status=?,finished_at=?,snapshot_id=?,bytes_total=?,bytes_done=?,files_total=?,files_done=?,data_added=?,error=? WHERE id=?`,
		r.Status, formatTimePtr(r.FinishedAt), r.SnapshotID, r.BytesTotal, r.BytesDone, r.FilesTotal, r.FilesDone, r.DataAdded, r.Error, r.ID)
	return err
}

func (s *Store) RecoverInterruptedRuns(ctx context.Context) error {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	_, err := s.db.ExecContext(ctx, `UPDATE runs
		SET status='failed',finished_at=?,error='vback service restarted before this run completed'
		WHERE status IN ('queued','running')`, now)
	return err
}

func (s *Store) Run(ctx context.Context, id string) (domain.Run, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id,COALESCE(job_id,''),repository_id,kind,status,started_at,finished_at,snapshot_id,bytes_total,bytes_done,files_total,files_done,data_added,error,dry_run FROM runs WHERE id=?`, id)
	return scanRun(row)
}

func (s *Store) Runs(ctx context.Context, limit int) ([]domain.Run, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx, `SELECT id,COALESCE(job_id,''),repository_id,kind,status,started_at,finished_at,snapshot_id,bytes_total,bytes_done,files_total,files_done,data_added,error,dry_run FROM runs ORDER BY started_at DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []domain.Run
	for rows.Next() {
		r, err := scanRun(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, r)
	}
	return result, rows.Err()
}

func scanRun(row scanner) (domain.Run, error) {
	var r domain.Run
	var started string
	var finished sql.NullString
	err := row.Scan(&r.ID, &r.JobID, &r.RepositoryID, &r.Kind, &r.Status, &started, &finished, &r.SnapshotID, &r.BytesTotal, &r.BytesDone, &r.FilesTotal, &r.FilesDone, &r.DataAdded, &r.Error, &r.DryRun)
	if err != nil {
		return r, err
	}
	r.StartedAt, _ = time.Parse(time.RFC3339Nano, started)
	if finished.Valid {
		t, _ := time.Parse(time.RFC3339Nano, finished.String)
		r.FinishedAt = &t
	}
	return r, nil
}

func (s *Store) AppendEvent(ctx context.Context, e domain.Event) (domain.Event, error) {
	var seq int64
	_ = s.db.QueryRowContext(ctx, `SELECT COALESCE(MAX(sequence),0)+1 FROM events WHERE run_id=?`, e.RunID).Scan(&seq)
	e.Sequence = seq
	result, err := s.db.ExecContext(ctx, `INSERT INTO events(run_id,sequence,time,type,message,data_json) VALUES(?,?,?,?,?,?)`, e.RunID, e.Sequence, e.Time.Format(time.RFC3339Nano), e.Type, e.Message, e.Data)
	if err != nil {
		return e, err
	}
	e.ID, _ = result.LastInsertId()
	return e, nil
}

func (s *Store) Events(ctx context.Context, runID string, after int64) ([]domain.Event, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id,run_id,sequence,time,type,message,data_json FROM events WHERE run_id=? AND sequence>? ORDER BY sequence`, runID, after)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []domain.Event
	for rows.Next() {
		var e domain.Event
		var ts string
		if err := rows.Scan(&e.ID, &e.RunID, &e.Sequence, &ts, &e.Type, &e.Message, &e.Data); err != nil {
			return nil, err
		}
		e.Time, _ = time.Parse(time.RFC3339Nano, ts)
		result = append(result, e)
	}
	return result, rows.Err()
}

func (s *Store) SaveSession(ctx context.Context, tokenHash, csrf string, expires time.Time) error {
	_, err := s.db.ExecContext(ctx, `INSERT OR REPLACE INTO sessions(token_hash,csrf_token,expires_at) VALUES(?,?,?)`, tokenHash, csrf, expires.Format(time.RFC3339Nano))
	return err
}

func (s *Store) Session(ctx context.Context, tokenHash string) (string, error) {
	var csrf, expires string
	err := s.db.QueryRowContext(ctx, `SELECT csrf_token,expires_at FROM sessions WHERE token_hash=?`, tokenHash).Scan(&csrf, &expires)
	if err != nil {
		return "", err
	}
	t, _ := time.Parse(time.RFC3339Nano, expires)
	if time.Now().After(t) {
		_, _ = s.db.ExecContext(ctx, `DELETE FROM sessions WHERE token_hash=?`, tokenHash)
		return "", errors.New("session expired")
	}
	return csrf, nil
}

func (s *Store) DeleteSession(ctx context.Context, tokenHash string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM sessions WHERE token_hash=?`, tokenHash)
	return err
}

func (s *Store) Audit(ctx context.Context, action, resourceType, resourceID, detail string) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO audit(time,action,resource_type,resource_id,detail) VALUES(?,?,?,?,?)`, time.Now().UTC().Format(time.RFC3339Nano), action, resourceType, resourceID, detail)
	return err
}

func (s *Store) Overview(ctx context.Context) (domain.Overview, error) {
	var o domain.Overview
	for query, target := range map[string]*int{
		`SELECT COUNT(*) FROM repositories`:                              &o.Repositories,
		`SELECT COUNT(*) FROM jobs`:                                      &o.Jobs,
		`SELECT COUNT(*) FROM runs WHERE status IN ('queued','running')`: &o.Running,
		`SELECT COUNT(*) FROM runs WHERE status IN ('failed','partial') AND started_at >= datetime('now','-7 days')`: &o.Failures,
		`SELECT COUNT(*) FROM runs WHERE kind='backup' AND status='success' AND snapshot_id<>''`:                     &o.Snapshots,
	} {
		if err := s.db.QueryRowContext(ctx, query).Scan(target); err != nil {
			return o, err
		}
	}
	o.RecentRuns, _ = s.Runs(ctx, 8)
	jobs, _ := s.Jobs(ctx)
	for _, j := range jobs {
		if j.Enabled && j.NextRunAt != nil {
			o.NextJobs = append(o.NextJobs, j)
		}
	}
	o.SevenDays = map[string]int{}
	rows, err := s.db.QueryContext(ctx, `SELECT substr(started_at,1,10),COUNT(*) FROM runs WHERE started_at >= datetime('now','-7 days') GROUP BY substr(started_at,1,10)`)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var d string
			var n int
			_ = rows.Scan(&d, &n)
			o.SevenDays[d] = n
		}
	}
	return o, nil
}

func formatTimePtr(t *time.Time) any {
	if t == nil {
		return nil
	}
	return t.UTC().Format(time.RFC3339Nano)
}

func (s *Store) DeleteJob(ctx context.Context, id string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM jobs WHERE id=?`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("job not found")
	}
	return nil
}
