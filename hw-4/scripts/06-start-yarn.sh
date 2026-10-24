#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

ensure_started() {
  daemon_running "$1" "$3" || run_on "$1" "sudo -u ${HADOOP_USER} ${HADOOP_HOME}/bin/$2 --daemon start $3"
  sleep 3
  daemon_running "$1" "$3" || {
    run_on "$1" "tail -n 20 ${LOG_DIR}/*$3*.log ${LOG_DIR}/*$3*.out 2>/dev/null" || true
    die "$3 не запустился на $1"
  }
}

nm_running() {
  local n
  n=$(run_on "$RM_HOST" "sudo -u ${HADOOP_USER} ${HADOOP_HOME}/bin/yarn node -list -states RUNNING 2>/dev/null" | sed -nE 's/.*Total Nodes:([0-9]+).*/\1/p')
  [[ ${n:-0} -ge $(wc -w <<<"$NM_HOSTS") ]]
}

log "Запуск YARN"

hdfs_as_hadoop "$NN_HOST" "dfs -mkdir -p /tmp/logs /user/${HADOOP_USER}"
hdfs_as_hadoop "$NN_HOST" "dfs -chmod 1777 /tmp /tmp/logs"

ensure_started "$RM_HOST" yarn resourcemanager
for h in $NM_HOSTS; do
  ensure_started "$h" yarn nodemanager
done
ensure_started "$JHS_HOST" mapred historyserver

for _ in $(seq 1 30); do
  nm_running && { log "YARN запущен"; exit 0; }
  sleep 2
done
die "В ResourceManager зарегистрировались не все NodeManager"
