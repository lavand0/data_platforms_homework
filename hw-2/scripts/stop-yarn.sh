#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

stop_daemon() {
  daemon_running "$1" "$3" && run_on "$1" "sudo -u ${HADOOP_USER} ${HADOOP_HOME}/bin/$2 --daemon stop $3" || true
}

log "Остановка YARN"
stop_daemon "$JHS_HOST" mapred historyserver
for h in $NM_HOSTS; do stop_daemon "$h" yarn nodemanager; done
stop_daemon "$RM_HOST" yarn resourcemanager
