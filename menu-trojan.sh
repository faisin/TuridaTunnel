#!/usr/bin/env bash
set -Eeuo pipefail
exec "$(dirname "$(readlink -f "$0")")/modules/protocol-menu.sh" "trojan"
