#!/usr/bin/env bash
set -Eeuo pipefail
PROTO="${1:-}"
case "$PROTO" in vless|vmess|trojan|shadowsocks) ;; *) echo 'Protocol tidak dikenal.' >&2; exit 2;; esac
MANAGER="$(dirname "$(readlink -f "$0")")/account-manager.sh"
while true; do
  clear 2>/dev/null || true
  printf '\033[1;36m========== TURIDATUNNEL %s ==========\033[0m\n' "${PROTO^^}"
  echo '1. Tambah akun'
  echo '2. Hapus akun'
  echo '3. Daftar akun'
  echo '0. Kembali'
  read -rp 'Pilih: ' choice
  case "$choice" in
    1) "$MANAGER" add "$PROTO" ;;
    2) read -rp 'Username: ' username; "$MANAGER" delete "$PROTO" "$username" ;;
    3) printf 'Username\tExpired\tCredential\n'; "$MANAGER" list "$PROTO" ;;
    0) exit 0 ;;
    *) echo 'Pilihan tidak valid.' ;;
  esac
  read -rp 'Tekan Enter untuk lanjut...' _
done
