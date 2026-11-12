#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Jalankan sebagai root.' >&2; exit 1; }
BASE=/root/.acme.sh/acme.sh
DOMAIN_FILE=/etc/turidatunnel/domain
WEBROOT=/home/vps/public_html
CERT_DIR=/etc/turidatunnel/certs
install -d -m 0755 "$CERT_DIR" "$WEBROOT/.well-known/acme-challenge"
[[ -s "$DOMAIN_FILE" ]] || { echo 'Domain belum diset.' >&2; exit 1; }
DOMAIN="$(head -n1 "$DOMAIN_FILE")"
SSH_SNI="ssh.${DOMAIN}"
EMAIL="${ACME_EMAIL:-}"

install_acme(){
  if [[ ! -x "$BASE" ]]; then
    apt-get update
    apt-get install -y curl socat cron
    if [[ -n "$EMAIL" ]]; then
      curl -fsSL https://get.acme.sh | sh -s email="$EMAIL"
    else
      curl -fsSL https://get.acme.sh | sh
    fi
  fi
  [[ -x "$BASE" ]] || { echo 'Instalasi acme.sh gagal.' >&2; exit 1; }
  "$BASE" --set-default-ca --server letsencrypt
}

install_deploy_hook(){
  cat >/usr/local/sbin/turidatunnel-deploy-cert <<'HOOK'
#!/usr/bin/env bash
set -Eeuo pipefail
D="$(head -n1 /etc/turidatunnel/domain)"
SRC="/etc/turidatunnel/certs"
install -m 0644 "$SRC/fullchain.pem" /etc/xray/xray.crt
install -m 0640 "$SRC/privkey.pem" /etc/xray/xray.key
chown root:www-data /etc/xray/xray.key
chmod 0640 /etc/xray/xray.key
cat "$SRC/fullchain.pem" "$SRC/privkey.pem" > /etc/stunnel/turidatunnel.pem
chmod 0600 /etc/stunnel/turidatunnel.pem
chown root:root /etc/stunnel/turidatunnel.pem
nginx -t && systemctl reload nginx
if systemctl is-enabled --quiet stunnel4 2>/dev/null; then systemctl restart stunnel4 || true; fi
if command -v haproxy >/dev/null 2>&1; then haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl reload haproxy || true; fi
HOOK
  chmod 0755 /usr/local/sbin/turidatunnel-deploy-cert
}

issue(){
  local mode="${1:-webroot}"
  install_acme
  case "$mode" in
    webroot)
      "$BASE" --issue --server letsencrypt -d "$DOMAIN" -d "$SSH_SNI" -w "$WEBROOT" --keylength ec-256
      ;;
    standalone)
      # HTTP-01 standalone needs public TCP/80. Stop Nginx only for issuance.
      systemctl stop nginx || true
      if ! "$BASE" --issue --server letsencrypt -d "$DOMAIN" -d "$SSH_SNI" --standalone --httpport 80 --keylength ec-256; then
        systemctl start nginx || true
        return 1
      fi
      systemctl start nginx
      ;;
    *) echo 'Metode harus webroot atau standalone.' >&2; exit 2;;
  esac
  install_deploy_hook
  "$BASE" --install-cert -d "$DOMAIN" --ecc \
    --key-file "$CERT_DIR/privkey.pem" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --reloadcmd '/usr/local/sbin/turidatunnel-deploy-cert'
  /usr/local/sbin/turidatunnel-deploy-cert
}

case "${1:-issue}" in
  install) install_acme ;;
  webroot) issue webroot ;;
  standalone) issue standalone ;;
  renew) "$BASE" --cron --home /root/.acme.sh ;;
  *) echo "Usage: $0 {install|webroot|standalone|renew}"; exit 2 ;;
esac
