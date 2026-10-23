#!/usr/bin/env bash
set -euo pipefail
: "${HADOOP_USER:?}" "${HADOOP_HOME:?}" "${DATA_DIR:?}" "${HIVE_HOME:?}" "${HIVE_LOG_DIR:?}" "${TARBALL:?}" "${CONF_SRC:?}"
: "${METASTORE_DB:?}" "${METASTORE_DB_USER:?}" "${METASTORE_DB_PASSWORD:?}"

host="$(hostname -s)"
cd /

if ! command -v psql >/dev/null || [[ ! -f /usr/share/java/postgresql.jar ]]; then
  command -v apt-get >/dev/null || { echo "ERROR: установите PostgreSQL и JDBC-драйвер вручную" >&2; exit 1; }
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1
  apt-get update -qq
  apt-get install -y -qq postgresql libpostgresql-jdbc-java >/dev/null
fi
systemctl enable --now postgresql >/dev/null 2>&1 || true
for _ in $(seq 1 30); do
  sudo -u postgres psql -qAtc 'SELECT 1' >/dev/null 2>&1 && break
  sleep 1
done

psql_su() { sudo -u postgres psql -v ON_ERROR_STOP=1 -qAt "$@"; }
[[ -n "$(psql_su -c "SELECT 1 FROM pg_roles WHERE rolname = '${METASTORE_DB_USER}'")" ]] \
  || psql_su -c "CREATE ROLE ${METASTORE_DB_USER} LOGIN"
psql_su -c "ALTER ROLE ${METASTORE_DB_USER} PASSWORD '${METASTORE_DB_PASSWORD}'"
[[ -n "$(psql_su -c "SELECT 1 FROM pg_database WHERE datname = '${METASTORE_DB}'")" ]] \
  || sudo -u postgres createdb -O "$METASTORE_DB_USER" "$METASTORE_DB"

if [[ ! -x "${HIVE_HOME}/bin/hive" ]]; then
  [[ -f "$TARBALL" ]] || { echo "ERROR: нет архива $TARBALL" >&2; exit 1; }
  tar -xzf "$TARBALL" -C "$(dirname "$HIVE_HOME")"
fi

hadoop_guava="$(ls "${HADOOP_HOME}"/share/hadoop/common/lib/guava-*.jar 2>/dev/null | head -1 || true)"
if [[ -n "$hadoop_guava" ]]; then
  for jar in "${HIVE_HOME}"/lib/guava-*.jar; do
    [[ "$(basename "$jar")" == "$(basename "$hadoop_guava")" ]] || rm -f "$jar"
  done
  cp -n "$hadoop_guava" "${HADOOP_HOME}"/share/hadoop/common/lib/failureaccess-*.jar "${HIVE_HOME}/lib/" 2>/dev/null || true
fi
ln -sfn /usr/share/java/postgresql.jar "${HIVE_HOME}/lib/postgresql-jdbc.jar"

mkdir -p "${HIVE_HOME}/auxlib"
collections="$(ls "${HIVE_HOME}"/lib/commons-collections-3*.jar 2>/dev/null | head -1 || true)"
[[ -n "$collections" ]] && cp -f "$collections" "${HIVE_HOME}/auxlib/"

install -o "$HADOOP_USER" -g "$HADOOP_USER" -m 640 "${CONF_SRC}/hive-site.xml" "${HIVE_HOME}/conf/hive-site.xml"
rm -rf "$CONF_SRC"
cat > "${HIVE_HOME}/conf/hive-env.sh" <<ENV
export HADOOP_HOME=${HADOOP_HOME}
export HIVE_CONF_DIR=${HIVE_HOME}/conf
export HADOOP_OPTS="\$HADOOP_OPTS -Dhive.log.dir=${HIVE_LOG_DIR} -Dhive.log.file=hive-\${SERVICE:-cli}.log"
case "\$SERVICE" in
  metastore)   export HADOOP_HEAPSIZE_MAX=512m ;;
  hiveserver2) export HADOOP_HEAPSIZE_MAX=1g ;;
  *)           export HADOOP_HEAPSIZE_MAX=256m ;;
esac
ENV

mkdir -p "$HIVE_LOG_DIR" "${DATA_DIR}/pids"
chown -R "$HADOOP_USER:$HADOOP_USER" "$HIVE_HOME" "$HIVE_LOG_DIR" "${DATA_DIR}/pids"
chown -h "$HADOOP_USER:$HADOOP_USER" "${HIVE_HOME}/lib/postgresql-jdbc.jar"

echo "[$host] Hive установлен, база метастора ${METASTORE_DB} в PostgreSQL готова"
