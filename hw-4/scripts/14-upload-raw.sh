#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

csv="${1:-${REPO_DIR}/data/sales.csv}"
[[ -s "$csv" ]] || die "Нет файла $csv"
log "Загрузка $(basename "$csv") в HDFS ${RAW_SALES_DIR}"

tmp="/tmp/raw-upload-$$"
run_on "$SPARK_HOST" "rm -rf $tmp && mkdir -p $tmp && chmod 777 $tmp"
copy_to "$SPARK_HOST" "$csv" "${tmp}/sales.csv"
run_on "$SPARK_HOST" "chmod 644 ${tmp}/sales.csv"
hdfs_as_hadoop "$SPARK_HOST" "dfs -mkdir -p ${RAW_SALES_DIR}"
hdfs_as_hadoop "$SPARK_HOST" "dfs -put -f ${tmp}/sales.csv ${RAW_SALES_DIR}/sales.csv"
run_on "$SPARK_HOST" "rm -rf $tmp"
hdfs_as_hadoop "$SPARK_HOST" "dfs -ls ${RAW_SALES_DIR}" | sed 's/^/    /'
