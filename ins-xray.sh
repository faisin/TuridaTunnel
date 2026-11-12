#!/usr/bin/env bash
set -Eeuo pipefail

# Modern Xray module. Nginx owns HTTP :80 and private TLS 127.0.0.1:9443;
# HAProxy alone owns public TCP :443 and forwards TLS to that private listener.
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
. /etc/os-release
case "${ID}:${VERSION_ID}" in
  debian:12|debian:13|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) ;;
  *) echo "Unsupported OS: ${PRETTY_NAME:-unknown}" >&2; exit 1 ;;
esac
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl ca-certificates unzip jq openssl nginx haproxy certbot

install -d -m 0755 /etc/turidatunnel /etc/xray /var/log/xray /home/vps/public_html
DOMAIN="$(head -n1 /etc/turidatunnel/domain 2>/dev/null || true)"
if [[ -z "$DOMAIN" ]]; then read -rp 'Domain DNS A/AAAA menuju VPS: ' DOMAIN; fi
[[ -n "$DOMAIN" ]] || { echo 'Domain wajib diisi.' >&2; exit 1; }
[[ "$DOMAIN" =~ ^[A-Za-z0-9.:-]+$ ]] || { echo 'Format domain/IP tidak valid.' >&2; exit 1; }
printf '%s\n' "$DOMAIN" >/etc/turidatunnel/domain
printf '%s\n' "$DOMAIN" >/etc/xray/domain

# Bootstrap Nginx HTTP vhost for ACME webroot challenge.
cat >/etc/nginx/sites-available/turidatunnel.conf <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /home/vps/public_html;
    index index.html;
    server_tokens off;
    location ^~ /.well-known/acme-challenge/ { try_files $uri =404; }
    location / { try_files $uri $uri/ =404; }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/turidatunnel.conf /etc/nginx/sites-enabled/turidatunnel.conf
nginx -t
systemctl enable --now nginx

if [[ "$DOMAIN" =~ ^[0-9.]+$ ]] || [[ "$DOMAIN" == *:* ]]; then
  echo 'Domain berupa IP: memakai self-signed certificate; TLS client tidak akan trusted secara default.'
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 365 \
    -subj "/CN=$DOMAIN" -keyout /etc/xray/xray.key -out /etc/xray/xray.crt
else
  if certbot certonly --webroot -w /home/vps/public_html --non-interactive --agree-tos \
      --register-unsafely-without-email -d "$DOMAIN"; then
    install -m 0644 "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" /etc/xray/xray.crt
    install -m 0640 "/etc/letsencrypt/live/$DOMAIN/privkey.pem" /etc/xray/xray.key
  else
    echo 'ACME gagal; membuat sertifikat self-signed sementara.'
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 30 \
      -subj "/CN=$DOMAIN" -keyout /etc/xray/xray.key -out /etc/xray/xray.crt
  fi
fi
chown root:www-data /etc/xray/xray.key
chmod 0640 /etc/xray/xray.key
chmod 0644 /etc/xray/xray.crt
# Certbot deploy hook refreshes the Nginx backend certificate after automatic renewal.
install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
cat >/etc/letsencrypt/renewal-hooks/deploy/turidatunnel.sh <<'HOOK'
#!/usr/bin/env bash
set -Eeuo pipefail
DOMAIN="$(head -n1 /etc/turidatunnel/domain)"
if [[ -s "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" && -s "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" ]]; then
  install -m 0644 "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" /etc/xray/xray.crt
  install -m 0640 "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" /etc/xray/xray.key
  chown root:www-data /etc/xray/xray.key
  systemctl reload nginx
fi
HOOK
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/turidatunnel.sh

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) XRAY_ARCH=64 ;;
  arm64) XRAY_ARCH=arm64-v8a ;;
  armhf) XRAY_ARCH=arm32-v7a ;;
  *) echo "Unsupported Xray architecture: $ARCH" >&2; exit 1 ;;
