#!/usr/bin/env bash
set -euo pipefail
: "${JAVA_VERSION:?}" "${HADOOP_USER:?}" "${DATA_DIR:?}" "${LOG_DIR:?}" "${HOSTS_ENTRIES:?}" "${ROLE:?}"

host="$(hostname -s)"
HOSTS_ENTRIES="$(tr ',' '\n' <<<"$HOSTS_ENTRIES")"

names="$(awk '{print $2}' <<<"$HOSTS_ENTRIES")"
for n in $names; do
  sed -i -E "/^127\./ s/[[:space:]]${n}([[:space:]]|$)/ /g" /etc/hosts
done
sed -i -E '/^127\.0\.1\.1[[:space:]]*$/d' /etc/hosts
sed -i '/# BEGIN hadoop-cluster/,/# END hadoop-cluster/d' /etc/hosts
{
  echo "# BEGIN hadoop-cluster"
  printf '%s\n' "$HOSTS_ENTRIES"
  echo "# END hadoop-cluster"
} >> /etc/hosts

java_dir() {
  ls -d /usr/lib/jvm/java-"${JAVA_VERSION}"-openjdk* /usr/lib/jvm/java-1."${JAVA_VERSION}".0-openjdk* 2>/dev/null | head -1 || true
}
if [[ -z "$(java_dir)" ]]; then
  if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1
    apt-get update -qq
    apt-get install -y -qq "openjdk-${JAVA_VERSION}-jdk-headless" >/dev/null
  elif command -v dnf >/dev/null; then
    pkg="java-${JAVA_VERSION}-openjdk-devel"; [[ "$JAVA_VERSION" == 8 ]] && pkg="java-1.8.0-openjdk-devel"
    dnf install -y -q "$pkg"
  fi
  [[ -n "$(java_dir)" ]] || { echo "ERROR: не удалось установить Java ${JAVA_VERSION}" >&2; exit 1; }
fi

if ! command -v curl >/dev/null; then
  if command -v apt-get >/dev/null; then apt-get install -y -qq curl >/dev/null; else dnf install -y -q curl; fi
fi

id "$HADOOP_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash -U "$HADOOP_USER"

if [[ "$ROLE" == "cluster" ]]; then
  mkdir -p "$DATA_DIR"/{nn,snn,dn,tmp,pids,yarn/local,yarn/logs} "$LOG_DIR"
  chown -R "$HADOOP_USER:$HADOOP_USER" "$DATA_DIR" "$LOG_DIR"
  chmod 700 "$DATA_DIR/dn"
fi

echo "[$host] узел подготовлен"
