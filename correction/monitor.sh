#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=correction/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root

LAB_DIR="/opt/monitoring-lab"
LOG_ROOT="/var/log/monitoring-lab"

DATA_DIR="$LOG_ROOT/data"
ARCHIVE_DIR="$LOG_ROOT/archive"
TREE_DIR="$LOG_ROOT/tmp/tree"

SERVICES=("fake-api" "log-generator" "noisy-workers")

STUDENT_DIR="/opt/monitoring-lab/student"
REPORTS_DIR="$STUDENT_DIR/reports"
LATEST_LINK="$REPORTS_DIR/latest"

APP_LOG="$LOG_ROOT/app/student-monitor.log"

: "${LAB_KILL_HOGS:=0}"

main() {
  require_cmd grep
  require_cmd awk
  require_cmd sed
  require_cmd find
  require_cmd xargs
  require_cmd ps
  require_cmd systemctl
  require_cmd journalctl
  require_cmd gzip
  require_cmd sort
  require_cmd head
  require_cmd wc

  ensure_dir "$STUDENT_DIR"
  ensure_dir "$REPORTS_DIR"
  ensure_dir "$(dirname "$APP_LOG")"

  local run_dir
  run_dir="$(make_run_dir "$REPORTS_DIR")"
  ensure_dir "$run_dir"
  update_latest_symlink "$run_dir" "$LATEST_LINK"

  log_info "student-monitor start run_dir=$run_dir" | tee -a "$APP_LOG"

  check_services "$run_dir"
  collect_journald_extract "$run_dir"
  collect_process_snapshot "$run_dir"
  process_datasets "$run_dir"
  explore_tree "$run_dir"

  write_report_md "$run_dir"

  log_info "student-monitor done run_dir=$run_dir" | tee -a "$APP_LOG"
}

check_services() {
  local run_dir="$1"
  local out="$run_dir/services_status.txt"
  : > "$out"

  for svc in "${SERVICES[@]}"; do
    local state
    state="$(systemctl is-active "$svc" 2>/dev/null || true)"
    echo "$(timestamp) service=$svc state=$state" | tee -a "$APP_LOG" >> "$out"

    if [[ "$state" != "active" ]]; then
      log_warn "service not active: $svc (state=$state)" | tee -a "$APP_LOG"
      systemctl status "$svc" --no-pager > "$run_dir/systemctl_status_${svc}.txt" 2>&1 || true
      journalctl -u "$svc" -n 200 --no-pager > "$run_dir/journal_${svc}_last200.txt" 2>&1 || true
    fi
  done
}

collect_journald_extract() {
  local run_dir="$1"
  local out="$run_dir/journald_extract.txt"
  : > "$out"

  {
    echo "== journalctl -u log-generator (last 200) =="
    journalctl -u log-generator -n 200 --no-pager || true
    echo
    echo "== journalctl -u fake-api (last 200) =="
    journalctl -u fake-api -n 200 --no-pager || true
  } > "$out" 2>&1

  {
    echo "== filtered (ERROR|CRITICAL) =="
    grep -E 'ERROR|CRITICAL' "$out" || true
  } > "$run_dir/journald_errors_critical.txt"
}

collect_process_snapshot() {
  local run_dir="$1"

  ps aux --sort=-%cpu | head -n 20 > "$run_dir/top_cpu.txt"
  ps aux --sort=-%mem | head -n 20 > "$run_dir/top_mem.txt"

  # PID, nice, cpu, mem, command, args
  ps -eo pid=,ni=,pcpu=,pmem=,comm=,args= > "$run_dir/ps_snapshot.txt"

  awk '
    /cpu-hog\.sh/ {
      printf "pid=%s nice=%s cpu=%s mem=%s comm=%s args=%s\n", $1, $2, $3, $4, $5, $0
    }
  ' "$run_dir/ps_snapshot.txt" > "$run_dir/hogs_found.txt" || true

  if [[ "${LAB_KILL_HOGS}" == "1" ]]; then
    kill_one_hog "$run_dir"
  else
    log_info "LAB_KILL_HOGS=0 (no kill)" | tee -a "$APP_LOG"
  fi
}

