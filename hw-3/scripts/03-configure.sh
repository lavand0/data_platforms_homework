#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

log "Конфигурация Hadoop"

build="${REPO_DIR}/build/conf"
rm -rf "$build"; mkdir -p "$build"

files=(workers)
for t in "${REPO_DIR}"/config/templates/*.xml; do
  render "$t" > "${build}/$(basename "$t")"
  files+=("$(basename "$t")")
done
tr ' ' '\n' <<<"$DN_HOSTS" | sed '/^$/d' > "${build}/workers"

for h in $ALL_HOSTS; do
  dst="/tmp/hadoop-conf-$$"
  run_on "$h" "rm -rf $dst && mkdir -p $dst && chmod 777 $dst"
  for f in "${files[@]}"; do
    copy_to "$h" "${build}/${f}" "${dst}/${f}"
  done
  run_script_on "$h" "${REPO_DIR}/remote/configure-node.sh" "${COMMON_ENV[@]}" "CONF_SRC=${dst}"
done
