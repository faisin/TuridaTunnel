#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(dirname "$(readlink -f "$0")")"
for proto in vless vmess trojan shadowsocks; do
  echo "===== $proto ====="
  "$BASE/modules/account-manager.sh" list "$proto"
done
