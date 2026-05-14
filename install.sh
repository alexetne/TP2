#!/bin/bash

set -e

LAB_DIR="/opt/monitoring-lab"
LOG_DIR="/var/log/monitoring-lab"
SERVICE_USER="monitorlab"
DATA_DIR="$LOG_DIR/data"
TREE_DIR="$LOG_DIR/tmp/tree"
DOC_DIR="$LAB_DIR/docs"

# Taille de données (peut être surchargé via variables d'env)
: "${LAB_DATA_LINES:=200000}"      # lignes pour gros fichiers texte
: "${LAB_METRICS_ROWS:=150000}"    # lignes pour CSV
: "${LAB_TREE_FILES:=3000}"        # nb de fichiers dans l'arborescence
: "${LAB_TREE_DEPTH:=5}"           # profondeur de l'arborescence
: "${LAB_TREE_DIRS:=40}"           # nb de sous-dossiers

echo "[+] Installation de l'environnement de TP monitoring..."

if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit être lancé en root."
  exit 1
fi

echo "[+] Création de l'utilisateur système..."
id "$SERVICE_USER" &>/dev/null || useradd -r -s /usr/sbin/nologin "$SERVICE_USER"

echo "[+] Création des dossiers..."
mkdir -p "$LAB_DIR/scripts"
mkdir -p "$DOC_DIR"
mkdir -p "$LOG_DIR/auth"
mkdir -p "$LOG_DIR/app"
mkdir -p "$LOG_DIR/nginx"
mkdir -p "$LOG_DIR/archive"
mkdir -p "$LOG_DIR/tmp"
mkdir -p "$DATA_DIR"
mkdir -p "$TREE_DIR"

chown -R "$SERVICE_USER:$SERVICE_USER" "$LAB_DIR" "$LOG_DIR"

echo "[+] Création du faux service applicatif..."

cat > "$LAB_DIR/scripts/fake-api.sh" <<'EOF'
#!/bin/bash

LOG_FILE="/var/log/monitoring-lab/app/fake-api.log"

log_line() {
  local line="$1"
  echo "$line" >> "$LOG_FILE"
  echo "$line"
}

log_line "[$(date '+%F %T')] INFO fake-api starting with PID $$"

while true; do
  TS=$(date '+%F %T')
  R=$((RANDOM % 10))

  case "$R" in
    0)
      log_line "[$TS] ERROR database connection timeout"
      logger -t fake-api "ERROR database connection timeout"
      ;;
    1)
      log_line "[$TS] WARNING response time greater than 1200ms"
      logger -t fake-api "WARNING slow response detected"
      ;;
    2)
      log_line "[$TS] ERROR failed to process payment request_id=$RANDOM"
      logger -t fake-api "ERROR failed to process payment"
      ;;
    *)
      log_line "[$TS] INFO request completed status=200 duration=$((RANDOM % 500))ms"
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

emit() {
  local file="$1"
  local line="$2"
  echo "$line" >> "$file"
  # aussi vers stdout pour journalctl -u log-generator
  echo "$line"
}

