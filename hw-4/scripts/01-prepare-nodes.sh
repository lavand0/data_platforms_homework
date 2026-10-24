#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

log "Подготовка узлов"
for h in $ALL_HOSTS; do
  role="cluster"; [[ " $CLUSTER_HOSTS " == *" $h "* ]] || role="client"
  run_script_on "$h" "${REPO_DIR}/remote/prepare-node.sh" \
    "${COMMON_ENV[@]}" "ROLE=${role}" "HOSTS_ENTRIES=${HOSTS_ENTRIES//$'\n'/,}"
done
