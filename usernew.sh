#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
read -rp 'Username: ' username
[[ "$username" =~ ^[a-zA-Z0-9_.-]{1,32}$ ]] || { echo 'Username tidak valid.' >&2; exit 1; }
if id "$username" >/dev/null 2>&1; then echo 'Username sudah ada.' >&2; exit 1; fi
read -rsp 'Password: ' password; echo
[[ ${#password} -ge 8 ]] || { echo 'Password minimal 8 karakter.' >&2; exit 1; }
read -rp 'Masa aktif (hari): ' days
[[ "$days" =~ ^[1-9][0-9]{0,3}$ ]] || { echo 'Masa aktif harus 1-9999 hari.' >&2; exit 1; }
expiry="$(date -d "+${days} days" +%F)"
useradd -m -s /bin/bash -e "$expiry" "$username"
printf '%s:%s\n' "$username" "$password" | chpasswd
DOMAIN="$(head -n1 /etc/turidatunnel/domain 2>/dev/null || head -n1 /etc/xray/domain 2>/dev/null || hostname -I | awk '{print $1}')"
printf '\nSSH account created.\nHost: %s\nUsername: %s\nPassword: %s\nExpiry: %s\nPorts: OpenSSH 22; Dropbear 109,143; SSH-WS path /ssh on 80/443\n' "$DOMAIN" "$username" "$password" "$expiry"