while true; do
  TS=$(date '+%b %d %H:%M:%S')
  IP="192.168.$((RANDOM % 255)).$((RANDOM % 255))"
  USERNAMES=("root" "admin" "test" "ubuntu" "deploy" "alex" "student")
  USER=${USERNAMES[$RANDOM % ${#USERNAMES[@]}]}

  emit "$BASE/auth/auth.log" "$TS server01 sshd[$RANDOM]: Failed password for $USER from $IP port $((RANDOM % 60000)) ssh2"

  STATUS_CODES=(200 200 200 301 403 404 500 502)
  STATUS=${STATUS_CODES[$RANDOM % ${#STATUS_CODES[@]}]}

  emit "$BASE/nginx/access.log" "$IP - - [$(date '+%d/%b/%Y:%H:%M:%S %z')] \"GET /api/resource/$RANDOM HTTP/1.1\" $STATUS $((RANDOM % 5000))"

  if [[ "$STATUS" == "500" || "$STATUS" == "502" ]]; then
    emit "$BASE/nginx/error.log" "[$(date '+%F %T')] nginx ERROR upstream server unavailable client=$IP status=$STATUS"
  fi

  if (( RANDOM % 8 == 0 )); then
    emit "$BASE/app/system-alerts.log" "[$(date '+%F %T')] CRITICAL disk usage above threshold partition=/var usage=$((80 + RANDOM % 20))%"
  fi

  sleep 3
done
EOF

chmod +x "$LAB_DIR/scripts/log-generator.sh"

echo "[+] Création d'un générateur de données (gros fichiers + arborescence)..."

cat > "$LAB_DIR/scripts/populate-lab-data.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

LOG_DIR="/var/log/monitoring-lab"
DATA_DIR="$LOG_DIR/data"
TREE_DIR="$LOG_DIR/tmp/tree"

: "${LAB_DATA_LINES:=200000}"
: "${LAB_METRICS_ROWS:=150000}"
: "${LAB_TREE_FILES:=3000}"
: "${LAB_TREE_DEPTH:=5}"
: "${LAB_TREE_DIRS:=40}"

mkdir -p "$DATA_DIR" "$TREE_DIR"

echo "[*] Génération: gros texte (grep/sed/awk)..."
# Fichier texte structuré avec "aiguilles" connues
{
  echo "# generated_at=$(date -Is)"
  echo "# fields: ts host level component user ip request_id status duration_ms msg"
  for i in $(seq 1 "$LAB_DATA_LINES"); do
    ts="$(date -d "@$(( $(date +%s) - (LAB_DATA_LINES - i) ))" '+%F %T' 2>/dev/null || date '+%F %T')"
    host="server$(( (i % 12) + 1 ))"
    case $((i % 17)) in
      0) level="ERROR" ;;
      1) level="WARN" ;;
      2) level="CRITICAL" ;;
      *) level="INFO" ;;
    esac
    component=$((i % 5))
    case "$component" in
      0) comp="auth" ;;
      1) comp="api" ;;
      2) comp="db" ;;
      3) comp="nginx" ;;
      *) comp="worker" ;;
    esac
    user="user$((i % 200))"
    ip="10.$((i % 256)).$(((i / 7) % 256)).$(((i / 13) % 256))"
    req="req-$i"
    status=$(( (i % 25 == 0) ? 500 : 200 ))
    dur=$(( (i * 37) % 2500 ))

    msg="ok"
    if (( i % 3333 == 0 )); then
      msg="password=supersecret-${i}"
    elif (( i % 7777 == 0 )); then
      msg="token=deadbeef${i}"
    elif (( i % 2500 == 0 )); then
      msg="TODO: remove debug flag"
    elif (( i % 1200 == 0 )); then
      msg="panic: null pointer"
    fi

    printf "%s %s %s %s %s %s %s status=%s duration_ms=%s msg=\"%s\"\n" \
      "$ts" "$host" "$level" "$comp" "$user" "$ip" "$req" "$status" "$dur" "$msg"
  done
} > "$DATA_DIR/app.log"

echo "[*] Génération: CSV (awk)..."
{
  echo "ts,host,cpu_pct,mem_pct,req_s,errors_s,latency_ms,env"
  for i in $(seq 1 "$LAB_METRICS_ROWS"); do
    ts="$(date -d "@$(( $(date +%s) - (LAB_METRICS_ROWS - i) ))" '+%F %T' 2>/dev/null || date '+%F %T')"
    host="server$(( (i % 12) + 1 ))"
    cpu=$(( (i * 3) % 101 ))
    mem=$(( (i * 7) % 101 ))
    req=$(( (i * 11) % 500 ))
    err=$(( (i % 97 == 0) ? (i % 7) + 1 : 0 ))
    lat=$(( (i * 13) % 2000 ))
    env="prod"
    if (( i % 5000 == 0 )); then env="staging"; fi
    printf "%s,%s,%s,%s,%s,%s,%s,%s\n" "$ts" "$host" "$cpu" "$mem" "$req" "$err" "$lat" "$env"
  done
} > "$DATA_DIR/metrics.csv"

echo "[*] Génération: JSONL (grep/jq si dispo, awk/sed sinon)..."
{
  for i in $(seq 1 80000); do
    host="server$(( (i % 12) + 1 ))"
    sev="info"
    if (( i % 9000 == 0 )); then sev="error"; fi
    if (( i % 15000 == 0 )); then sev="critical"; fi
    printf '{"ts":"%s","host":"%s","severity":"%s","event":"%s","id":%s}\n' \
      "$(date -Is)" "$host" "$sev" "evt-$((i % 200))" "$i"
  done
} > "$DATA_DIR/events.jsonl"

echo "[*] Génération: arborescence (find/xargs)..."
# Crée des dossiers
for d in $(seq 1 "$LAB_TREE_DIRS"); do
  mkdir -p "$TREE_DIR/dir_$d"
done

# Crée des sous-dossiers (profondeur)
for d in $(seq 1 "$LAB_TREE_DIRS"); do
  base="$TREE_DIR/dir_$d"
  cur="$base"
  for depth in $(seq 1 "$LAB_TREE_DEPTH"); do
    cur="$cur/sub_$depth"
    mkdir -p "$cur"
  done
done

