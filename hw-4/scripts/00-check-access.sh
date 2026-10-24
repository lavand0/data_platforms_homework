#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

log "Проверка доступа к узлам"
[[ -r "$SSH_KEY" ]] || die "Нет ssh-ключа $SSH_KEY"
for h in $ALL_HOSTS; do
  run_on "$h" true || die "Нет доступа к $h"
done
