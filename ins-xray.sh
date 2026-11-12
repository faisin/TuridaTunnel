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
apt-get install -y curl ca-certificates unzip jq openssl nginx haproxy stunnel4 socat

install -d -m 0755 /etc/turidatunnel /etc/xray /var/log/xray /var/www/turidatunnel-acme/.well-known/acme-challenge
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
    server_name DOMAIN_PLACEHOLDER _;
    root /var/www/turidatunnel-acme;
    index index.html;
    server_tokens off;
    location ^~ /.well-known/acme-challenge/ {
        alias /var/www/turidatunnel-acme/.well-known/acme-challenge/;
        default_type text/plain;
        allow all;
        autoindex off;
    }
    location / { try_files $uri $uri/ =404; }
}
NGINX
sed -i "s/DOMAIN_PLACEHOLDER/${DOMAIN}/" /etc/nginx/sites-available/turidatunnel.conf
rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/turidatunnel.conf /etc/nginx/sites-enabled/turidatunnel.conf
# Apply the newly written ACME vhost before the ACME manager probes it.
# `enable --now` does not reload an already-running Nginx process.
nginx -t
systemctl enable nginx
if systemctl is-active --quiet nginx; then
  systemctl reload nginx
else
  systemctl start nginx
fi

if [[ "$DOMAIN" =~ ^[0-9.]+$ ]] || [[ "$DOMAIN" == *:* ]]; then
  echo 'ACME memerlukan nama domain DNS; domain berupa IP tidak dapat diterbitkan sertifikat publik.'
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 30 \
    -subj "/CN=$DOMAIN" -keyout /etc/xray/xray.key -out /etc/xray/xray.crt
  cat /etc/xray/xray.crt /etc/xray/xray.key >/etc/stunnel/turidatunnel.pem
else
  # Default issuance uses Nginx webroot. If DNS for ssh.<domain> is not ready,
  # user can rerun: turidatunnel-acme standalone or webroot after fixing DNS.
  bash "$(dirname "$(readlink -f "$0")")/modules/acme-manager.sh" webroot || {
    echo 'Penerbitan ACME webroot gagal. Periksa DNS A/AAAA untuk domain utama, lalu jalankan turidatunnel-acme webroot.' >&2
    exit 1
  }
fi
chown root:www-data /etc/xray/xray.key
chmod 0640 /etc/xray/xray.key
chmod 0644 /etc/xray/xray.crt

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
    server_name ${DOMAIN};
    root /var/www/turidatunnel-acme;
    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    server_tokens off;
    location ^~ /.well-known/acme-challenge/ {
        alias /var/www/turidatunnel-acme/.well-known/acme-challenge/;
        default_type text/plain;
        allow all;
        autoindex off;
    }
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

SSH_TLS_PORT=8443
STUNNEL_BACKEND_PORT=9444

# Debian/Ubuntu menjalankan stunnel dengan user unprivileged stunnel4.
# Simpan PID di direktori runtime yang memang dapat ditulis oleh user tersebut.
getent passwd stunnel4 >/dev/null || { echo "User stunnel4 tidak ditemukan setelah pemasangan paket." >&2; exit 1; }
getent group stunnel4 >/dev/null || { echo "Group stunnel4 tidak ditemukan setelah pemasangan paket." >&2; exit 1; }
cat >/etc/tmpfiles.d/turidatunnel-stunnel.conf <<'TMPFILES'
d /run/stunnel4 0750 stunnel4 stunnel4 -
TMPFILES
systemd-tmpfiles --create /etc/tmpfiles.d/turidatunnel-stunnel.conf
install -d -o stunnel4 -g stunnel4 -m 0750 /run/stunnel4
cat >/etc/stunnel/turidatunnel.conf <<EOFST
foreground = no
pid = /run/stunnel4/turidatunnel.pid
setuid = stunnel4
setgid = stunnel4
[turidatunnel-dropbear]
accept = 127.0.0.1:${STUNNEL_BACKEND_PORT}
connect = 127.0.0.1:109
cert = /etc/stunnel/turidatunnel.pem
TIMEOUTclose = 0
EOFST
chmod 0640 /etc/stunnel/turidatunnel.conf
# Ubuntu/Debian stunnel4 package uses /etc/default/stunnel4 to enable custom config.
if [[ -f /etc/default/stunnel4 ]]; then
  sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4
  if grep -q '^FILES=' /etc/default/stunnel4; then
    sed -i 's#^FILES=.*#FILES="/etc/stunnel/turidatunnel.conf"#' /etc/default/stunnel4
  else
    echo 'FILES="/etc/stunnel/turidatunnel.conf"' >>/etc/default/stunnel4
  fi
fi
cat >/etc/haproxy/haproxy.cfg <<EOFHAP
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

frontend turidatunnel_xray_tls_in
    bind :443
    mode tcp
    default_backend turidatunnel_xray_tls

frontend turidatunnel_ssh_tls_in
    bind :8443
    mode tcp
    default_backend turidatunnel_ssh_tls

backend turidatunnel_ssh_tls
    mode tcp
    server stunnel_ssh 127.0.0.1:${STUNNEL_BACKEND_PORT} check

backend turidatunnel_xray_tls
    mode tcp
    server nginx_tls 127.0.0.1:9443 check
EOFHAP

chown -R www-data:www-data /var/log/xray
nginx -t
haproxy -c -f /etc/haproxy/haproxy.cfg
/usr/local/bin/xray run -test -config /etc/xray/config.json
systemctl daemon-reload
systemctl enable --now xray nginx haproxy
systemctl enable stunnel4
systemctl restart nginx xray
systemctl restart stunnel4
# stunnel4 pada Debian memakai unit SysV; status "active (exited)" saja
# tidak menjamin listener berhasil dibuat, jadi validasi port backend-nya.
sleep 1
if ! ss -H -lnt "sport = :${STUNNEL_BACKEND_PORT}" | grep -q LISTEN; then
  echo "stunnel tidak membuka 127.0.0.1:${STUNNEL_BACKEND_PORT}. Log terakhir:" >&2
  journalctl -u stunnel4 -n 30 --no-pager >&2 || true
  exit 1
fi
systemctl restart haproxy
printf '\nXray ready. HTTP :80 -> Nginx; TLS :443 ${DOMAIN} -> HAProxy -> Nginx TLS 127.0.0.1:9443 -> Xray; SSH TLS ${DOMAIN}:8443 -> HAProxy -> stunnel 127.0.0.1:${STUNNEL_BACKEND_PORT} -> Dropbear :109.\n'
printf 'Domain: %s\n' "$DOMAIN"
printf 'SSH TLS: %s:8443 (gunakan DNS utama yang sama)\n' "$DOMAIN"
printf 'Account manager: /opt/turidatunnel/modules/account-manager.sh\n'
