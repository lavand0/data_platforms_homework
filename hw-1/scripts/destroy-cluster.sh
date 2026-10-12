#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

purge=0; yes=0
for a in "$@"; do
  case "$a" in --purge) purge=1 ;; --yes|-y) yes=1 ;; *) die "Неизвестный аргумент: $a" ;; esac
done

if [[ $yes -ne 1 ]]; then
  read -r -p "Все данные HDFS будут удалены. Продолжить? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 0
fi

"${REPO_DIR}/scripts/stop-cluster.sh"

log "Удаление данных HDFS и логов"
for h in $CLUSTER_HOSTS; do
  run_on "$h" "rm -rf ${DATA_DIR:?}/nn/* ${DATA_DIR:?}/snn/* ${DATA_DIR:?}/dn/* ${DATA_DIR:?}/tmp/* ${LOG_DIR:?}/*"
done

if [[ $purge -eq 1 ]]; then
  log "Удаление Hadoop"
  for h in $ALL_HOSTS; do
    run_on "$h" "rm -rf ${HADOOP_HOME:?} /opt/hadoop-${HADOOP_VERSION:?} /etc/profile.d/hadoop.sh"
  done
fi
