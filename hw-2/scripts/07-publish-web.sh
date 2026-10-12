#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

log "Публикация веб-интерфейсов через nginx на ${EDGE_HOST}"

run_on "$EDGE_HOST" "command -v nginx >/dev/null || { export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq nginx >/dev/null; }"

if [[ ! -s "$WEB_CREDENTIALS_FILE" ]]; then
  (umask 077; printf '%s:%s\n' "$WEB_USER" "$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 16)" > "$WEB_CREDENTIALS_FILE")
fi
IFS=: read -r web_user web_pass < "$WEB_CREDENTIALS_FILE"

build="${REPO_DIR}/build/nginx"
rm -rf "$build"; mkdir -p "$build"
printf '%s:%s\n' "$web_user" "$(openssl passwd -apr1 "$web_pass")" > "${build}/hadoop.htpasswd"

ip_of() { awk -v h="$1" '$2 == h {print $1}' <<<"$HOSTS_ENTRIES"; }

while read -r name port target; do
  echo "sub_filter '${target}' '\$host:${port}';"
  echo "sub_filter '$(ip_of "${target%:*}"):${target#*:}' '\$host:${port}';"
done <<<"$WEB_UIS" > "${build}/hadoop-ui-links.conf"

while read -r name port target; do
  cat <<CONF
server {
    listen ${port};
    server_name _;
    auth_basic "Hadoop ${name}";
    auth_basic_user_file /etc/nginx/hadoop.htpasswd;
    location / {
        proxy_pass http://${target};
        proxy_set_header Host \$http_host;
        proxy_set_header Accept-Encoding "";
        proxy_redirect http://${target}/ /;
        sub_filter_once off;
        sub_filter_types text/css text/plain text/javascript application/javascript application/json application/xml;
        include /etc/nginx/hadoop-ui-links.conf;
    }
}
CONF
done <<<"$WEB_UIS" > "${build}/hadoop-ui.conf"

tmp="/tmp/hadoop-nginx-$$"
run_on "$EDGE_HOST" "rm -rf $tmp && mkdir -p $tmp && chmod 777 $tmp"
for f in hadoop.htpasswd hadoop-ui-links.conf hadoop-ui.conf; do
  copy_to "$EDGE_HOST" "${build}/${f}" "${tmp}/${f}"
done
run_on "$EDGE_HOST" "
  install -o root -g www-data -m 640 $tmp/hadoop.htpasswd /etc/nginx/hadoop.htpasswd
  install -m 644 $tmp/hadoop-ui-links.conf /etc/nginx/hadoop-ui-links.conf
  install -m 644 $tmp/hadoop-ui.conf /etc/nginx/conf.d/hadoop-ui.conf
  rm -rf $tmp
  nginx -t -q && systemctl enable nginx >/dev/null 2>&1 && systemctl restart nginx
" || die "nginx не принял конфигурацию"

ports="$(awk '{print $2}' <<<"$WEB_UIS" | tr '\n' ' ')"
run_on "$EDGE_HOST" "if ufw status 2>/dev/null | grep -q 'Status: active'; then for p in $ports; do ufw allow \$p/tcp >/dev/null; done; fi"

log "Веб-интерфейсы (логин ${web_user}, пароль ${web_pass}, сохранён в ${WEB_CREDENTIALS_FILE}):"
while read -r name port target; do
  printf '    %-18s http://%s:%s\n' "$name" "$EDGE_PUBLIC_IP" "$port"
done <<<"$WEB_UIS"
