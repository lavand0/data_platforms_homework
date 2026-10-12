#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_DIR}/config/cluster.env"

SSH_OPTS=(-i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR)

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

is_local() {
  local host="$1"
  [[ "$host" == "$EDGE_HOST" || "$host" == "$(hostname -s)" || "$host" == "$(hostname)" ]]
}

run_on() {
  local host="$1"; shift
  if is_local "$host"; then
    sudo bash -c "$*"
  else
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "sudo bash -c $(printf '%q' "$*")"
  fi
}

run_script_on() {
  local host="$1" script="$2"; shift 2
  if is_local "$host"; then
    sudo env "$@" bash -s < "$script"
  else
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "sudo env $(printf '%q ' "$@") bash -s" < "$script"
  fi
}

copy_to() {
  local host="$1" src="$2" dst="$3"
  if is_local "$host"; then
    cp -f "$src" "$dst"
  else
    scp -q "${SSH_OPTS[@]}" "$src" "${SSH_USER}@${host}:${dst}"
  fi
}

hdfs_as_hadoop() {
  local host="$1"; shift
  run_on "$host" "sudo -u ${HADOOP_USER} ${HADOOP_HOME}/bin/hdfs $*"
}

COMMON_ENV=(
  "HADOOP_USER=${HADOOP_USER}"
  "HADOOP_HOME=${HADOOP_HOME}"
  "HADOOP_VERSION=${HADOOP_VERSION}"
  "DATA_DIR=${DATA_DIR}"
  "LOG_DIR=${LOG_DIR}"
)

daemon_running() {
  run_on "$1" "p=\$(cat ${DATA_DIR}/pids/hadoop-${HADOOP_USER}-$2.pid 2>/dev/null) && ps -o args= -p \"\$p\" | grep -q -- -Dproc_$2"
}
