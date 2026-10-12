#!/usr/bin/env bash
set -euo pipefail
: "${HADOOP_USER:?}" "${HADOOP_HOME:?}" "${DATA_DIR:?}" "${LOG_DIR:?}" "${CONF_SRC:?}"

host="$(hostname -s)"
conf="${HADOOP_HOME}/etc/hadoop"

for f in core-site.xml hdfs-site.xml workers; do
  install -o "$HADOOP_USER" -g "$HADOOP_USER" -m 644 "${CONF_SRC}/${f}" "${conf}/${f}"
done
rm -rf "$CONF_SRC"

java_home=""
for pattern in /usr/lib/jvm/java-11-openjdk* /usr/lib/jvm/java-1.8.0-openjdk* /usr/lib/jvm/java-8-openjdk* /usr/lib/jvm/java-17-openjdk*; do
  if [[ -x "${pattern}/bin/java" ]]; then java_home="$pattern"; break; fi
done
if [[ -z "$java_home" ]]; then
  java_home="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
fi

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
