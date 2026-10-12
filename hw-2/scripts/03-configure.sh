#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

log "Конфигурация Hadoop"

build="${REPO_DIR}/build/conf"
rm -rf "$build"; mkdir -p "$build"

render() {
  local text var
  text="$(<"$1")"
  for var in $(grep -oE '__[A-Z0-9_]+__' "$1" | sort -u | sed -E 's/^__(.*)__$/\1/'); do
    [[ -n "${!var:-}" ]] || die "Не задана переменная $var для $(basename "$1")"
    text="${text//__${var}__/${!var}}"
  done
  printf '%s\n' "$text"
}

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
