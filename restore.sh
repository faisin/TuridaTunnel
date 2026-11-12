#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
DIR=/root/turidatunnel-backups
[[ -d "$DIR" ]] || { echo 'Folder backup tidak ditemukan.' >&2; exit 1; }
mapfile -t files < <(find "$DIR" -maxdepth 1 -type f -name 'turidatunnel-*.tar.gz' -printf '%f\n' | sort -r)
((${#files[@]})) || { echo 'Tidak ada backup lokal.'; exit 1; }
for i in "${!files[@]}"; do printf '%d) %s\n' "$((i+1))" "${files[$i]}"; done
read -rp 'Pilih nomor backup: ' n
[[ "$n" =~ ^[0-9]+$ ]] && ((n>=1 && n<=${#files[@]})) || { echo 'Pilihan tidak valid.'; exit 1; }
ARCHIVE="$DIR/${files[$((n-1))]}"
# Refuse archives containing absolute paths or traversal components.
if tar -tzf "$ARCHIVE" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then echo 'Arsip berisi path tidak aman.' >&2; exit 1; fi
read -rp 'Restore akan menimpa konfigurasi TuridaTunnel saat ini. Lanjutkan? [y/N] ' answer
[[ "$answer" =~ ^[Yy]$ ]] || exit 0
tar -xzf "$ARCHIVE" -C /
systemctl restart xray haproxy nginx 2>/dev/null || true
echo "Restore selesai dari $ARCHIVE"
