#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

log "Установка Spark ${SPARK_VERSION} на ${SPARK_HOST}"

dl_dir="${REPO_DIR}/downloads"
name="spark-${SPARK_VERSION}-bin-hadoop3.tgz"
tarball="${dl_dir}/${name}"
mkdir -p "$dl_dir"

if [[ ! -s "$tarball" || ! -s "${tarball}.sha512" ]]; then
  for mirror in $SPARK_MIRRORS; do
    url="${mirror}/spark-${SPARK_VERSION}/${name}"
    curl -fL --retry 3 --progress-bar -o "${tarball}.part" "$url" \
      && curl -fsSL -o "${tarball}.sha512" "${url}.sha512" \
      && mv "${tarball}.part" "$tarball" && break
  done
  [[ -s "$tarball" ]] || die "Не удалось скачать ${name}, положите его и ${name}.sha512 в ${dl_dir}"
fi
expected="$(tr -d ' \r\n' < "${tarball}.sha512" | grep -oiE '[0-9a-f]{128}' | head -1 | tr 'A-F' 'a-f')"
actual="$(sha512sum "$tarball" | awk '{print $1}')"
[[ -n "$expected" && "$expected" == "$actual" ]] || die "SHA-512 не совпадает, удалите ${tarball}"

build="${REPO_DIR}/build/spark"
rm -rf "$build"; mkdir -p "$build"
render "${REPO_DIR}/config/spark/spark-defaults.conf" > "${build}/spark-defaults.conf"
render "${REPO_DIR}/config/spark/hive-site.xml" > "${build}/hive-site.xml"

tmp="/tmp/spark-install-$$"
run_on "$SPARK_HOST" "rm -rf $tmp && mkdir -p $tmp && chmod 777 $tmp"
copy_to "$SPARK_HOST" "${build}/spark-defaults.conf" "${tmp}/spark-defaults.conf"
copy_to "$SPARK_HOST" "${build}/hive-site.xml" "${tmp}/hive-site.xml"
remote_tar="none"
if ! run_on "$SPARK_HOST" "test -x ${SPARK_HOME}/bin/spark-shell"; then
  remote_tar="${tmp}/${name}"
  copy_to "$SPARK_HOST" "$tarball" "$remote_tar"
fi
run_script_on "$SPARK_HOST" "${REPO_DIR}/remote/install-spark.sh" "${COMMON_ENV[@]}" \
  "SPARK_HOME=${SPARK_HOME}" "TARBALL=${remote_tar}" "CONF_SRC=${tmp}"

log "Загрузка библиотек Spark в HDFS ${SPARK_JARS_HDFS}"
run_on "$SPARK_HOST" "
  hdfs='sudo -u ${HADOOP_USER} ${HADOOP_HOME}/bin/hdfs'
  local_jars=\$(ls ${SPARK_HOME}/jars/*.jar | wc -l)
  hdfs_jars=\$(\$hdfs dfs -ls ${SPARK_JARS_HDFS} 2>/dev/null | grep -c '\.jar\$' || true)
  if [ \"\$local_jars\" != \"\$hdfs_jars\" ]; then
    \$hdfs dfs -mkdir -p ${SPARK_JARS_HDFS} && \$hdfs dfs -put -f ${SPARK_HOME}/jars/*.jar ${SPARK_JARS_HDFS}/
  fi
  echo \"    библиотек в HDFS: \$(\$hdfs dfs -ls ${SPARK_JARS_HDFS} | grep -c '\.jar\$') из \$local_jars\""
