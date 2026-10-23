#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

port_open() { run_on "$HIVE_HOST" "timeout 2 bash -c '</dev/tcp/${HIVE_HOST}/$1'" 2>/dev/null; }

start_service() {
  local name="$1" port="$2" timeout="$3" pidfile="${DATA_DIR}/pids/hadoop-${HADOOP_USER}-$1.pid"
  if ! daemon_running "$HIVE_HOST" "$name"; then
    run_on "$HIVE_HOST" "cd /tmp && sudo -u ${HADOOP_USER} -H bash -c 'echo \$\$ > ${pidfile}; exec nohup ${HIVE_HOME}/bin/hive --service ${name} >> ${HIVE_LOG_DIR}/${name}.out 2>&1' < /dev/null > /dev/null 2>&1 &"
  fi
  for _ in $(seq 1 $((timeout / 3))); do
    port_open "$port" && { log "${name} слушает ${HIVE_HOST}:${port}"; return 0; }
    run_on "$HIVE_HOST" "kill -0 \$(cat ${pidfile}) 2>/dev/null" || break
    sleep 3
  done
  run_on "$HIVE_HOST" "tail -n 30 ${HIVE_LOG_DIR}/hive-${name}.log ${HIVE_LOG_DIR}/${name}.out 2>/dev/null" || true
  die "${name} не запустился"
}

log "Запуск Hive Metastore и HiveServer2"
start_service metastore "$METASTORE_PORT" 120
start_service hiveserver2 "$HS2_PORT" 240

run_on "$HIVE_HOST" "
  command -v iptables >/dev/null || { echo 'WARN: iptables не найден, порты Hive не ограничены'; exit 0; }
  ok=1
  for p in ${METASTORE_PORT} ${HS2_PORT} ${HS2_WEBUI_PORT}; do
    iptables -C INPUT -p tcp --dport \$p ! -s ${INTERNAL_NET} -j DROP 2>/dev/null \
      || iptables -I INPUT -p tcp --dport \$p ! -s ${INTERNAL_NET} -j DROP 2>/dev/null \
      || { echo \"WARN: не удалось ограничить порт \$p через iptables\"; ok=0; }
  done
  [ \$ok = 1 ] && echo '==> Порты ${METASTORE_PORT}, ${HS2_PORT}, ${HS2_WEBUI_PORT} доступны только из ${INTERNAL_NET}' || true"
