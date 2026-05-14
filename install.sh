#!/bin/bash

#!/bin/bash

set -e

LAB_DIR="/opt/monitoring-lab"
LOG_DIR="/var/log/monitoring-lab"
SERVICE_USER="monitorlab"

echo "[+] Installation de l'environnement de TP monitoring..."

if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit être lancé en root."
  exit 1
fi

echo "[+] Création de l'utilisateur système..."
id "$SERVICE_USER" &>/dev/null || useradd -r -s /usr/sbin/nologin "$SERVICE_USER"

echo "[+] Création des dossiers..."
mkdir -p "$LAB_DIR/scripts"
mkdir -p "$LOG_DIR/auth"
mkdir -p "$LOG_DIR/app"
mkdir -p "$LOG_DIR/nginx"
mkdir -p "$LOG_DIR/archive"
mkdir -p "$LOG_DIR/tmp"

chown -R "$SERVICE_USER:$SERVICE_USER" "$LAB_DIR" "$LOG_DIR"

echo "[+] Création du faux service applicatif..."

cat > "$LAB_DIR/scripts/fake-api.sh" <<'EOF'
#!/bin/bash

LOG_FILE="/var/log/monitoring-lab/app/fake-api.log"

echo "[$(date '+%F %T')] INFO fake-api starting with PID $$" >> "$LOG_FILE"

while true; do
  TS=$(date '+%F %T')
  R=$((RANDOM % 10))

  case "$R" in
    0)
      echo "[$TS] ERROR database connection timeout" >> "$LOG_FILE"
      logger -t fake-api "ERROR database connection timeout"
      ;;
    1)
      echo "[$TS] WARNING response time greater than 1200ms" >> "$LOG_FILE"
      logger -t fake-api "WARNING slow response detected"
      ;;
    2)
      echo "[$TS] ERROR failed to process payment request_id=$RANDOM" >> "$LOG_FILE"
      logger -t fake-api "ERROR failed to process payment"
      ;;
    *)
      echo "[$TS] INFO request completed status=200 duration=$((RANDOM % 500))ms" >> "$LOG_FILE"
      ;;
  esac

  sleep 5
done
EOF

chmod +x "$LAB_DIR/scripts/fake-api.sh"

echo "[+] Création du générateur de faux logs..."

cat > "$LAB_DIR/scripts/log-generator.sh" <<'EOF'
#!/bin/bash

BASE="/var/log/monitoring-lab"

while true; do
  TS=$(date '+%b %d %H:%M:%S')
  IP="192.168.$((RANDOM % 255)).$((RANDOM % 255))"
  USERNAMES=("root" "admin" "test" "ubuntu" "deploy" "alex" "student")
  USER=${USERNAMES[$RANDOM % ${#USERNAMES[@]}]}

  echo "$TS server01 sshd[$RANDOM]: Failed password for $USER from $IP port $((RANDOM % 60000)) ssh2" >> "$BASE/auth/auth.log"

  STATUS_CODES=(200 200 200 301 403 404 500 502)
  STATUS=${STATUS_CODES[$RANDOM % ${#STATUS_CODES[@]}]}

  echo "$IP - - [$(date '+%d/%b/%Y:%H:%M:%S %z')] \"GET /api/resource/$RANDOM HTTP/1.1\" $STATUS $((RANDOM % 5000))" >> "$BASE/nginx/access.log"

  if [[ "$STATUS" == "500" || "$STATUS" == "502" ]]; then
    echo "[$(date '+%F %T')] nginx ERROR upstream server unavailable client=$IP status=$STATUS" >> "$BASE/nginx/error.log"
  fi

  if (( RANDOM % 8 == 0 )); then
    echo "[$(date '+%F %T')] CRITICAL disk usage above threshold partition=/var usage=$((80 + RANDOM % 20))%" >> "$BASE/app/system-alerts.log"
  fi

  sleep 3
done
EOF

chmod +x "$LAB_DIR/scripts/log-generator.sh"

echo "[+] Création de fichiers pour find/xargs..."

dd if=/dev/zero of="$LOG_DIR/archive/big-debug.log" bs=1M count=15 status=none
dd if=/dev/zero of="$LOG_DIR/archive/old-big-file.log" bs=1M count=25 status=none

touch -d "10 days ago" "$LOG_DIR/archive/old-big-file.log"
touch -d "2 days ago" "$LOG_DIR/archive/big-debug.log"

cat > "$LOG_DIR/app/users.csv" <<EOF
id,name,role,status
1,Alice,admin,active
2,Bob,user,inactive
3,Charlie,user,active
4,David,admin,suspended
5,Eve,user,active
EOF

cat > "$LOG_DIR/app/config.conf" <<EOF
APP_ENV=production
DEBUG=true
MAX_CPU=80
MAX_RAM=75
SERVICE_CHECK=fake-api
ALERT_EMAIL=admin@example.local
EOF

chown -R "$SERVICE_USER:$SERVICE_USER" "$LAB_DIR" "$LOG_DIR"

echo "[+] Installation des services systemd..."

cat > /etc/systemd/system/fake-api.service <<EOF
[Unit]
Description=Monitoring Lab - Fake API Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
ExecStart=$LAB_DIR/scripts/fake-api.sh
Restart=always
RestartSec=5
Nice=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/log-generator.service <<EOF
[Unit]
Description=Monitoring Lab - Fake Log Generator
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
ExecStart=$LAB_DIR/scripts/log-generator.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[+] Rechargement systemd..."
systemctl daemon-reload
systemctl enable fake-api.service
systemctl enable log-generator.service
systemctl restart fake-api.service
systemctl restart log-generator.service

echo
echo "Installation terminée."
echo
echo "Dossiers créés :"
echo "  $LAB_DIR"
echo "  $LOG_DIR"
echo
echo "Services disponibles :"
echo "  fake-api.service"
echo "  log-generator.service"
echo
echo "Commandes utiles :"
echo "  systemctl status fake-api"
echo "  systemctl status log-generator"
echo "  journalctl -u fake-api -f"
echo "  journalctl -u log-generator -f"
echo
echo "Exemples de logs :"
echo "  $LOG_DIR/auth/auth.log"
echo "  $LOG_DIR/app/fake-api.log"
echo "  $LOG_DIR/app/system-alerts.log"
echo "  $LOG_DIR/nginx/access.log"
echo "  $LOG_DIR/nginx/error.log"