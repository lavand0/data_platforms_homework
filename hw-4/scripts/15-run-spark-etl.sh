#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

log "Запуск Spark-задачи ${SPARK_APP_NAME} в YARN"

tmp="/tmp/spark-etl-$$"
run_on "$SPARK_HOST" "rm -rf $tmp && mkdir -p $tmp && chmod 777 $tmp"
copy_to "$SPARK_HOST" "${REPO_DIR}/spark/sales_etl.scala" "${tmp}/sales_etl.scala"
run_on "$SPARK_HOST" "chmod 644 ${tmp}/sales_etl.scala"

etl_log="${tmp}/etl.log"
run_on "$SPARK_HOST" "cd /tmp && sudo -u ${HADOOP_USER} -H ${SPARK_HOME}/bin/spark-shell \
  --master yarn --deploy-mode client --name ${SPARK_APP_NAME} \
  --conf spark.hw4.input=hdfs://${NN_HOST}:${NN_RPC_PORT}${RAW_SALES_DIR} \
  --conf spark.hw4.database=${HIVE_DB} --conf spark.hw4.table=${SPARK_TABLE} \
  -i ${tmp}/sales_etl.scala < /dev/null > ${etl_log} 2>&1
  rc=\$?
  grep -E '^(==>|[|+]|.*error:|[a-zA-Z.]*(Exception|Error)|[[:space:]]+at )' ${etl_log}
  [ \$rc = 0 ] && grep -q '^==> Таблица' ${etl_log}" \
  || die "Spark-задача завершилась с ошибкой, полный лог: ${etl_log} на ${SPARK_HOST}"
run_on "$SPARK_HOST" "rm -rf $tmp"
