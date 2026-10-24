#!/usr/bin/env bash
set -euo pipefail
: "${JAVA_VERSION:?}" "${HADOOP_USER:?}" "${HADOOP_HOME:?}" "${SPARK_HOME:?}" "${TARBALL:?}" "${CONF_SRC:?}"

host="$(hostname -s)"

if [[ ! -x "${SPARK_HOME}/bin/spark-shell" ]]; then
  [[ -f "$TARBALL" ]] || { echo "ERROR: нет архива $TARBALL" >&2; exit 1; }
  tar -xzf "$TARBALL" -C "$(dirname "$SPARK_HOME")"
fi

java_home="$(ls -d /usr/lib/jvm/java-"${JAVA_VERSION}"-openjdk* /usr/lib/jvm/java-1."${JAVA_VERSION}".0-openjdk* 2>/dev/null | head -1 || true)"
[[ -x "${java_home}/bin/java" ]] || { echo "ERROR: на $host нет Java ${JAVA_VERSION}" >&2; exit 1; }

install -m 644 "${CONF_SRC}/spark-defaults.conf" "${SPARK_HOME}/conf/spark-defaults.conf"
install -m 644 "${CONF_SRC}/hive-site.xml" "${SPARK_HOME}/conf/hive-site.xml"
rm -rf "$CONF_SRC"
cat > "${SPARK_HOME}/conf/spark-env.sh" <<ENV
export JAVA_HOME=${java_home}
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export YARN_CONF_DIR=${HADOOP_HOME}/etc/hadoop
ENV
chown -R "$HADOOP_USER:$HADOOP_USER" "$SPARK_HOME"

echo "[$host] Spark установлен: ${SPARK_HOME}"