kill_one_hog() {
  local run_dir="$1"
  local snapshot="$run_dir/ps_snapshot.txt"
  local picked="$run_dir/hog_kill_target.txt"

  # Pick the hog with highest %CPU (field 3), store PID
  awk '
    /cpu-hog\.sh/ { print $1, $3 }
  ' "$snapshot" | sort -k2,2nr | head -n 1 > "$picked" || true

  if [[ ! -s "$picked" ]]; then
    log_warn "LAB_KILL_HOGS=1 but no hog found" | tee -a "$APP_LOG"
    return 0
  fi

  local pid
  pid="$(awk '{print $1}' "$picked")"
  log_warn "LAB_KILL_HOGS=1 killing hog pid=$pid" | tee -a "$APP_LOG"
  kill -TERM "$pid" 2>>"$APP_LOG" || true
  sleep 1
  kill -KILL "$pid" 2>>"$APP_LOG" || true
}

process_datasets() {
  local run_dir="$1"
  summarize_app_log "$run_dir"
  summarize_metrics_csv "$run_dir"
  summarize_events_jsonl "$run_dir"
  check_archives "$run_dir"
}

summarize_app_log() {
  local run_dir="$1"
  local src="$DATA_DIR/app.log"
  local out="$run_dir/app_log_summary.txt"

  if [[ ! -f "$src" ]]; then
    echo "missing_file=$src" > "$out"
    log_warn "missing dataset: $src" | tee -a "$APP_LOG"
    return 0
  fi

  {
    echo "source=$src"
    echo "lines_total=$(wc -l < "$src")"
    echo
    echo "== count by level =="
    awk '{print $3}' "$src" | sort | awk '{c[$1]++} END{for (k in c) printf "%s %d\n", k, c[k]}' | sort
    echo
    echo "== top 10 hosts =="
    awk '{print $2}' "$src" | sort | awk '{c[$1]++} END{for (k in c) printf "%d %s\n", c[k], k}' | sort -nr | head -n 10
    echo
    echo "== top 10 users =="
    awk '{print $5}' "$src" | sort | awk '{c[$1]++} END{for (k in c) printf "%d %s\n", c[k], k}' | sort -nr | head -n 10
    echo
    echo "password_occurrences=$(grep -c 'password=' "$src" || true)"
    echo "token_occurrences=$(grep -c 'token=' "$src" || true)"
    echo "status_500_occurrences=$(grep -c 'status=500' "$src" || true)"
  } > "$out"

  # Exemple de masquage "sed" (sans détruire l'original)
  sed -E 's/(password=)[^" ]+/\1***REDACTED***/g; s/(token=)[^" ]+/\1***REDACTED***/g' \
    "$src" > "$run_dir/app_log_redacted.log"
}

summarize_metrics_csv() {
  local run_dir="$1"
  local src="$DATA_DIR/metrics.csv"
  local out="$run_dir/metrics_summary.txt"
  local staging_lines

  if [[ ! -f "$src" ]]; then
    echo "missing_file=$src" > "$out"
    log_warn "missing dataset: $src" | tee -a "$APP_LOG"
    return 0
  fi

  staging_lines="$(awk -F, 'NR>1 && $8=="staging"{c++} END{print c+0}' "$src")"

  {
    echo "source=$src"
    echo "lines_total=$(wc -l < "$src")"
    echo
    echo "staging_lines=$staging_lines"
    echo
    echo "== top 10 hosts by avg cpu_pct =="
    awk -F, '
      NR==1{next}
      {host=$2; cpu=$3+0; sum[host]+=cpu; cnt[host]++}
      END{for (h in cnt) printf "%.2f %s\n", sum[h]/cnt[h], h}
    ' "$src" | sort -nr | head -n 10
    echo
    echo "== top 10 hosts by avg latency_ms =="
    awk -F, '
      NR==1{next}
      {host=$2; lat=$7+0; sum[host]+=lat; cnt[host]++}
      END{for (h in cnt) printf "%.2f %s\n", sum[h]/cnt[h], h}
    ' "$src" | sort -nr | head -n 10
    echo
    echo "== anomalies (cpu>=95 OR mem>=95) count + examples =="
    awk -F, '
      NR==1{next}
      ($3+0>=95 || $4+0>=95){c++; if (c<=10) print}
      END{print "count=" c+0}
    ' "$src"
  } > "$out"
}

