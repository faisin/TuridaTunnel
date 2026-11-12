#!/usr/bin/env bash
set -Eeuo pipefail
if ! command -v speedtest-cli >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y speedtest-cli
fi
exec speedtest-cli
