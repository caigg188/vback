#!/usr/bin/env sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer as root." >&2
  exit 1
fi

SOURCE_BIN="${1:-./dist/vback}"
if [ ! -x "$SOURCE_BIN" ]; then
  echo "Built vback binary not found: $SOURCE_BIN" >&2
  exit 1
fi
if ! command -v restic >/dev/null 2>&1; then
  echo "restic is required. Install it with your distribution package manager." >&2
  exit 1
fi

id vback >/dev/null 2>&1 || useradd --system --home /var/lib/vback --shell /usr/sbin/nologin vback
install -m 0755 "$SOURCE_BIN" /usr/local/bin/vback
install -d -o vback -g vback -m 0700 /var/lib/vback
install -m 0644 deploy/vback.service /etc/systemd/system/vback.service
systemctl daemon-reload
systemctl enable --now vback.service

echo "vback is listening on 127.0.0.1:9898"
echo "Read the one-time setup token with: journalctl -u vback -n 20"
