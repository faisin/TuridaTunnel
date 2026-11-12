#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/faisin/turidatunnel.git"
BRANCH="main"
INSTALL_DIR="/opt/turidatunnel"
LOG_FILE="/var/log/turidatunnel-install.log"

say(){ printf '\033[1;36m[TuridaTunnel]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die 'Jalankan sebagai root.'
[[ -r /etc/os-release ]] || die 'Tidak dapat membaca /etc/os-release.'
. /etc/os-release
case "${ID}:${VERSION_ID}" in
  debian:12|debian:13|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) ;;
  *) die "OS tidak didukung: ${PRETTY_NAME:-unknown}. Target Debian 12/13 dan Ubuntu 22.04/24.04/26.04." ;;
esac
command -v apt-get >/dev/null 2>&1 || die 'APT tidak tersedia.'
exec > >(tee -a "$LOG_FILE") 2>&1
export DEBIAN_FRONTEND=noninteractive

say "OS: ${PRETTY_NAME}"
say 'Memasang dependensi dasar.'
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl wget git unzip jq openssl socat cron iproute2 net-tools lsof procps psmisc dnsutils python3 nginx haproxy certbot

say 'Mengambil repositori publik faisin/turidatunnel.'
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" remote set-url origin "$REPO_URL"
  git -C "$INSTALL_DIR" fetch --depth=1 origin "$BRANCH"
  git -C "$INSTALL_DIR" reset --hard FETCH_HEAD
else
  tmp="${INSTALL_DIR}.new"
  rm -rf "$tmp"
  git clone --depth=1 --single-branch --branch "$BRANCH" "$REPO_URL" "$tmp"
  rm -rf "$INSTALL_DIR"
  mv "$tmp" "$INSTALL_DIR"
fi

install -d -m 0755 /etc/turidatunnel /etc/xray /home/vps/public_html /var/log/xray /usr/local/bin
# Install stable command entrypoints while keeping the Git checkout as the source of truth.
for script in "$INSTALL_DIR"/*.sh; do
  [[ -f "$script" ]] || continue
  name="$(basename "$script" .sh)"
  ln -sfn "$script" "/usr/local/bin/$name"
done
for script in "$INSTALL_DIR"/modules/*.sh; do
  [[ -f "$script" ]] || continue
  name="$(basename "$script" .sh)"
  ln -sfn "$script" "/usr/local/bin/turidatunnel-$name"
done
if [[ -s /etc/turidatunnel/domain ]]; then
  DOMAIN="$(head -n1 /etc/turidatunnel/domain)"
elif [[ -s /etc/xray/domain ]]; then
  DOMAIN="$(head -n1 /etc/xray/domain)"
else
  read -rp 'Masukkan domain yang DNS A/AAAA-nya sudah mengarah ke IP VPS: ' DOMAIN
fi
[[ -n "$DOMAIN" ]] || die 'Domain tidak boleh kosong.'
[[ "$DOMAIN" =~ ^[A-Za-z0-9.:-]+$ ]] || die 'Format domain/IP tidak valid.'
printf '%s\n' "$DOMAIN" > /etc/turidatunnel/domain
printf '%s\n' "$DOMAIN" > /etc/xray/domain
install -d -m 0755 /var/lib/scrz-prem
printf 'IP=%s\n' "$DOMAIN" > /var/lib/scrz-prem/ipvps.conf
printf '%s\n' 'TuridaTunnel HTTP bootstrap' > /home/vps/public_html/index.html

say 'Memasang modul SSH/Dropbear.'
bash "$INSTALL_DIR/ssh-vpn.sh"

say 'Memasang Xray dan menghubungkan jalur TLS HAProxy -> Nginx internal.'
bash "$INSTALL_DIR/ins-xray.sh"

cat >/etc/cron.d/turidatunnel-expiry <<EOF3
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
15 3 * * * root $INSTALL_DIR/modules/expire-users.sh >>/var/log/turidatunnel-expiry.log 2>&1
EOF3
chmod 0644 /etc/cron.d/turidatunnel-expiry
systemctl enable --now cron

say 'Menjalankan audit port.'
bash "$INSTALL_DIR/modules/port-audit.sh" || die 'Audit port menemukan konflik.'

cat >/etc/turidatunnel/install.conf <<EOF2
REPOSITORY=${REPO_URL}
BRANCH=${BRANCH}
INSTALL_DIR=${INSTALL_DIR}
NGINX_PUBLIC_PORT=80
HAPROXY_PUBLIC_PORT=443
HAPROXY_BACKEND=127.0.0.1:9443
SSH_PORT=22
DROPBEAR_PORTS=109,143
BADVPN_LISTEN=127.0.0.1:7300
IP_REGISTRATION=disabled
GITHUB_TOKEN=disabled
TELEGRAM_BOT_TOKEN=disabled
CLOUDFLARE_TOKEN=disabled
EOF2

say 'Instalasi selesai.'
say 'Jalur publik: Nginx :80; HAProxy :443 -> Nginx TLS internal 127.0.0.1:9443 -> Xray localhost inbounds.'
say 'SSH: OpenSSH :22; Dropbear :109 dan :143; BadVPN localhost :7300 (amd64).'
say "Log instalasi: $LOG_FILE"
