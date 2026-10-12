#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

daemon() {
  run_on "$1" "sudo -u ${HADOOP_USER} ${HADOOP_HOME}/bin/hdfs --daemon $2 $3"
}

ensure_started() {
  daemon "$1" status "$2" >/dev/null 2>&1 || daemon "$1" start "$2"
}

wait_for() {
  for _ in $(seq 1 30); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

all_dn_live() {
  local n
  n=$(hdfs_as_hadoop "$NN_HOST" "dfsadmin -report -live" | sed -nE 's/^Live datanodes \(([0-9]+)\).*/\1/p')
  [[ ${n:-0} -ge $(wc -w <<<"$DN_HOSTS") ]]
}

log "Запуск кластера"

if ! run_on "$NN_HOST" "test -f ${DATA_DIR}/nn/current/VERSION"; then
  hdfs_as_hadoop "$NN_HOST" "namenode -format -nonInteractive -clusterId ${CLUSTER_ID}"
fi

ensure_started "$NN_HOST" namenode
wait_for hdfs_as_hadoop "$NN_HOST" "dfsadmin -safemode get" || die "NameNode не отвечает, см. ${LOG_DIR} на ${NN_HOST}"

for h in $DN_HOSTS; do
  ensure_started "$h" datanode
done
ensure_started "$SNN_HOST" secondarynamenode

wait_for all_dn_live || die "Зарегистрировались не все DataNode"
hdfs_as_hadoop "$NN_HOST" "dfsadmin -safemode wait" >/dev/null
log "Кластер запущен"
