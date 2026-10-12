#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

mkdir -p "${REPO_DIR}/reports"
report="${REPO_DIR}/reports/check-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$report") 2>&1

errors=0
check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "[OK]   $label"
  else
    echo "[FAIL] $label"; errors=$((errors + 1))
  fi
}

running()       { run_on "$1" "pgrep -u ${HADOOP_USER} -f proc_$2"; }
safemode_off()  { hdfs_as_hadoop "$NN_HOST" "dfsadmin -safemode get" | grep -q OFF; }
fsck_healthy()  { hdfs_as_hadoop "$NN_HOST" "fsck /" | grep -q HEALTHY; }
no_log_errors() { ! run_on "$1" "grep -hE ' (ERROR|FATAL) ' ${LOG_DIR}/*.log | grep -v 'RECEIVED SIGNAL'"; }
smoke_test() {
  run_on "$NN_HOST" "head -c 5M /dev/urandom > /tmp/smoke.bin && chmod 644 /tmp/smoke.bin" \
    && hdfs_as_hadoop "$NN_HOST" "dfs -mkdir -p /tmp" \
    && hdfs_as_hadoop "$NN_HOST" "dfs -put -f /tmp/smoke.bin /tmp/smoke.bin" \
    && hdfs_as_hadoop "$NN_HOST" "fsck /tmp/smoke.bin -files -blocks" | grep -q "Live_repl=${REPLICATION}"
}

jmx="$(run_on "$NN_HOST" "curl -fsS 'http://localhost:${NN_HTTP_PORT}/jmx?qry=Hadoop:service=NameNode,name=FSNamesystemState'" 2>/dev/null || true)"
jget() { sed -nE "s/.*\"$1\" *: *\"?([^\",}]*)\"?.*/\1/p" <<<"$jmx" | head -1; }
dn_count=$(wc -w <<<"$DN_HOSTS")
live=$(jget NumLiveDataNodes); dead=$(jget NumDeadDataNodes); stale=$(jget NumStaleDataNodes)

log "Проверка кластера $(date '+%F %T')"
check "NameNode на $NN_HOST" running "$NN_HOST" namenode
check "Secondary NameNode на $SNN_HOST" running "$SNN_HOST" secondarynamenode
for h in $DN_HOSTS; do check "DataNode на $h" running "$h" datanode; done
check "Живых DataNode: ${live:-?} из $dn_count" test "$live" = "$dn_count"
check "Мёртвых DataNode: ${dead:-?}" test "$dead" = 0
check "Устаревших DataNode: ${stale:-?}" test "$stale" = 0
check "Safe mode выключен" safemode_off
check "Запись файла с репликацией $REPLICATION" smoke_test
check "fsck / HEALTHY" fsck_healthy
for h in $CLUSTER_HOSTS; do check "Нет ERROR/FATAL в логах $h" no_log_errors "$h"; done

hdfs_as_hadoop "$NN_HOST" "dfs -rm -f -skipTrash /tmp/smoke.bin" >/dev/null 2>&1 || true
run_on "$NN_HOST" "rm -f /tmp/smoke.bin" || true

if [[ $errors -eq 0 ]]; then
  log "ИТОГ: кластер целостный"
else
  log "ИТОГ: проблем: $errors"
fi
exit $((errors > 0))
