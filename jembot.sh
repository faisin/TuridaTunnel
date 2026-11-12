#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y vnstat
IFACE="$(ip route show default | awk 'NR==1 {print $5}')"
[[ -n "$IFACE" ]] || { echo 'Interface default route tidak ditemukan.' >&2; exit 1; }
install -d -m 0755 /etc/vnstat
if grep -q '^Interface ' /etc/vnstat.conf 2>/dev/null; then
  sed -i "s/^Interface .*/Interface \"$IFACE\"/" /etc/vnstat.conf
else
  printf '\nInterface "%s"\n' "$IFACE" >> /etc/vnstat.conf
fi
systemctl enable --now vnstat
systemctl restart vnstat
vnstat --add -i "$IFACE" >/dev/null 2>&1 || true
printf 'vnStat aktif pada interface %s.\n' "$IFACE"
