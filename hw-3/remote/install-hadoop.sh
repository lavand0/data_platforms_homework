#!/usr/bin/env bash
set -euo pipefail
: "${HADOOP_USER:?}" "${HADOOP_HOME:?}" "${HADOOP_VERSION:?}" "${TARBALL:?}"

host="$(hostname -s)"
target="/opt/hadoop-${HADOOP_VERSION}"

if [[ ! -x "${target}/bin/hdfs" ]]; then
  [[ -f "$TARBALL" ]] || { echo "ERROR: нет архива $TARBALL" >&2; exit 1; }
  tar -xzf "$TARBALL" -C /opt
fi
if [[ "$TARBALL" == /tmp/hadoop-*.tar.gz && -f "$TARBALL" ]]; then
  rm -f "$TARBALL"
fi

ln -sfn "$target" "$HADOOP_HOME"
chown -R "$HADOOP_USER:$HADOOP_USER" "$target"

cat > /etc/profile.d/hadoop.sh <<EOF
export HADOOP_HOME=${HADOOP_HOME}
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export PATH=\$PATH:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin
EOF

echo "[$host] Hadoop установлен"
