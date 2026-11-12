#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
BASE="$(dirname "$(readlink -f "$0")")"
install -m 0755 "$BASE/backup.sh" /usr/local/bin/turidatunnel-backup
install -m 0755 "$BASE/restore.sh" /usr/local/bin/turidatunnel-restore
install -m 0755 "$BASE/logcleaner.sh" /usr/local/bin/turidatunnel-logcleaner
install -d -m 0755 /etc/cron.d
cat >/etc/cron.d/turidatunnel-logcleaner <<'CRON'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/10 * * * * root /usr/local/bin/turidatunnel-logcleaner >/dev/null 2>&1
CRON
systemctl restart cron
printf 'Utilitas backup lokal dan log cleaner dipasang. Tidak ada rclone/token.\n'
