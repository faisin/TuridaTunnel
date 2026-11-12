#!/usr/bin/env bash
# setup2 dipertahankan sebagai alias kompatibilitas.
exec "$(dirname "$(readlink -f "$0")")/setup.sh" "$@"
