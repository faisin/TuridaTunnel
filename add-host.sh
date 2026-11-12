#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
read -rp 'Domain baru (DNS harus mengarah ke VPS): ' host
[[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || { echo 'Format domain tidak valid.' >&2; exit 1; }
printf '%s\n' "$host" >/etc/turidatunnel/domain
printf '%s\n' "$host" >/etc/xray/domain
install -d -m 0755 /var/lib/scrz-prem
printf 'IP=%s\n' "$host" >/var/lib/scrz-prem/ipvps.conf
echo 'Domain disimpan. Jalankan certbot webroot/renew SSL setelah DNS siap.'
