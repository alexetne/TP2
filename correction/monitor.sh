#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

require_root

# Chemins principaux du TP
LOG_ROOT="/var/log/monitoring-lab"
DATA_DIR="$LOG_ROOT/data"
ARCHIVE_DIR="$LOG_ROOT/archive"
TREE_DIR="$LOG_ROOT/tmp/tree"

STUDENT_DIR="/opt/monitoring-lab/student"
REPORTS_DIR="$STUDENT_DIR/reports"
APP_LOG="$LOG_ROOT/app/student-monitor.log"

# Par defaut, le script ne tue aucun processus.
# Pour tester le kill: sudo LAB_KILL_HOGS=1 ./monitor.sh
LAB_KILL_HOGS="${LAB_KILL_HOGS:-0}"

# Services a surveiller
SERVICES="fake-api log-generator noisy-workers"

echo "===== Student monitor ====="
echo "Debut       : $(date '+%F %T')"
echo "Machine     : $(hostname)"
echo "Utilisateur : $(id -un)"

echo "[1/9] Verification des commandes utiles"
for cmd in grep awk sed find xargs ps systemctl journalctl gzip sort head wc; do
  require_cmd "$cmd"
done

echo "[2/9] Preparation des dossiers de rapport"
mkdir -p "$REPORTS_DIR"
mkdir -p "$(dirname "$APP_LOG")"

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RUN_DIR="$REPORTS_DIR/run-$RUN_ID"
LATEST_LINK="$REPORTS_DIR/latest"

mkdir -p "$RUN_DIR"
rm -rf "$LATEST_LINK"
ln -s "$RUN_DIR" "$LATEST_LINK"

log_info "start run_dir=$RUN_DIR" | tee -a "$APP_LOG"

echo "[3/9] Etat des services systemd"
SERVICES_REPORT="$RUN_DIR/services_status.txt"
: > "$SERVICES_REPORT"

for service in $SERVICES; do
  state="$(systemctl is-active "$service" 2>/dev/null || true)"
  echo "$(date '+%F %T') service=$service state=$state" | tee -a "$SERVICES_REPORT"

  if [[ "$state" != "active" ]]; then
    log_warn "service non actif: $service ($state)" | tee -a "$APP_LOG"
    systemctl status "$service" --no-pager > "$RUN_DIR/systemctl_status_${service}.txt" 2>&1 || true
    journalctl -u "$service" -n 200 --no-pager > "$RUN_DIR/journal_${service}_last200.txt" 2>&1 || true
  fi
done

echo "[4/9] Extraction journald"
{
  echo "== log-generator =="
  journalctl -u log-generator -n 200 --no-pager || true
  echo
  echo "== fake-api =="
  journalctl -u fake-api -n 200 --no-pager || true
} > "$RUN_DIR/journald_extract.txt" 2>&1

grep -E "ERROR|CRITICAL" "$RUN_DIR/journald_extract.txt" \
  > "$RUN_DIR/journald_errors_critical.txt" || true

echo "[5/9] Processus et hogs CPU"
ps aux --sort=-%cpu | head -n 20 > "$RUN_DIR/top_cpu.txt"
ps aux --sort=-%mem | head -n 20 > "$RUN_DIR/top_mem.txt"
ps -eo pid,ni,pcpu,pmem,comm,args > "$RUN_DIR/ps_snapshot.txt"

grep "cpu-hog.sh" "$RUN_DIR/ps_snapshot.txt" > "$RUN_DIR/hogs_found.txt" || true

if [[ "$LAB_KILL_HOGS" == "1" ]]; then
  # On choisit le processus hog qui consomme le plus de CPU.
  HOG_PID="$(awk '/cpu-hog\.sh/ {print $1, $3}' "$RUN_DIR/ps_snapshot.txt" \
    | sort -k2,2nr \
    | head -n 1 \
    | awk '{print $1}')"

  if [[ -n "${HOG_PID:-}" ]]; then
    echo "PID tue: $HOG_PID" > "$RUN_DIR/hog_kill.txt"
    log_warn "kill du hog PID=$HOG_PID" | tee -a "$APP_LOG"
    kill -TERM "$HOG_PID" 2>>"$APP_LOG" || true
  else
    echo "Aucun hog trouve" > "$RUN_DIR/hog_kill.txt"
  fi
else
  echo "Mode observation uniquement. LAB_KILL_HOGS=0" > "$RUN_DIR/hog_kill.txt"
fi

echo "[6/9] Analyse de data/app.log"
APP_LOG_DATA="$DATA_DIR/app.log"
APP_SUMMARY="$RUN_DIR/app_log_summary.txt"

if [[ -f "$APP_LOG_DATA" ]]; then
  {
    echo "source=$APP_LOG_DATA"
    echo "lignes_total=$(wc -l < "$APP_LOG_DATA")"
    echo
    echo "== Nombre par niveau =="
    awk '{print $3}' "$APP_LOG_DATA" | sort | uniq -c | sort -nr
    echo
    echo "== Top 10 hosts =="
    awk '{print $2}' "$APP_LOG_DATA" | sort | uniq -c | sort -nr | head -n 10
    echo
    echo "== Top 10 users =="
    awk '{print $5}' "$APP_LOG_DATA" | sort | uniq -c | sort -nr | head -n 10
    echo
    echo "password=$(grep -c 'password=' "$APP_LOG_DATA" || true)"
    echo "token=$(grep -c 'token=' "$APP_LOG_DATA" || true)"
    echo "status_500=$(grep -c 'status=500' "$APP_LOG_DATA" || true)"
  } > "$APP_SUMMARY"

  sed -E 's/(password=)[^" ]+/\1***MASQUE***/g; s/(token=)[^" ]+/\1***MASQUE***/g' \
    "$APP_LOG_DATA" > "$RUN_DIR/app_log_masque.log"
