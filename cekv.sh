#!/usr/bin/env bash
set -Eeuo pipefail
INSTALL_DIR=/opt/turidatunnel
if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  echo 'Repositori belum tersedia di /opt/turidatunnel.'
  exit 1
fi
git -C "$INSTALL_DIR" remote set-url origin https://github.com/faisin/turidatunnel.git
git -C "$INSTALL_DIR" fetch --depth=1 origin main
git -C "$INSTALL_DIR" reset --hard FETCH_HEAD
echo 'TuridaTunnel berhasil diperbarui dari faisin/turidatunnel.'