# Crée beaucoup de fichiers variés
for i in $(seq 1 "$LAB_TREE_FILES"); do
  d="$TREE_DIR/dir_$(( (i % LAB_TREE_DIRS) + 1 ))"
  sub="$d/sub_$(( (i % LAB_TREE_DEPTH) + 1 ))"
  ext="log"
  case $((i % 7)) in
    0) ext="conf" ;;
    1) ext="txt" ;;
    2) ext="log" ;;
    3) ext="bak" ;;
    4) ext="csv" ;;
    5) ext="json" ;;
    6) ext="md" ;;
  esac
  f="$sub/file_$i.$ext"
  {
    echo "# file=$f"
    echo "owner=monitorlab"
    echo "id=$i"
    if (( i % 500 == 0 )); then echo "SECRET=do_not_commit"; fi
    if (( i % 333 == 0 )); then echo "DEBUG=true"; fi
    if (( i % 1111 == 0 )); then echo "ALERT: CRITICAL threshold exceeded"; fi
    echo "payload=$(printf '%08x' "$i")"
  } > "$f"

  # Timestamps variés pour find -mtime
  if (( i % 10 == 0 )); then
    touch -d "15 days ago" "$f" 2>/dev/null || true
  elif (( i % 7 == 0 )); then
    touch -d "3 days ago" "$f" 2>/dev/null || true
  fi
done

echo "[*] Compression d'archives (zgrep, find -name '*.gz')..."
gzip -c "$DATA_DIR/app.log" > "$LOG_DIR/archive/app.log.gz"
gzip -c "$DATA_DIR/metrics.csv" > "$LOG_DIR/archive/metrics.csv.gz"

echo "[*] Terminé."
EOF

chmod +x "$LAB_DIR/scripts/populate-lab-data.sh"

echo "[+] Création de processus 'bruyants' (ps/top/htop/nice/kill)..."

cat > "$LAB_DIR/scripts/cpu-hog.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

NAME="${1:-hog}"
LOG_FILE="/var/log/monitoring-lab/app/hogs.log"

echo "[$(date '+%F %T')] INFO cpu-hog start name=$NAME pid=$$ nice=$(ps -o ni= -p $$ | tr -d ' ')" | tee -a "$LOG_FILE"

# Boucle CPU: calculs simples en continu
i=0
while true; do
  i=$((i + 1))
  # Empêche l'optimisation et fait tourner le CPU
  printf "%s" "$(( (i * i + 3*i + 7) % 99991 ))" >/dev/null
done
EOF

chmod +x "$LAB_DIR/scripts/cpu-hog.sh"

cat > "$LAB_DIR/scripts/start-hogs.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

LAB_DIR="/opt/monitoring-lab"
LOG="/var/log/monitoring-lab/app/hogs.log"

echo "[$(date '+%F %T')] INFO starting hogs..." | tee -a "$LOG"

nohup nice -n 0  "$LAB_DIR/scripts/cpu-hog.sh" "hog_nice0"  >/dev/null 2>&1 &
nohup nice -n 10 "$LAB_DIR/scripts/cpu-hog.sh" "hog_nice10" >/dev/null 2>&1 &
nohup nice -n 15 "$LAB_DIR/scripts/cpu-hog.sh" "hog_nice15" >/dev/null 2>&1 &
nohup nice -n 19 "$LAB_DIR/scripts/cpu-hog.sh" "hog_nice19" >/dev/null 2>&1 &

echo "[$(date '+%F %T')] INFO hogs started (check with ps/top/htop) - stop with pkill -f cpu-hog.sh" | tee -a "$LOG"
EOF

chmod +x "$LAB_DIR/scripts/start-hogs.sh"

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

echo "[+] Peuplement massif des données (peut prendre ~1-2 minutes)..."
"$LAB_DIR/scripts/populate-lab-data.sh"

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
Nice=10

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/noisy-workers.service <<EOF
[Unit]
Description=Monitoring Lab - Noisy Workers (CPU hogs)
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
ExecStart=$LAB_DIR/scripts/start-hogs.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "[+] Rechargement systemd..."
systemctl daemon-reload
systemctl enable fake-api.service
systemctl enable log-generator.service
systemctl enable noisy-workers.service
systemctl restart fake-api.service
systemctl restart log-generator.service
systemctl restart noisy-workers.service

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
echo "  noisy-workers.service"
echo
echo "Commandes utiles :"
echo "  systemctl status fake-api"
echo "  systemctl status log-generator"
echo "  systemctl status noisy-workers"
echo "  journalctl -u fake-api -f"
echo "  journalctl -u log-generator -f"
echo "  journalctl -u noisy-workers -f"
echo
echo "Exemples de logs :"
echo "  $LOG_DIR/auth/auth.log"
echo "  $LOG_DIR/app/fake-api.log"
echo "  $LOG_DIR/app/system-alerts.log"
echo "  $LOG_DIR/nginx/access.log"
echo "  $LOG_DIR/nginx/error.log"
echo
echo "Données volumineuses (exercices grep/awk/sed/find/xargs) :"
echo "  $DATA_DIR/app.log"
echo "  $DATA_DIR/metrics.csv"
echo "  $DATA_DIR/events.jsonl"
echo "  $LOG_DIR/archive/app.log.gz"
echo "  $TREE_DIR/"
