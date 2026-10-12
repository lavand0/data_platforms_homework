#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

log "Конфигурация Hadoop"

build="${REPO_DIR}/build/conf"
rm -rf "$build"; mkdir -p "$build"

render() {
  sed -e "s|__NN_HOST__|${NN_HOST}|g" \
      -e "s|__SNN_HOST__|${SNN_HOST}|g" \
      -e "s|__NN_RPC_PORT__|${NN_RPC_PORT}|g" \
      -e "s|__NN_HTTP_PORT__|${NN_HTTP_PORT}|g" \
      -e "s|__SNN_HTTP_PORT__|${SNN_HTTP_PORT}|g" \
      -e "s|__DATA_DIR__|${DATA_DIR}|g" \
      -e "s|__HADOOP_USER__|${HADOOP_USER}|g" \
      -e "s|__REPLICATION__|${REPLICATION}|g" \
      "$1"
}
render "${REPO_DIR}/config/templates/core-site.xml" > "${build}/core-site.xml"
render "${REPO_DIR}/config/templates/hdfs-site.xml" > "${build}/hdfs-site.xml"
tr ' ' '\n' <<<"$DN_HOSTS" | sed '/^$/d' > "${build}/workers"

! grep -q '__[A-Z_]*__' "${build}"/*.xml || die "В конфигах остались плейсхолдеры"

for h in $ALL_HOSTS; do
  dst="/tmp/hadoop-conf-$$"
  run_on "$h" "rm -rf $dst && mkdir -p $dst && chmod 777 $dst"
  for f in core-site.xml hdfs-site.xml workers; do
    copy_to "$h" "${build}/${f}" "${dst}/${f}"
  done
  run_script_on "$h" "${REPO_DIR}/remote/configure-node.sh" "${COMMON_ENV[@]}" "CONF_SRC=${dst}"
done
