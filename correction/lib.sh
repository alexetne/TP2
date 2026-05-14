#!/usr/bin/env bash

set -euo pipefail

timestamp() {
  date '+%F %T'
}

log_info() {
  local msg="$1"
  echo "[$(timestamp)] INFO $msg"
}

log_warn() {
  local msg="$1"
  echo "[$(timestamp)] WARN $msg"
}

log_err() {
  local msg="$1"
  echo "[$(timestamp)] ERROR $msg" >&2
}

die() {
  local msg="$1"
  log_err "$msg"
  exit 1
}

require_root() {
  if [[ ${EUID:-0} -ne 0 ]]; then
    die "Ce script doit être exécuté en root."
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Commande requise introuvable: $cmd"
}

ensure_dir() {
  local dir="$1"
  mkdir -p "$dir"
}

make_run_dir() {
  local base="$1"
  local now
  now="$(date '+%Y%m%d-%H%M%S')"
  echo "$base/run-$now"
}

update_latest_symlink() {
  local run_dir="$1"
  local latest_dir="$2"

  rm -rf "$latest_dir"
  mkdir -p "$(dirname "$latest_dir")"
  ln -s "$run_dir" "$latest_dir"
}

