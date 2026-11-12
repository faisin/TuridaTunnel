#!/usr/bin/env bash
set -Eeuo pipefail
DB=/etc/turidatunnel/users.tsv
BASE="$(cd -- "$(dirname -- "$0")" && pwd -P)"
[[ -f "$DB" ]] || exit 0
today="$(date +%F)"
while IFS=$'\t' read -r proto user credential expiry quota max_ip; do
  [[ -n "$proto" && -n "$user" && -n "$expiry" ]] || continue
  if [[ "$expiry" < "$today" || "$expiry" == "$today" ]]; then
    if [[ "$proto" == ssh ]]; then "$BASE/unified-account-manager.sh" delete ssh "$user" || true
    else "$BASE/account-manager.sh" delete "$proto" "$user" || true
    fi
  fi
done < "$DB"