esac
VERSION="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name // empty' | sed 's/^v//')"
[[ -n "$VERSION" ]] || { echo 'Gagal mengambil versi Xray dari GitHub API.' >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fL --retry 3 "https://github.com/XTLS/Xray-core/releases/download/v${VERSION}/Xray-linux-${XRAY_ARCH}.zip" -o "$TMP/xray.zip"
unzip -q "$TMP/xray.zip" -d "$TMP/unpacked"
install -m 0755 "$TMP/unpacked/xray" /usr/local/bin/xray

# Allocate unique loopback ports and persist them for the account/menu modules.
port(){ while :; do p="$(shuf -i 20000-45000 -n1)"; ss -H -lnt "sport = :$p" | grep -q . || { echo "$p"; return; }; done; }
VLESS_WS=$(port); VMESS_WS=$(port); TROJAN_WS=$(port); SS_WS=$(port)
VLESS_GRPC=$(port); VMESS_GRPC=$(port); TROJAN_GRPC=$(port); SS_GRPC=$(port)
VLESS_HU=$(port); VMESS_HU=$(port); TROJAN_HU=$(port); SS_HU=$(port)
cat >/etc/turidatunnel/xray.env <<EOF2
DOMAIN='$DOMAIN'
VLESS_WS='$VLESS_WS'
VMESS_WS='$VMESS_WS'
TROJAN_WS='$TROJAN_WS'
SS_WS='$SS_WS'
VLESS_GRPC='$VLESS_GRPC'
VMESS_GRPC='$VMESS_GRPC'
TROJAN_GRPC='$TROJAN_GRPC'
SS_GRPC='$SS_GRPC'
VLESS_HU='$VLESS_HU'
VMESS_HU='$VMESS_HU'
TROJAN_HU='$TROJAN_HU'
SS_HU='$SS_HU'
EOF2
chmod 0600 /etc/turidatunnel/xray.env

jq -n \
  --argjson vws "$VLESS_WS" --argjson mws "$VMESS_WS" --argjson tws "$TROJAN_WS" --argjson sws "$SS_WS" \
  --argjson vgrpc "$VLESS_GRPC" --argjson mgrpc "$VMESS_GRPC" --argjson tgrpc "$TROJAN_GRPC" --argjson sgrpc "$SS_GRPC" --argjson vhu "$VLESS_HU" --argjson mhu "$VMESS_HU" --argjson thu "$TROJAN_HU" --argjson shu "$SS_HU" '
{
  log:{access:"/var/log/xray/access.log",error:"/var/log/xray/error.log",loglevel:"info"},
  api:{tag:"api",services:["StatsService"]},
  stats:{},
  policy:{levels:{"0":{"statsUserUplink":true,"statsUserDownlink":true}}},
  inbounds:[
    {tag:"api-in",listen:"127.0.0.1",port:10085,protocol:"dokodemo-door",settings:{address:"127.0.0.1"}},
    {tag:"vless-ws",listen:"127.0.0.1",port:$vws,protocol:"vless",settings:{clients:[],decryption:"none"},streamSettings:{network:"ws",wsSettings:{path:"/vless"}}},
    {tag:"vmess-ws",listen:"127.0.0.1",port:$mws,protocol:"vmess",settings:{clients:[],disableInsecureEncryption:true},streamSettings:{network:"ws",wsSettings:{path:"/vmess"}}},
    {tag:"trojan-ws",listen:"127.0.0.1",port:$tws,protocol:"trojan",settings:{clients:[],udp:true},streamSettings:{network:"ws",wsSettings:{path:"/trojan-ws"}}},
    {tag:"ss-ws",listen:"127.0.0.1",port:$sws,protocol:"shadowsocks",settings:{clients:[],network:"tcp,udp"},streamSettings:{network:"ws",wsSettings:{path:"/ss-ws"}}},
    {tag:"vless-grpc",listen:"127.0.0.1",port:$vgrpc,protocol:"vless",settings:{clients:[],decryption:"none"},streamSettings:{network:"grpc",grpcSettings:{serviceName:"vless-grpc"}}},
    {tag:"vmess-grpc",listen:"127.0.0.1",port:$mgrpc,protocol:"vmess",settings:{clients:[],disableInsecureEncryption:true},streamSettings:{network:"grpc",grpcSettings:{serviceName:"vmess-grpc"}}},
    {tag:"trojan-grpc",listen:"127.0.0.1",port:$tgrpc,protocol:"trojan",settings:{clients:[],udp:true},streamSettings:{network:"grpc",grpcSettings:{serviceName:"trojan-grpc"}}},
    {tag:"ss-grpc",listen:"127.0.0.1",port:$sgrpc,protocol:"shadowsocks",settings:{clients:[],network:"tcp,udp"},streamSettings:{network:"grpc",grpcSettings:{serviceName:"ss-grpc"}}},
    {tag:"vless-hu",listen:"127.0.0.1",port:$vhu,protocol:"vless",settings:{clients:[],decryption:"none"},streamSettings:{network:"httpupgrade",httpupgradeSettings:{path:"/vless-hu",host:""}}},
    {tag:"vmess-hu",listen:"127.0.0.1",port:$mhu,protocol:"vmess",settings:{clients:[],disableInsecureEncryption:true},streamSettings:{network:"httpupgrade",httpupgradeSettings:{path:"/vmess-hu",host:""}}},
    {tag:"trojan-hu",listen:"127.0.0.1",port:$thu,protocol:"trojan",settings:{clients:[],udp:true},streamSettings:{network:"httpupgrade",httpupgradeSettings:{path:"/trojan-hu",host:""}}},
    {tag:"ss-hu",listen:"127.0.0.1",port:$shu,protocol:"shadowsocks",settings:{clients:[],network:"tcp,udp"},streamSettings:{network:"httpupgrade",httpupgradeSettings:{path:"/ss-hu",host:""}}}
  ],
  outbounds:[{protocol:"freedom",tag:"direct"},{protocol:"blackhole",tag:"blocked"},{protocol:"freedom",tag:"api"}],
  routing:{rules:[{type:"field",inboundTag:["api-in"],outboundTag:"api"}]}
}' > /etc/xray/config.json
chown root:www-data /etc/xray/config.json
chmod 0640 /etc/xray/config.json

rm -f /etc/nginx/sites-enabled/turidatunnel-bootstrap.conf /etc/nginx/sites-available/turidatunnel-bootstrap.conf
NGINX_VERSION="$(nginx -v 2>&1 | sed -E 's#.*nginx/([0-9.]+).*#\1#')"
if dpkg --compare-versions "$NGINX_VERSION" ge 1.25.1; then
  TLS_LISTEN='listen 127.0.0.1:9443 ssl;'
  HTTP2_DIRECTIVE='http2 on;'
else
  TLS_LISTEN='listen 127.0.0.1:9443 ssl http2;'
  HTTP2_DIRECTIVE=''
fi
cat >/etc/nginx/sites-available/turidatunnel.conf <<EOF3
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    $TLS_LISTEN
    $HTTP2_DIRECTIVE
    server_name _;
    root /home/vps/public_html;
    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    server_tokens off;
    location ^~ /.well-known/acme-challenge/ { try_files \$uri =404; }
    location = /ssh { proxy_pass http://127.0.0.1:2082; include /etc/nginx/snippets/turidatunnel-ws.conf; }
    location = /vless { proxy_pass http://127.0.0.1:${VLESS_WS}; include /etc/nginx/snippets/turidatunnel-ws.conf; }
    location = /vmess { proxy_pass http://127.0.0.1:${VMESS_WS}; include /etc/nginx/snippets/turidatunnel-ws.conf; }
    location = /trojan-ws { proxy_pass http://127.0.0.1:${TROJAN_WS}; include /etc/nginx/snippets/turidatunnel-ws.conf; }
    location = /ss-ws { proxy_pass http://127.0.0.1:${SS_WS}; include /etc/nginx/snippets/turidatunnel-ws.conf; }
    location = /vless-hu { proxy_pass http://127.0.0.1:${VLESS_HU}; include /etc/nginx/snippets/turidatunnel-ws.conf; }
    location = /vmess-hu { proxy_pass http://127.0.0.1:${VMESS_HU}; include /etc/nginx/snippets/turidatunnel-ws.conf; }
    location = /trojan-hu { proxy_pass http://127.0.0.1:${TROJAN_HU}; include /etc/nginx/snippets/turidatunnel-ws.conf; }
    location = /ss-hu { proxy_pass http://127.0.0.1:${SS_HU}; include /etc/nginx/snippets/turidatunnel-ws.conf; }
    location ^~ /vless-grpc { grpc_pass grpc://127.0.0.1:${VLESS_GRPC}; }
    location ^~ /vmess-grpc { grpc_pass grpc://127.0.0.1:${VMESS_GRPC}; }
    location ^~ /trojan-grpc { grpc_pass grpc://127.0.0.1:${TROJAN_GRPC}; }
    location ^~ /ss-grpc { grpc_pass grpc://127.0.0.1:${SS_GRPC}; }
    location / { try_files \$uri \$uri/ =404; }
}
EOF3
rm -f /etc/nginx/conf.d/turidatunnel-xray.conf
install -d -m 0755 /etc/nginx/snippets
cat >/etc/nginx/snippets/turidatunnel-ws.conf <<'NGINX'
proxy_redirect off;
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
NGINX

cat >/etc/systemd/system/xray.service <<'UNIT'
[Unit]
Description=TuridaTunnel Xray Core
After=network-online.target
Wants=network-online.target

[Service]
User=www-data
Group=www-data
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1000000
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT

cat >/etc/haproxy/haproxy.cfg <<'HAPROXY'
global
    log /dev/log local0
    daemon
    user haproxy
    group haproxy
    maxconn 20000

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client 1h
    timeout server 1h

frontend turidatunnel_tls_in
    bind :443
    default_backend turidatunnel_tls_backend

backend turidatunnel_tls_backend
    server nginx_tls 127.0.0.1:9443 check
HAPROXY

chown -R www-data:www-data /var/log/xray
nginx -t
haproxy -c -f /etc/haproxy/haproxy.cfg
/usr/local/bin/xray run -test -config /etc/xray/config.json
systemctl daemon-reload
systemctl enable --now xray nginx haproxy
systemctl restart nginx xray haproxy
printf '\nXray ready. HTTP :80 -> Nginx; TLS :443 -> HAProxy -> Nginx 127.0.0.1:9443.\n'
printf 'Domain: %s\n' "$DOMAIN"
printf 'Account manager: /opt/turidatunnel/modules/account-manager.sh\n'
