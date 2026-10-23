#!/usr/bin/env bash
set -euo pipefail
: "${JAVA_VERSION:?}" "${HADOOP_USER:?}" "${HADOOP_HOME:?}" "${DATA_DIR:?}" "${LOG_DIR:?}" "${CONF_SRC:?}"

host="$(hostname -s)"
conf="${HADOOP_HOME}/etc/hadoop"

for f in "$CONF_SRC"/*; do
  install -o "$HADOOP_USER" -g "$HADOOP_USER" -m 644 "$f" "${conf}/$(basename "$f")"
done
rm -rf "$CONF_SRC"

java_home="$(ls -d /usr/lib/jvm/java-"${JAVA_VERSION}"-openjdk* /usr/lib/jvm/java-1."${JAVA_VERSION}".0-openjdk* 2>/dev/null | head -1 || true)"
[[ -x "${java_home}/bin/java" ]] || { echo "ERROR: на $host нет Java ${JAVA_VERSION}" >&2; exit 1; }

env_file="${conf}/hadoop-env.sh"
sed -i '/# BEGIN managed/,/# END managed/d' "$env_file"
cat >> "$env_file" <<EOF
# BEGIN managed (hdfs-cluster-deploy)
export JAVA_HOME=${java_home}
export HADOOP_LOG_DIR=${LOG_DIR}
export HADOOP_PID_DIR=${DATA_DIR}/pids
# END managed
EOF

echo "[$host] конфиги разложены"
