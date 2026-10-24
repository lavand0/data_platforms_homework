#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

stop_service() {
  local pidfile="${DATA_DIR}/pids/hadoop-${HADOOP_USER}-$1.pid"
  daemon_running "$HIVE_HOST" "$1" || return 0
  run_on "$HIVE_HOST" "
    p=\$(cat ${pidfile}); kill \$p
    for _ in \$(seq 1 30); do kill -0 \$p 2>/dev/null || exit 0; sleep 1; done
    kill -9 \$p"
}

log "Остановка Hive"
stop_service hiveserver2
stop_service metastore
