#!/usr/bin/env bash
set -Eeuo pipefail
read -rp 'Protocol (vless/vmess/trojan/shadowsocks): ' proto
read -rp 'Username: ' username
exec "$(dirname "$(readlink -f "$0")")/modules/account-manager.sh" delete "$proto" "$username"
