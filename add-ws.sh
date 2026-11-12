#!/usr/bin/env bash
set -Eeuo pipefail
exec "$(dirname "$(readlink -f "$0")")/modules/account-manager.sh" add "vmess" "$@"
