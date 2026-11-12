#!/usr/bin/env bash
set -Eeuo pipefail

# TuridaTunnel bootstrap installer.
# Supports both:
#   wget -qO- https://raw.githubusercontent.com/faisin/TuridaTunnel/main/setup.sh | bash
#   bash setup.sh (from an extracted project directory)

REPO_OWNER="faisin"
REPO_NAME="TuridaTunnel"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"
ARCHIVE_URL="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/zip/refs/heads/${BRANCH}"
INSTALL_DIR="/opt/turidatunnel"
LOG_FILE="/var/log/turidatunnel-install.log"

say(){ printf '\033[1;36m[TuridaTunnel]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die 'Jalankan sebagai root.'
[[ -r /etc/os-release ]] || die 'Tidak dapat membaca /etc/os-release.'
. /etc/os-release
case "${ID}:${VERSION_ID}" in
  debian:12|debian:13|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) ;;
  *) die "OS tidak didukung: ${PRETTY_NAME:-unknown}. Target Debian 12/13 dan Ubuntu 22.04/24.04/26.04." ;;
esac
command -v apt-get >/dev/null 2>&1 || die 'APT tidak tersedia.'

install -d -m 0755 /var/log
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'rc=$?; say "Instalasi gagal pada baris ${LINENO:-?} (exit ${rc}). Log: ${LOG_FILE}"; exit "$rc"' ERR
export DEBIAN_FRONTEND=noninteractive

say "OS: ${PRETTY_NAME}"
say 'Memasang dependensi dasar.'
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl wget unzip jq openssl socat cron iproute2 net-tools lsof procps psmisc dnsutils python3 nginx haproxy certbot

# Prefer a complete local checkout when setup.sh is run from an extracted ZIP.
SOURCE_DIR=""
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"
  if [[ -s "$SCRIPT_DIR/ssh-vpn.sh" && -s "$SCRIPT_DIR/ins-xray.sh" && -d "$SCRIPT_DIR/modules" ]]; then
    SOURCE_DIR="$SCRIPT_DIR"
  fi
fi

if [[ -z "$SOURCE_DIR" ]]; then
  say "Mengunduh source ${REPO_OWNER}/${REPO_NAME} branch ${BRANCH} dari GitHub (tanpa git clone)."
  TMP_DIR="$(mktemp -d /tmp/turidatunnel-bootstrap.XXXXXX)"
  cleanup(){ rm -rf "${TMP_DIR:-}"; }
  trap cleanup EXIT
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 "$ARCHIVE_URL" -o "$TMP_DIR/source.zip"
  else
    wget -O "$TMP_DIR/source.zip" "$ARCHIVE_URL"
  fi
  unzip -q "$TMP_DIR/source.zip" -d "$TMP_DIR/unpacked"
  SOURCE_DIR="$(find "$TMP_DIR/unpacked" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [[ -n "$SOURCE_DIR" && -s "$SOURCE_DIR/ssh-vpn.sh" && -s "$SOURCE_DIR/ins-xray.sh" && -d "$SOURCE_DIR/modules" ]] || die 'Arsip GitHub tidak berisi struktur TuridaTunnel yang lengkap.'
fi

install -d -m 0755 "$INSTALL_DIR"
if [[ "$(realpath -m "$SOURCE_DIR")" != "$(realpath -m "$INSTALL_DIR")" ]]; then
  say "Memasang source ke ${INSTALL_DIR}."
  cp -a "$SOURCE_DIR/." "$INSTALL_DIR/"
fi
[[ -s "$INSTALL_DIR/ssh-vpn.sh" && -s "$INSTALL_DIR/ins-xray.sh" && -d "$INSTALL_DIR/modules" ]] || die 'File inti instalasi tidak lengkap.'

install -d -m 0755 /etc/turidatunnel /etc/xray /home/vps/public_html /var/log/xray /usr/local/bin
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
  # /dev/tty allows interactive prompts even when setup.sh is piped from wget/curl.
  if [[ -r /dev/tty ]]; then
    read -r -p 'Masukkan domain yang DNS A/AAAA-nya sudah mengarah ke IP VPS: ' DOMAIN </dev/tty
  else
    die 'Domain belum diset. Buat /etc/turidatunnel/domain sebelum instalasi non-interaktif.'
  fi
fi
[[ -n "${DOMAIN:-}" ]] || die 'Domain tidak boleh kosong.'
[[ "$DOMAIN" =~ ^[A-Za-z0-9.:-]+$ ]] || die 'Format domain/IP tidak valid.'
printf '%s\n' "$DOMAIN" > /etc/turidatunnel/domain
printf '%s\n' "$DOMAIN" > /etc/xray/domain
printf '%s\n' 'TuridaTunnel HTTP bootstrap' > /home/vps/public_html/index.html

say 'Memasang modul SSH/Dropbear.'
bash "$INSTALL_DIR/ssh-vpn.sh"

say 'Memasang Xray dan menghubungkan jalur TLS HAProxy -> Nginx internal.'
bash "$INSTALL_DIR/ins-xray.sh"

cat >/etc/cron.d/turidatunnel-expiry <<EOF_EXPIRY
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
15 3 * * * root $INSTALL_DIR/modules/expire-users.sh >>/var/log/turidatunnel-expiry.log 2>&1
EOF_EXPIRY
chmod 0644 /etc/cron.d/turidatunnel-expiry
systemctl enable --now cron

say 'Mengaktifkan enforcement quota dan limit IP Xray.'
install -m 0644 "$INSTALL_DIR/modules/turidatunnel-limits.service" /etc/systemd/system/turidatunnel-limits.service
install -m 0644 "$INSTALL_DIR/modules/turidatunnel-limits.timer" /etc/systemd/system/turidatunnel-limits.timer
systemctl daemon-reload
systemctl enable --now turidatunnel-limits.timer

say 'Menjalankan audit port.'
bash "$INSTALL_DIR/modules/port-audit.sh" || die 'Audit port menemukan konflik.'

cat >/etc/turidatunnel/install.conf <<EOF_CONF
REPOSITORY=https://github.com/${REPO_OWNER}/${REPO_NAME}
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
EOF_CONF

say 'Instalasi selesai.'
say 'Jalur publik: Nginx :80; HAProxy :443 -> Nginx TLS internal 127.0.0.1:9443 -> Xray localhost inbounds.'
say 'SSH: OpenSSH :22; Dropbear :109 dan :143; BadVPN localhost :7300 (amd64).'
say "Log instalasi: $LOG_FILE"
