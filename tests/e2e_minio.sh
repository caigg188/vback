#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENDPOINT="${VBACK_E2E_ENDPOINT:-http://127.0.0.1:9000}"
BUCKET="${VBACK_E2E_BUCKET:-vback-e2e}"
ACCESS_KEY="${VBACK_E2E_ACCESS_KEY:-vbacktest}"
SECRET_KEY="${VBACK_E2E_SECRET_KEY:-vbacktestsecret}"
PORT="${VBACK_E2E_PORT:-19989}"
work_dir="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$work_dir/data" "$work_dir/source"
printf 'first version\n' > "$work_dir/source/first.txt"
CGO_ENABLED=0 go build -trimpath -o "$work_dir/vback" "$ROOT/cmd/vback"
VBACK_DATA_DIR="$work_dir/data" VBACK_LISTEN="127.0.0.1:$PORT" "$work_dir/vback" serve > "$work_dir/server.log" 2>&1 &
server_pid=$!

for _ in $(seq 1 100); do
  curl -fsS "http://127.0.0.1:$PORT/api/v1/health" >/dev/null 2>&1 && break
  sleep 0.1
done
token="$(tr -d '\n' < "$work_dir/data/setup-token")"
curl -fsS -X POST "http://127.0.0.1:$PORT/api/v1/setup" \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg token "$token" '{token:$token,password:"correct-horse-battery"}')" >/dev/null
login="$(curl -fsS -c "$work_dir/cookies" -X POST "http://127.0.0.1:$PORT/api/v1/login" \
  -H 'Content-Type: application/json' -d '{"password":"correct-horse-battery"}')"
csrf="$(jq -r .csrf_token <<< "$login")"

api_post() {
  local path="$1" data="$2"
  curl -fsS -b "$work_dir/cookies" -X POST "http://127.0.0.1:$PORT/api/v1$path" \
    -H 'Content-Type: application/json' -H "X-CSRF-Token: $csrf" -d "$data"
}

repo="$(api_post /repositories "$(jq -nc \
  --arg endpoint "$ENDPOINT" --arg bucket "$BUCKET" --arg access "$ACCESS_KEY" --arg secret "$SECRET_KEY" \
  '{name:"CI MinIO",provider:"custom",endpoint:$endpoint,bucket:$bucket,prefix:"vback-v2",region:"us-east-1",access_key:$access,secret_key:$secret,restic_password:"integration-recovery-key"}')")"
repo_id="$(jq -r .id <<< "$repo")"
api_post "/repositories/$repo_id/init" '{}' >/dev/null

job="$(api_post /jobs "$(jq -nc --arg repo "$repo_id" --arg source "$work_dir/source" \
  '{id:"",name:"CI backup",repository_id:$repo,sources:[{path:$source,alias:"source"}],sqlite_sources:[],excludes:[],schedule:"",timezone:"UTC",retention:{last:3,hourly:0,daily:0,weekly:0,monthly:0},bandwidth_kb:0,one_file_system:false,low_resource:true,enabled:false}')")"
job_id="$(jq -r .id <<< "$job")"

wait_run() {
  local run_id="$1" status
  for _ in $(seq 1 300); do
    status="$(curl -fsS -b "$work_dir/cookies" "http://127.0.0.1:$PORT/api/v1/runs/$run_id" | jq -r .status)"
    case "$status" in
      success) return 0 ;;
      failed|partial|cancelled)
        cat "$work_dir/server.log" >&2
        return 1
        ;;
    esac
    sleep 0.1
  done
  return 1
}

first_run="$(api_post "/jobs/$job_id/run" '{}')"
wait_run "$(jq -r .id <<< "$first_run")"
printf 'second file\n' > "$work_dir/source/second.txt"
second_run="$(api_post "/jobs/$job_id/run" '{}')"
wait_run "$(jq -r .id <<< "$second_run")"

snapshots="$(curl -fsS -b "$work_dir/cookies" "http://127.0.0.1:$PORT/api/v1/snapshots?job_id=$job_id")"
[[ "$(jq length <<< "$snapshots")" -ge 2 ]]
snapshot_id="$(jq -r '.[0].id' <<< "$snapshots")"
restore_run="$(api_post /restore "$(jq -nc --arg job "$job_id" --arg snapshot "$snapshot_id" '{job_id:$job,snapshot_id:$snapshot,path:""}')")"
restore_id="$(jq -r .id <<< "$restore_run")"
wait_run "$restore_id"
restored_file="$(find "$work_dir/data/restores/$restore_id" -type f -name first.txt -print -quit)"
cmp "$work_dir/source/first.txt" "$restored_file"

echo "MinIO backup, incremental snapshot and restore checks passed"
