#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(dirname "$(readlink -f "$0")")"
echo '1) Buat backup lokal'
echo '2) Restore backup lokal'
echo '0) Kembali'
read -rp 'Pilih: ' choice
case "$choice" in
  1) exec "$BASE/backup.sh" ;;
  2) exec "$BASE/restore.sh" ;;
  0) exit 0 ;;
  *) echo 'Pilihan tidak valid.'; exit 2 ;;
esac
