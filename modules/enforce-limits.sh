#!/usr/bin/env bash
set -Eeuo pipefail
exec /usr/bin/python3 "$(dirname "$(readlink -f "$0")")/enforce-limits.py"
