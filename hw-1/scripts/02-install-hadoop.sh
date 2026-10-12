#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

log "Установка Hadoop ${HADOOP_VERSION}"

dl_dir="${REPO_DIR}/downloads"
name="hadoop-${HADOOP_VERSION}.tar.gz"
tarball="${dl_dir}/${name}"
mkdir -p "$dl_dir"

if [[ ! -s "$tarball" || ! -s "${tarball}.sha512" ]]; then
  for mirror in $HADOOP_MIRRORS; do
    url="${mirror}/hadoop-${HADOOP_VERSION}/${name}"
    curl -fL --retry 3 --progress-bar -o "${tarball}.part" "$url" \
      && curl -fsSL -o "${tarball}.sha512" "${url}.sha512" \
      && mv "${tarball}.part" "$tarball" && break
  done
  [[ -s "$tarball" ]] || die "Не удалось скачать ${name}, положите его и ${name}.sha512 в ${dl_dir}"
fi

expected="$(grep -oiE '[0-9a-f]{128}' "${tarball}.sha512" | head -1 | tr 'A-F' 'a-f')"
actual="$(sha512sum "$tarball" | awk '{print $1}')"
[[ -n "$expected" && "$expected" == "$actual" ]] || die "SHA-512 не совпадает, удалите ${tarball}"

for h in $ALL_HOSTS; do
  remote_tar="none"
  if ! run_on "$h" "test -x /opt/hadoop-${HADOOP_VERSION}/bin/hdfs"; then
    remote_tar="/tmp/${name}"
    copy_to "$h" "$tarball" "$remote_tar"
  fi
  run_script_on "$h" "${REPO_DIR}/remote/install-hadoop.sh" "${COMMON_ENV[@]}" "TARBALL=${remote_tar}"
done
