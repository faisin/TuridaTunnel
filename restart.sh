#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
while true; do
  echo '===== TURIDATUNNEL SERVICE RESTART ====='
  echo '1) Restart semua layanan'
  echo '2) Restart OpenSSH'
  echo '3) Restart Dropbear'
  echo '4) Restart Xray'
  echo '5) Restart Nginx + HAProxy'
  echo '6) Restart BadVPN'
  echo '0) Kembali'
  read -rp 'Pilih: ' choice
  case "$choice" in
    1) systemctl restart ssh turidatunnel-dropbear xray nginx haproxy; systemctl restart turidatunnel-badvpn 2>/dev/null || true ;;
    2) systemctl restart ssh ;;
    3) systemctl restart turidatunnel-dropbear ;;
    4) systemctl restart xray ;;
    5) nginx -t && haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl restart nginx haproxy ;;
    6) systemctl restart turidatunnel-badvpn ;;
    0) exit 0 ;;
    *) echo 'Pilihan tidak valid.' ;;
  esac
  read -rp 'Tekan Enter...' _
done
