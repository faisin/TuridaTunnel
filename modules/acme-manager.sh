#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Jalankan sebagai root.' >&2; exit 1; }
BASE=/root/.acme.sh/acme.sh
DOMAIN_FILE=/etc/turidatunnel/domain
WEBROOT=/var/www/turidatunnel-acme
CERT_DIR=/etc/turidatunnel/certs
install -d -o root -g www-data -m 0755 "$CERT_DIR" "$WEBROOT" "$WEBROOT/.well-known" "$WEBROOT/.well-known/acme-challenge"
chmod 0755 /var /var/www "$WEBROOT" "$WEBROOT/.well-known" "$WEBROOT/.well-known/acme-challenge"
[[ -s "$DOMAIN_FILE" ]] || { echo 'Domain belum diset.' >&2; exit 1; }
DOMAIN="$(head -n1 "$DOMAIN_FILE")"
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

acme_existing_cert_is_valid(){
  local cert_dir="/root/.acme.sh/${DOMAIN}_ecc"
  local cert="${cert_dir}/${DOMAIN}.cer"
  local key="${cert_dir}/${DOMAIN}.key"

  [[ -s "$cert" && -s "$key" ]] || return 1
  openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1 || return 1
  openssl x509 -in "$cert" -noout -checkhost "$DOMAIN" >/dev/null 2>&1 || return 1

  # Pastikan private key cocok dengan sertifikat yang akan dipasang.
  local cert_pub key_pub
  cert_pub="$(openssl x509 -in "$cert" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')" || return 1
  key_pub="$(openssl pkey -in "$key" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')" || return 1
  [[ -n "$cert_pub" && "$cert_pub" == "$key_pub" ]]
}

issue(){
  local mode="${1:-webroot}"
  local issue_ok=0
  install_acme
  # Verify that Nginx serves the exact ACME webroot before contacting the CA.
  if [[ "$mode" == webroot ]]; then
    local probe="turidatunnel-acme-probe-$$" body="/tmp/turidatunnel-acme-probe-$$.body" code
    printf 'turidatunnel-acme-ok\n' >"$WEBROOT/.well-known/acme-challenge/$probe"
    chmod 0644 "$WEBROOT/.well-known/acme-challenge/$probe"
    code="$(curl -sS --max-time 5 -o "$body" -w '%{http_code}' -H "Host: $DOMAIN" "http://127.0.0.1/.well-known/acme-challenge/$probe" || true)"
    if [[ "$code" != 200 ]] || ! grep -qx 'turidatunnel-acme-ok' "$body" 2>/dev/null; then
      echo 'Gagal menguji webroot ACME melalui Nginx.' >&2
      echo "HTTP status: ${code:-tidak ada}" >&2
      echo "File uji: $WEBROOT/.well-known/acme-challenge/$probe" >&2
      echo 'Konfigurasi Nginx aktif:' >&2
      nginx -T 2>&1 | grep -n -A12 -B3 'acme-challenge' >&2 || true
      rm -f "$WEBROOT/.well-known/acme-challenge/$probe" "$body"
      return 1
    fi
    rm -f "$WEBROOT/.well-known/acme-challenge/$probe" "$body"
  fi
  case "$mode" in
    webroot)
      if ! "$BASE" --issue --server letsencrypt -d "$DOMAIN" -w "$WEBROOT" --keylength ec-256; then
        if acme_existing_cert_is_valid; then
          echo "ACME tidak menerbitkan ulang sertifikat; sertifikat ECC yang ada masih valid untuk ${DOMAIN}. Melanjutkan pemasangan sertifikat tersebut."
        else
          echo "Penerbitan ACME gagal dan tidak ditemukan sertifikat ECC valid untuk ${DOMAIN}." >&2
          return 1
        fi
      fi
      ;;
    standalone)
      # HTTP-01 standalone needs public TCP/80. Stop Nginx only for issuance.
      systemctl stop nginx || true
      if ! "$BASE" --issue --server letsencrypt -d "$DOMAIN" --standalone --httpport 80 --keylength ec-256; then
        systemctl start nginx || true
        if acme_existing_cert_is_valid; then
          echo "ACME tidak menerbitkan ulang sertifikat; sertifikat ECC yang ada masih valid untuk ${DOMAIN}. Melanjutkan pemasangan sertifikat tersebut."
        else
          echo "Penerbitan ACME gagal dan tidak ditemukan sertifikat ECC valid untuk ${DOMAIN}." >&2
          return 1
        fi
      else
        systemctl start nginx
      fi
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
