#!/usr/bin/env bash

set -euo pipefail

require_root() {
  if [[ ${EUID:-0} -ne 0 ]]; then
    echo "Ce script doit être exécuté en root." >&2
    exit 1
  fi
}

require_root

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

STUDENT_DIR="/opt/monitoring-lab/student"
SERVICE_PATH="/etc/systemd/system/student-monitor.service"
TIMER_PATH="/etc/systemd/system/student-monitor.timer"

mkdir -p "$STUDENT_DIR"
cp -f "$SRC_DIR/monitor.sh" "$STUDENT_DIR/monitor.sh"
cp -f "$SRC_DIR/lib.sh" "$STUDENT_DIR/lib.sh"
chmod +x "$STUDENT_DIR/monitor.sh"

cat > "$SERVICE_PATH" <<'EOF'
[Unit]
Description=Student Monitoring Script (TP)
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/opt/monitoring-lab/student/monitor.sh
EOF

cat > "$TIMER_PATH" <<'EOF'
[Unit]
Description=Run Student Monitoring Script (TP) every 2 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
Unit=student-monitor.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now student-monitor.timer

echo "OK: installed to $STUDENT_DIR and enabled student-monitor.timer"
echo "Check: systemctl list-timers --all | grep student-monitor"
echo "Logs: journalctl -u student-monitor.service -n 100 --no-pager"

