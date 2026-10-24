#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

mkdir -p "${REPO_DIR}/reports"
report="${REPO_DIR}/reports/yarn-check-$(date +%Y%m%d-%H%M%S).txt"
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

yarn_cmd() { run_on "$RM_HOST" "sudo -u ${HADOOP_USER} ${HADOOP_HOME}/bin/yarn $*"; }

pi_job() {
  run_on "$NN_HOST" "sudo -u ${HADOOP_USER} ${HADOOP_HOME}/bin/yarn jar ${HADOOP_HOME}/share/hadoop/mapreduce/hadoop-mapreduce-examples-${HADOOP_VERSION}.jar pi 3 100 2>&1" \
    | grep -q "Estimated value of Pi"
}

history_has_job() {
  for _ in $(seq 1 15); do
    run_on "$JHS_HOST" "curl --noproxy '*' -fsS http://localhost:${JHS_WEB_PORT}/ws/v1/history/mapreduce/jobs" | grep -q SUCCEEDED && return 0
    sleep 2
  done
  return 1
}

no_log_errors() {
  ! run_on "$1" "grep -hE ' (ERROR|FATAL) ' ${LOG_DIR}/*resourcemanager* ${LOG_DIR}/*nodemanager* ${LOG_DIR}/*historyserver* 2>/dev/null | grep -v 'RECEIVED SIGNAL'"
}

IFS=: read -r web_user web_pass < "$WEB_CREDENTIALS_FILE" || die "Нет файла $WEB_CREDENTIALS_FILE, запустите 09-publish-web.sh"
web_ok()     { curl --noproxy '*' -fsSL -o /dev/null -u "${web_user}:${web_pass}" "http://127.0.0.1:$1/"; }
web_closed() { [[ "$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$1/")" == 401 ]]; }

nm_count=$(wc -w <<<"$NM_HOSTS")
running=$(yarn_cmd "node -list -states RUNNING" 2>/dev/null | sed -nE 's/.*Total Nodes:([0-9]+).*/\1/p')

log "Проверка YARN $(date '+%F %T')"
check "ResourceManager на $RM_HOST" daemon_running "$RM_HOST" resourcemanager
for h in $NM_HOSTS; do check "NodeManager на $h" daemon_running "$h" nodemanager; done
check "JobHistory Server на $JHS_HOST" daemon_running "$JHS_HOST" historyserver
check "NodeManager в состоянии RUNNING: ${running:-?} из $nm_count" test "$running" = "$nm_count"
check "MapReduce-задача pi выполнена" pi_job
check "Задача видна в JobHistory Server" history_has_job
for h in $CLUSTER_HOSTS; do check "Нет ERROR/FATAL в логах YARN на $h" no_log_errors "$h"; done
while read -r name port target; do
  check "Веб-интерфейс $name: http://${EDGE_PUBLIC_IP}:${port}" web_ok "$port"
done <<<"$WEB_UIS"
check "Без пароля веб-интерфейсы закрыты (HTTP 401)" web_closed "$RM_WEB_PORT"

if [[ $errors -eq 0 ]]; then
  log "ИТОГ: YARN работает, веб-интерфейсы опубликованы"
else
  log "ИТОГ: проблем: $errors"
fi
exit $((errors > 0))
