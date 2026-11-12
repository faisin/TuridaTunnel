#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
. /etc/os-release
case "${ID}:${VERSION_ID}" in debian:12|debian:13|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) ;; *) echo 'OS tidak didukung.'; exit 1;; esac
if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
  echo 'Kernel aktif tidak menyediakan BBR. Tidak mengunduh atau memasang kernel pihak ketiga.'
  exit 1
fi
install -d -m 0755 /etc/sysctl.d
cat >/etc/sysctl.d/90-turidatunnel-bbr.conf <<'SYSCTL'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL
sysctl --system
printf 'BBR aktif: '
sysctl -n net.ipv4.tcp_congestion_control
