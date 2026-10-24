#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

mkdir -p "${REPO_DIR}/reports"
report="${REPO_DIR}/reports/spark-check-$(date +%Y%m%d-%H%M%S).txt"
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

csv="${REPO_DIR}/data/sales.csv"
read -r exp_orders exp_rows exp_parts exp_revenue < <(tail -n +2 "$csv" | awk -F, '
  { split($2, d, "-"); key = d[1]+0 "-" d[2]+0 "-" $3 "-" $4; groups[key] = 1; parts[d[1]+0 "-" d[2]+0] = 1
    revenue += $5 * $6; orders++ }
  END { printf "%d %d %d %.2f\n", orders, length(groups), length(parts), revenue }')

t="${HIVE_DB}.${SPARK_TABLE}"
spark_app_ok() {
  run_on "$SPARK_HOST" "sudo -u ${HADOOP_USER} ${HADOOP_HOME}/bin/yarn application -list -appStates FINISHED -appTypes SPARK 2>/dev/null" \
    | awk -v n="$SPARK_APP_NAME" '$2 == n && $7 == "SUCCEEDED" {ok = 1} END {exit !ok}'
}
raw_in_hdfs()    { hdfs_as_hadoop "$SPARK_HOST" "dfs -test -f ${RAW_SALES_DIR}/sales.csv"; }
jars_in_hdfs()   { hdfs_as_hadoop "$SPARK_HOST" "dfs -test -d ${SPARK_JARS_HDFS}"; }
in_metastore()   { [[ "$(pg_query "SELECT count(*) FROM \"TBLS\" t JOIN \"DBS\" d ON t.\"DB_ID\" = d.\"DB_ID\" WHERE t.\"TBL_NAME\" = '${SPARK_TABLE}' AND d.\"NAME\" = '${HIVE_DB}'")" == 1 ]]; }
orc_format()     { hive_query "DESCRIBE FORMATTED ${SPARK_TABLE}" | grep -q 'OrcInputFormat'; }

parts="$(hive_query "SHOW PARTITIONS ${SPARK_TABLE}" | grep -c '^sale_year=')"
rows="$(hive_query "SELECT count(*) FROM ${SPARK_TABLE}")"
totals="$(hive_query "SELECT sum(orders), sum(revenue) FROM ${SPARK_TABLE}" | sed '/^$/d')"
dirs="$(hive_query "SELECT count(DISTINCT regexp_extract(INPUT__FILE__NAME, '(sale_year=[0-9]+/sale_month=[0-9]+)', 1)) FROM ${SPARK_TABLE}")"
read -r orders revenue <<<"$totals"

log "Проверка Spark $(date '+%F %T')"
check "Библиотеки Spark ${SPARK_VERSION} лежат в HDFS ${SPARK_JARS_HDFS}" jars_in_hdfs
check "Исходные данные лежат в HDFS ${RAW_SALES_DIR}/sales.csv" raw_in_hdfs
check "Spark-задача ${SPARK_APP_NAME} выполнена в YARN (FINISHED, SUCCEEDED)" spark_app_ok
check "Таблица ${t} зарегистрирована в общем метасторе PostgreSQL" in_metastore
check "Hive видит таблицу ${t} в формате ORC" orc_format
check "Hive: партиций ${parts:-?} из ${exp_parts}" test "$parts" = "$exp_parts"
check "Hive: каталогов партиций с данными ${dirs:-?} из ${exp_parts}" test "$dirs" = "$exp_parts"
check "Hive: строк ${rows:-?} из ${exp_rows}" test "$rows" = "$exp_rows"
check "Hive: заказов ${orders:-?} из ${exp_orders}" test "$orders" = "$exp_orders"
check "Hive: выручка ${revenue:-?} из ${exp_revenue}" test "$revenue" = "$exp_revenue"

if [[ $errors -eq 0 ]]; then
  log "ИТОГ: Spark на YARN обработал данные из HDFS, Hive читает результат"
else
  log "ИТОГ: проблем: $errors"
fi
exit $((errors > 0))
