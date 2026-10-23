#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

stop_daemon() {
  local cmd="sudo -u ${HADOOP_USER} ${HADOOP_HOME}/bin/hdfs --daemon"
  daemon_running "$1" "$2" && run_on "$1" "$cmd stop $2" || true
}

log "Остановка кластера"
stop_daemon "$SNN_HOST" secondarynamenode
for h in $DN_HOSTS; do stop_daemon "$h" datanode; done
stop_daemon "$NN_HOST" namenode