summarize_events_jsonl() {
  local run_dir="$1"
  local src="$DATA_DIR/events.jsonl"
  local out="$run_dir/events_summary.txt"

  if [[ ! -f "$src" ]]; then
    echo "missing_file=$src" > "$out"
    log_warn "missing dataset: $src" | tee -a "$APP_LOG"
    return 0
  fi

  {
    echo "source=$src"
    echo "lines_total=$(wc -l < "$src")"
    echo
    echo "== count by severity =="
    grep -oE '"severity":"[^"]+"' "$src" | awk -F\" '{print $4}' | sort | awk '{c[$1]++} END{for (k in c) printf "%s %d\n", k, c[k]}' | sort
    echo
    echo "== top 10 hosts =="
    grep -oE '"host":"[^"]+"' "$src" | awk -F\" '{print $4}' | sort | awk '{c[$1]++} END{for (k in c) printf "%d %s\n", c[k], k}' | sort -nr | head -n 10
  } > "$out"
}

check_archives() {
  local run_dir="$1"
  local out="$run_dir/archive_check.txt"

  if [[ ! -d "$ARCHIVE_DIR" ]]; then
    echo "missing_dir=$ARCHIVE_DIR" > "$out"
    log_warn "missing dir: $ARCHIVE_DIR" | tee -a "$APP_LOG"
    return 0
  fi

  {
    echo "archive_dir=$ARCHIVE_DIR"
    echo "== gzip -t results =="
    find "$ARCHIVE_DIR" -name '*.gz' -print0 | xargs -0 gzip -t
    echo "OK"
  } > "$out" 2>&1 || {
    echo "FAIL (see errors above)" >> "$out"
    log_warn "archive check failed (see $out)" | tee -a "$APP_LOG"
  }
}

explore_tree() {
  local run_dir="$1"

  if [[ ! -d "$TREE_DIR" ]]; then
    echo "missing_dir=$TREE_DIR" > "$run_dir/tree_missing.txt"
    log_warn "missing dir: $TREE_DIR" | tee -a "$APP_LOG"
    return 0
  fi

  find "$TREE_DIR" -type f -name '*.bak' -print0 \
    | xargs -0 -I{} echo "{}" > "$run_dir/tree_bak_files.txt"
  echo "count=$(wc -l < "$run_dir/tree_bak_files.txt")" > "$run_dir/tree_bak_summary.txt"
  head -n 20 "$run_dir/tree_bak_files.txt" >> "$run_dir/tree_bak_summary.txt" || true

  find "$TREE_DIR" -type f -mtime +7 -print0 \
    | xargs -0 -I{} echo "{}" > "$run_dir/tree_mtime_plus7.txt"
  echo "count=$(wc -l < "$run_dir/tree_mtime_plus7.txt")" > "$run_dir/tree_mtime_plus7_summary.txt"
  head -n 20 "$run_dir/tree_mtime_plus7.txt" >> "$run_dir/tree_mtime_plus7_summary.txt" || true

  find "$TREE_DIR" -type f -print0 \
    | xargs -0 grep -Hn 'SECRET=' > "$run_dir/tree_secret_hits.txt" 2>/dev/null || true

  find "$TREE_DIR" -type f -print0 \
    | xargs -0 grep -Hn 'DEBUG=true' > "$run_dir/tree_debug_hits.txt" 2>/dev/null || true
}

write_report_md() {
  local run_dir="$1"
  local out="$run_dir/REPORT.md"

  {
    echo "# Student Monitor Report"
    echo
    echo "- generated_at: $(date -Is)"
    echo "- run_dir: $run_dir"
    echo
    echo "## Key files"
    echo "- services: services_status.txt"
    echo "- journald: journald_extract.txt, journald_errors_critical.txt"
    echo "- process: top_cpu.txt, top_mem.txt, hogs_found.txt"
    echo "- datasets: app_log_summary.txt, metrics_summary.txt, events_summary.txt, archive_check.txt"
    echo "- tree: tree_bak_summary.txt, tree_mtime_plus7_summary.txt, tree_secret_hits.txt, tree_debug_hits.txt"
  } > "$out"
}

main "$@"
