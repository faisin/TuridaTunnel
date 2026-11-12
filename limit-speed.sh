#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Jalankan sebagai root.'; exit 1; }
IFACE="$(ip -o route show default | awk 'NR==1 {print $5}')"
[[ -n "$IFACE" ]] || { echo 'Interface default route tidak ditemukan.'; exit 1; }
command -v wondershaper >/dev/null || { apt-get update && apt-get install -y wondershaper; }
echo "Interface: $IFACE"
echo '1) Aktifkan limit (Kbps)'
echo '2) Hapus limit'
read -rp 'Pilih: ' choice
case "$choice" in
  1) read -rp 'Download Kbps: ' down; read -rp 'Upload Kbps: ' up
     [[ "$down" =~ ^[0-9]+$ && "$up" =~ ^[0-9]+$ ]] || { echo 'Nilai harus angka.'; exit 1; }
     wondershaper -a "$IFACE" -d "$down" -u "$up"; echo "$IFACE $down $up" >/etc/turidatunnel/limit-speed.conf ;;
  2) wondershaper -c -a "$IFACE"; rm -f /etc/turidatunnel/limit-speed.conf ;;
  *) echo 'Pilihan tidak valid.'; exit 1;;
esac
