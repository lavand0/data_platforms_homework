#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

csv="${1:-${REPO_DIR}/data/sales.csv}"
[[ -s "$csv" ]] || die "Нет файла $csv"
log "Загрузка $(basename "$csv") в партиционированную таблицу ${HIVE_DB}.sales"

tmp="/tmp/hive-load-$$"
run_on "$HIVE_HOST" "rm -rf $tmp && mkdir -p $tmp && chmod 777 $tmp"
copy_to "$HIVE_HOST" "$csv" "${tmp}/sales.csv"
copy_to "$HIVE_HOST" "${REPO_DIR}/sql/load_sales.sql" "${tmp}/load_sales.sql"
run_on "$HIVE_HOST" "chmod 644 ${tmp}/*"

hdfs_as_hadoop "$HIVE_HOST" "dfs -mkdir -p ${HIVE_STAGING}"
hdfs_as_hadoop "$HIVE_HOST" "dfs -put -f ${tmp}/sales.csv ${HIVE_STAGING}/sales.csv"

run_on "$HIVE_HOST" "set -o pipefail; cd /tmp && sudo -u ${HADOOP_USER} -H ${HIVE_HOME}/bin/beeline \
  -u jdbc:hive2://${HIVE_HOST}:${HS2_PORT}/default -n ${HADOOP_USER} --silent=true \
  --hivevar db=${HIVE_DB} --hivevar staging=${HIVE_STAGING} -f ${tmp}/load_sales.sql 2> >(grep -v '^SLF4J' >&2) | sed '/^[[:space:]]*$/d'" \
  || die "Загрузка не выполнена, см. ${HIVE_LOG_DIR}/hive-hiveserver2.log на ${HIVE_HOST}"
run_on "$HIVE_HOST" "rm -rf $tmp"

log "Партиции таблицы ${HIVE_DB}.sales:"
hive_query "SHOW PARTITIONS sales" | sed 's/^/    /'
