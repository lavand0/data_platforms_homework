#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

mkdir -p "${REPO_DIR}/reports"
report="${REPO_DIR}/reports/hive-check-$(date +%Y%m%d-%H%M%S).txt"
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
csv_rows=$(($(wc -l < "$csv") - 1))
csv_months="$(tail -n +2 "$csv" | awk -F, '{split($2, d, "-"); print d[1]+0 "\t" d[2]+0}' | sort | uniq -c | awk '{print $2 "\t" $3 "\t" $1}' | sort -n -k1,1 -k2,2)"
csv_partitions=$(wc -l <<<"$csv_months")

schema_in_postgres() { [[ "$(pg_query 'SELECT "SCHEMA_VERSION" FROM "VERSION"')" == "$HIVE_VERSION" ]]; }
remote_metastore()   { hive_query "SET hive.metastore.uris" default | grep -q "=thrift://${HIVE_HOST}:${METASTORE_PORT}"; }
internal_only()      { ! run_on "$HIVE_HOST" "ss -Htln" | awk '{print $4}' | grep -qE "^(0\.0\.0\.0|\*|\[::\]):(${METASTORE_PORT}|${HS2_PORT})$"; }
pg_partitions()      { pg_query "SELECT count(*) FROM \"PARTITIONS\" p JOIN \"TBLS\" t ON p.\"TBL_ID\" = t.\"TBL_ID\" JOIN \"DBS\" d ON t.\"DB_ID\" = d.\"DB_ID\" WHERE t.\"TBL_NAME\" = 'sales' AND d.\"NAME\" = '${HIVE_DB}'"; }
hive_partitions()    { hive_query "SHOW PARTITIONS sales" | grep -c '^sale_year='; }
partition_dirs()     { hive_query "SELECT count(DISTINCT regexp_extract(INPUT__FILE__NAME, '(sale_year=[0-9]+/sale_month=[0-9]+)', 1)) FROM sales"; }
rows_by_month()      { hive_query "SELECT sale_year, sale_month, count(*) FROM sales GROUP BY sale_year, sale_month ORDER BY sale_year, sale_month" | sed "/^$/d"; }

parallel_clients() {
  run_on "$HIVE_HOST" "cd /tmp
    for i in 1 2 3; do
      ( sudo -u ${HADOOP_USER} -H ${HIVE_HOME}/bin/beeline -u jdbc:hive2://${HIVE_HOST}:${HS2_PORT}/${HIVE_DB} -n client\$i \
          --silent=true -e 'SELECT region, count(*) FROM sales GROUP BY region' > /tmp/hive-client-\$i.log 2>&1
        echo \$? > /tmp/hive-client-\$i.rc ) &
    done
    wait
    cat /tmp/hive-client-1.rc /tmp/hive-client-2.rc /tmp/hive-client-3.rc" | grep -c '^0$' | grep -qx 3
}

log "Проверка Hive $(date '+%F %T')"
check "PostgreSQL на $HIVE_HOST" run_on "$HIVE_HOST" "systemctl is-active --quiet postgresql"
check "Hive Metastore на $HIVE_HOST" daemon_running "$HIVE_HOST" metastore
check "HiveServer2 на $HIVE_HOST" daemon_running "$HIVE_HOST" hiveserver2
check "Схема метастора ${HIVE_VERSION} хранится в PostgreSQL (база ${METASTORE_DB})" schema_in_postgres
check "HiveServer2 работает с удалённым Metastore thrift://${HIVE_HOST}:${METASTORE_PORT}" remote_metastore
check "Порты ${METASTORE_PORT} и ${HS2_PORT} слушают только внутренний адрес" internal_only

parts_hive="$(hive_partitions)"; parts_pg="$(pg_partitions)"; dirs="$(partition_dirs)"
rows="$(hive_query "SELECT count(*) FROM sales")"
check "Партиций в Hive: ${parts_hive:-?} из ${csv_partitions}" test "$parts_hive" = "$csv_partitions"
check "Партиций в метасторе PostgreSQL: ${parts_pg:-?}" test "$parts_pg" = "$csv_partitions"
check "Каталогов партиций с данными в HDFS: ${dirs:-?}" test "$dirs" = "$csv_partitions"
check "Строк в ${HIVE_DB}.sales: ${rows:-?} из ${csv_rows}" test "$rows" = "$csv_rows"
check "Число строк в каждой партиции совпадает с CSV" test "$(rows_by_month)" = "$csv_months"
check "3 клиента одновременно выполнили запросы через HiveServer2" parallel_clients

if [[ $errors -eq 0 ]]; then
  log "ИТОГ: Hive работает, данные загружены в партиционированную таблицу"
else
  log "ИТОГ: проблем: $errors"
fi
exit $((errors > 0))
