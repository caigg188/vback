package domain

import "time"

type Repository struct {
	ID             string     `json:"id"`
	Name           string     `json:"name"`
	Provider       string     `json:"provider"`
	Endpoint       string     `json:"endpoint"`
	Bucket         string     `json:"bucket"`
	Prefix         string     `json:"prefix"`
	Region         string     `json:"region"`
	SecretFile     string     `json:"-"`
	HasCredentials bool       `json:"has_credentials"`
	Health         string     `json:"health"`
	LastCheckedAt  *time.Time `json:"last_checked_at,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

type RepositoryInput struct {
	ID             string `json:"id,omitempty"`
	Name           string `json:"name"`
	Provider       string `json:"provider"`
	Endpoint       string `json:"endpoint"`
	Bucket         string `json:"bucket"`
	Prefix         string `json:"prefix"`
	Region         string `json:"region"`
	AccessKey      string `json:"access_key,omitempty"`
	SecretKey      string `json:"secret_key,omitempty"`
	ResticPassword string `json:"restic_password,omitempty"`
}

type Source struct {
	Path  string `json:"path"`
	Alias string `json:"alias"`
}

type SQLiteSource struct {
	Path  string `json:"path"`
	Alias string `json:"alias"`
}

type Retention struct {
	Last    int `json:"last"`
	Hourly  int `json:"hourly"`
	Daily   int `json:"daily"`
	Weekly  int `json:"weekly"`
	Monthly int `json:"monthly"`
}

type Job struct {
	ID            string         `json:"id"`
	Name          string         `json:"name"`
	RepositoryID  string         `json:"repository_id"`
	Sources       []Source       `json:"sources"`
	SQLiteSources []SQLiteSource `json:"sqlite_sources"`
	Excludes      []string       `json:"excludes"`
	Schedule      string         `json:"schedule"`
	Timezone      string         `json:"timezone"`
	Retention     Retention      `json:"retention"`
	BandwidthKB   int            `json:"bandwidth_kb"`
	OneFileSystem bool           `json:"one_file_system"`
	LowResource   bool           `json:"low_resource"`
	Enabled       bool           `json:"enabled"`
	NextRunAt     *time.Time     `json:"next_run_at,omitempty"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
}

type Run struct {
	ID           string     `json:"id"`
	JobID        string     `json:"job_id,omitempty"`
	RepositoryID string     `json:"repository_id"`
	Kind         string     `json:"kind"`
	Status       string     `json:"status"`
	StartedAt    time.Time  `json:"started_at"`
	FinishedAt   *time.Time `json:"finished_at,omitempty"`
	SnapshotID   string     `json:"snapshot_id,omitempty"`
	BytesTotal   int64      `json:"bytes_total"`
	BytesDone    int64      `json:"bytes_done"`
	FilesTotal   int64      `json:"files_total"`
	FilesDone    int64      `json:"files_done"`
	DataAdded    int64      `json:"data_added"`
	Error        string     `json:"error,omitempty"`
	DryRun       bool       `json:"dry_run"`
}

type Event struct {
	ID       int64     `json:"id"`
	RunID    string    `json:"run_id"`
	Sequence int64     `json:"sequence"`
	Time     time.Time `json:"time"`
	Type     string    `json:"type"`
	Message  string    `json:"message"`
	Data     []byte    `json:"-"`
}

type Snapshot struct {
	ID       string    `json:"id"`
	ShortID  string    `json:"short_id"`
	Time     time.Time `json:"time"`
	Hostname string    `json:"hostname"`
	Paths    []string  `json:"paths"`
	Tags     []string  `json:"tags"`
	Summary  any       `json:"summary,omitempty"`
}

type SnapshotFile struct {
	Path       string    `json:"path"`
	Name       string    `json:"name"`
	Type       string    `json:"type"`
	Size       int64     `json:"size"`
	ModifiedAt time.Time `json:"modified_at"`
}

type Overview struct {
	Repositories int            `json:"repositories"`
	Jobs         int            `json:"jobs"`
	Running      int            `json:"running"`
	Failures     int            `json:"failures"`
	Snapshots    int            `json:"snapshots"`
	RecentRuns   []Run          `json:"recent_runs"`
	NextJobs     []Job          `json:"next_jobs"`
	SevenDays    map[string]int `json:"seven_days"`
}

type Secret struct {
	AccessKey      string `json:"access_key"`
	SecretKey      string `json:"secret_key"`
	ResticPassword string `json:"restic_password"`
}
