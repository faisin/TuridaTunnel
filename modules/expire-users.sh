#!/usr/bin/env bash
set -Eeuo pipefail
DB=/etc/turidatunnel/users.tsv
MANAGER="$(dirname "$(readlink -f "$0")")/account-manager.sh"
[[ -f "$DB" ]] || exit 0
today="$(date +%F)"
while IFS=$'\t' read -r proto user credential expiry; do
  [[ -n "$proto" && -n "$user" && -n "$expiry" ]] || continue
  if [[ "$expiry" < "$today" || "$expiry" == "$today" ]]; then
    "$MANAGER" delete "$proto" "$user"
  fi
done < "$DB"
