#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/vback.sh"

bash -n "$SCRIPT"
grep -q 'VERSION="1.4.2"' "$SCRIPT"
grep -q 'BASH_VERSINFO\[0\] < 4' "$SCRIPT"
grep -q 'remote_md5.*== \*-\\*' "$SCRIPT"
grep -q 'done <<< "\$list"' "$SCRIPT"
grep -q 'Refusing to reset unsafe data directory' "$SCRIPT"
grep -q 'load_data_file "\$CONFIG_FILE"' "$SCRIPT"
if grep -Eq 'source "\$(CONFIG|TASKS|SCHEDULES)_FILE"' "$SCRIPT"; then
  echo "v1 data files must not be sourced as shell code" >&2
  exit 1
fi

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
cp "$ROOT"/tests/fixtures/v1/* "$fixture_dir/"
chmod 600 "$fixture_dir"/*
VBACK_DATA_DIR="$fixture_dir" bash "$SCRIPT" --lang en config > "$fixture_dir/output"
grep -q 'Daily Site' "$fixture_dir/output"
grep -q '/srv/My App' "$fixture_dir/output"

echo "v1 safety checks passed"
