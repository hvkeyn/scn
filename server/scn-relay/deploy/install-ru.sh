#!/usr/bin/env bash
# Install scn-relay into /opt/scn-relay WITHOUT touching nginx/apache/other apps.
# Usage (on target): sudo bash install-ru.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST=/opt/scn-relay
PORT=53319

echo "[scn-relay] install from $SRC_DIR -> $DEST (port $PORT)"

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node is required. Install Node 18+ first, then re-run."
  exit 1
fi

mkdir -p "$DEST/updates"
# Copy only relay files — never overwrite unrelated projects.
cp -f "$SRC_DIR/server.js" "$DEST/server.js"
cp -f "$SRC_DIR/package.json" "$DEST/package.json"
if [[ -f "$SRC_DIR/package-lock.json" ]]; then
  cp -f "$SRC_DIR/package-lock.json" "$DEST/package-lock.json"
fi

cd "$DEST"
if [[ -f package-lock.json ]]; then
  npm ci --omit=dev
else
  npm install --omit=dev
fi

cp -f "$SRC_DIR/deploy/scn-relay.service" /etc/systemd/system/scn-relay.service
systemctl daemon-reload
systemctl enable scn-relay.service
systemctl restart scn-relay.service

# Open firewall only for our port if ufw is active — leave other rules alone.
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow ${PORT}/tcp comment 'scn-relay' || true
fi

sleep 1
curl -fsS "http://127.0.0.1:${PORT}/api/v1/health" || {
  echo "WARNING: health check failed — check: journalctl -u scn-relay -n 50"
  exit 1
}
echo "[scn-relay] OK — listening on :${PORT}"
