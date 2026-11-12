#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST=/root/turidatunnel-backups
install -d -m 0700 "$DEST"
ARCHIVE="$DEST/turidatunnel-${STAMP}.tar.gz"
items=()
for path in /etc/xray /etc/turidatunnel /home/vps/public_html /etc/haproxy/haproxy.cfg /etc/nginx/sites-available/turidatunnel.conf /etc/nginx/snippets/turidatunnel-ws.conf; do
  [[ -e "$path" ]] && items+=("${path#/}")
done
((${#items[@]})) || { echo 'Tidak ada data TuridaTunnel yang dapat dibackup.'; exit 1; }
tar --numeric-owner -czf "$ARCHIVE" -C / "${items[@]}"
chmod 0600 "$ARCHIVE"
echo "Backup lokal selesai: $ARCHIVE"
echo 'File backup tidak dikirim ke GitHub, Telegram, Google Drive, atau layanan eksternal.'
