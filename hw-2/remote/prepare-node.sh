#!/usr/bin/env bash
set -euo pipefail
: "${HADOOP_USER:?}" "${DATA_DIR:?}" "${LOG_DIR:?}" "${HOSTS_ENTRIES:?}" "${ROLE:?}"

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

java_ok() {
  ls -d /usr/lib/jvm/java-11-openjdk* >/dev/null 2>&1 || ls -d /usr/lib/jvm/java-8-openjdk* >/dev/null 2>&1
}
if ! java_ok; then
  if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    if apt-cache show openjdk-11-jdk-headless >/dev/null 2>&1; then
      apt-get install -y -qq openjdk-11-jdk-headless >/dev/null
    else
      apt-get install -y -qq openjdk-17-jdk-headless >/dev/null
    fi
  elif command -v dnf >/dev/null; then
    dnf install -y -q java-11-openjdk-devel || dnf install -y -q java-17-openjdk-devel
  else
    echo "ERROR: установите Java 11 вручную" >&2; exit 1
  fi
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