else
  echo "Fichier manquant: $APP_LOG_DATA" > "$APP_SUMMARY"
fi

echo "[7/9] Analyse de data/metrics.csv"
METRICS_FILE="$DATA_DIR/metrics.csv"
METRICS_SUMMARY="$RUN_DIR/metrics_summary.txt"

if [[ -f "$METRICS_FILE" ]]; then
  {
    echo "source=$METRICS_FILE"
    echo "lignes_total=$(wc -l < "$METRICS_FILE")"
    echo "lignes_staging=$(awk -F, 'NR>1 && $8=="staging" {count++} END {print count+0}' "$METRICS_FILE")"
    echo
    echo "== Top 10 hosts par CPU moyen =="
    awk -F, 'NR>1 {sum[$2]+=$3; count[$2]++} END {for (host in count) print sum[host]/count[host], host}' "$METRICS_FILE" \
      | sort -nr \
      | head -n 10
    echo
    echo "== Top 10 hosts par latence moyenne =="
    awk -F, 'NR>1 {sum[$2]+=$7; count[$2]++} END {for (host in count) print sum[host]/count[host], host}' "$METRICS_FILE" \
      | sort -nr \
      | head -n 10
    echo
    echo "== Anomalies CPU/MEM (exemples) =="
    awk -F, 'NR>1 && ($3 >= 95 || $4 >= 95) {print; count++; if (count == 10) exit}' "$METRICS_FILE"
    echo
    echo "nombre_anomalies=$(awk -F, 'NR>1 && ($3 >= 95 || $4 >= 95) {count++} END {print count+0}' "$METRICS_FILE")"
  } > "$METRICS_SUMMARY"
else
  echo "Fichier manquant: $METRICS_FILE" > "$METRICS_SUMMARY"
fi

echo "[8/9] Analyse de data/events.jsonl et archives"
EVENTS_FILE="$DATA_DIR/events.jsonl"
EVENTS_SUMMARY="$RUN_DIR/events_summary.txt"

if [[ -f "$EVENTS_FILE" ]]; then
  {
    echo "source=$EVENTS_FILE"
    echo "lignes_total=$(wc -l < "$EVENTS_FILE")"
    echo
    echo "== Nombre par severity =="
    grep -oE '"severity":"[^"]+"' "$EVENTS_FILE" \
      | sed 's/"severity":"//; s/"//' \
      | sort \
      | uniq -c \
      | sort -nr
    echo
    echo "== Top 10 hosts =="
    grep -oE '"host":"[^"]+"' "$EVENTS_FILE" \
      | sed 's/"host":"//; s/"//' \
      | sort \
      | uniq -c \
      | sort -nr \
      | head -n 10
  } > "$EVENTS_SUMMARY"
else
  echo "Fichier manquant: $EVENTS_FILE" > "$EVENTS_SUMMARY"
fi

{
  echo "Verification des archives gzip"
  find "$ARCHIVE_DIR" -name "*.gz" -print0 | xargs -0 gzip -t
  echo "OK"
} > "$RUN_DIR/archive_check.txt" 2>&1 || echo "FAIL" >> "$RUN_DIR/archive_check.txt"

echo "[9/9] Exploration de l'arborescence tmp/tree"
find "$TREE_DIR" -type f -name "*.bak" -print0 \
  | xargs -0 -r -n 1 echo > "$RUN_DIR/tree_bak_files.txt"

find "$TREE_DIR" -type f -mtime +7 -print0 \
  | xargs -0 -r -n 1 echo > "$RUN_DIR/tree_mtime_plus7.txt"

find "$TREE_DIR" -type f -print0 \
  | xargs -0 -r grep -Hn "SECRET=" > "$RUN_DIR/tree_secret_hits.txt" 2>/dev/null || true

find "$TREE_DIR" -type f -print0 \
  | xargs -0 -r grep -Hn "DEBUG=true" > "$RUN_DIR/tree_debug_hits.txt" 2>/dev/null || true

{
  echo "# Rapport de monitoring"
  echo
  echo "- Date: $(date -Is)"
  echo "- Dossier: $RUN_DIR"
  echo
  echo "## Fichiers principaux"
  echo "- services_status.txt"
  echo "- journald_extract.txt"
  echo "- top_cpu.txt / top_mem.txt"
  echo "- app_log_summary.txt"
  echo "- metrics_summary.txt"
  echo "- events_summary.txt"
  echo "- archive_check.txt"
  echo "- tree_bak_files.txt"
  echo "- tree_secret_hits.txt"
} > "$RUN_DIR/REPORT.md"

echo "Fin         : $(date '+%F %T')"
echo "Rapport     : $RUN_DIR"
log_info "done run_dir=$RUN_DIR" | tee -a "$APP_LOG"
