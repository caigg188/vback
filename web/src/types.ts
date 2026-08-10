export interface Repository {
  id: string;
  name: string;
  provider: string;
  endpoint: string;
  bucket: string;
  prefix: string;
  region: string;
  has_credentials: boolean;
  health: string;
  last_checked_at?: string;
}

export interface Source { path: string; alias: string }
export interface Retention { last: number; hourly: number; daily: number; weekly: number; monthly: number }

export interface Job {
  id: string;
  name: string;
  repository_id: string;
  sources: Source[];
  sqlite_sources: Source[];
  excludes: string[];
  schedule: string;
  timezone: string;
  retention: Retention;
  bandwidth_kb: number;
  one_file_system: boolean;
  low_resource: boolean;
  enabled: boolean;
  next_run_at?: string;
}

export interface Run {
  id: string;
  job_id?: string;
  repository_id: string;
  kind: string;
  status: string;
  started_at: string;
  finished_at?: string;
  snapshot_id?: string;
  bytes_total: number;
  bytes_done: number;
  files_total: number;
  files_done: number;
  data_added: number;
  error?: string;
  dry_run: boolean;
}

export interface Snapshot {
  id: string;
  short_id: string;
  time: string;
  hostname: string;
  paths: string[];
  tags: string[];
}

export interface Overview {
  repositories: number;
  jobs: number;
  running: number;
  failures: number;
  snapshots: number;
  recent_runs: Run[] | null;
  next_jobs: Job[] | null;
  seven_days: Record<string, number>;
}
