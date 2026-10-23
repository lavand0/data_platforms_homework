#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

log "Установка Hive ${HIVE_VERSION} на ${HIVE_HOST}"

dl_dir="${REPO_DIR}/downloads"
name="apache-hive-${HIVE_VERSION}-bin.tar.gz"
tarball="${dl_dir}/${name}"
mkdir -p "$dl_dir"

if [[ ! -s "$tarball" || ! -s "${tarball}.sha256" ]]; then
  for mirror in $HIVE_MIRRORS; do
    url="${mirror}/hive-${HIVE_VERSION}/${name}"
    curl -fL --retry 3 --progress-bar -o "${tarball}.part" "$url" \
      && curl -fsSL -o "${tarball}.sha256" "${url}.sha256" \
      && mv "${tarball}.part" "$tarball" && break
  done
  [[ -s "$tarball" ]] || die "Не удалось скачать ${name}, положите его и ${name}.sha256 в ${dl_dir}"
fi
expected="$(grep -oiE '[0-9a-f]{64}' "${tarball}.sha256" | head -1 | tr 'A-F' 'a-f')"
actual="$(sha256sum "$tarball" | awk '{print $1}')"
[[ -n "$expected" && "$expected" == "$actual" ]] || die "SHA-256 не совпадает, удалите ${tarball}"

if [[ ! -s "$METASTORE_PASSWORD_FILE" ]]; then
  (umask 077; openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20 > "$METASTORE_PASSWORD_FILE")
fi
METASTORE_DB_PASSWORD="$(<"$METASTORE_PASSWORD_FILE")"

build="${REPO_DIR}/build/hive"
rm -rf "$build"; mkdir -p "$build"
(umask 077; render "${REPO_DIR}/config/hive/hive-site.xml" > "${build}/hive-site.xml")

tmp="/tmp/hive-install-$$"
run_on "$HIVE_HOST" "rm -rf $tmp && mkdir -p $tmp && chmod 777 $tmp"
copy_to "$HIVE_HOST" "${build}/hive-site.xml" "${tmp}/hive-site.xml"
remote_tar="none"
if ! run_on "$HIVE_HOST" "test -x ${HIVE_HOME}/bin/hive"; then
  remote_tar="${tmp}/${name}"
  copy_to "$HIVE_HOST" "$tarball" "$remote_tar"
fi
run_script_on "$HIVE_HOST" "${REPO_DIR}/remote/install-hive.sh" "${COMMON_ENV[@]}" \
  "HIVE_HOME=${HIVE_HOME}" "HIVE_LOG_DIR=${HIVE_LOG_DIR}" "TARBALL=${remote_tar}" "CONF_SRC=${tmp}" \
  "METASTORE_DB=${METASTORE_DB}" "METASTORE_DB_USER=${METASTORE_DB_USER}" "METASTORE_DB_PASSWORD=${METASTORE_DB_PASSWORD}"

hdfs_as_hadoop "$NN_HOST" "dfs -mkdir -p ${HIVE_WAREHOUSE} /tmp/hive"
hdfs_as_hadoop "$NN_HOST" "dfs -chmod 1777 /tmp/hive"

schematool="sudo -u ${HADOOP_USER} -H ${HIVE_HOME}/bin/schematool -dbType postgres"
if run_on "$HIVE_HOST" "cd /tmp && $schematool -info >/dev/null 2>&1"; then
  log "Схема метастора уже создана"
else
  run_on "$HIVE_HOST" "cd /tmp && $schematool -initSchema > ${HIVE_LOG_DIR}/schematool.log 2>&1" \
    || { run_on "$HIVE_HOST" "tail -n 20 ${HIVE_LOG_DIR}/schematool.log"; die "schematool не создал схему метастора"; }
  log "Схема метастора создана в PostgreSQL"
fi
