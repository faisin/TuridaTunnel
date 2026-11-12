#!/usr/bin/env bash
set -Eeuo pipefail

PROTO="${1:-}"
case "$PROTO" in
  vless|vmess|trojan|shadowsocks) ;;
  *) echo 'Protocol tidak dikenal.' >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
MANAGER="$SCRIPT_DIR/account-manager.sh"
[[ -x "$MANAGER" ]] || { echo "Account manager tidak ditemukan: $MANAGER" >&2; exit 1; }

run_manager() {
  local rc=0
  "$MANAGER" "$@" || rc=$?
  if (( rc != 0 )); then
    printf '\n\033[1;31m[ GAGAL ] Account manager berhenti (exit code %d).\033[0m\n' "$rc" >&2
    echo 'Pesan error di atas adalah penyebab yang perlu diperbaiki.' >&2
  fi
  return 0
}

while true; do
  clear 2>/dev/null || true
  printf '\033[1;36m========== TURIDATUNNEL %s ==========\033[0m\n' "${PROTO^^}"
  echo '1. Tambah akun'
  echo '2. Hapus akun'
  echo '3. Daftar akun'
  echo '0. Kembali'
  read -rp 'Pilih: ' choice || exit 0
  case "$choice" in
    1) run_manager add "$PROTO" ;;
    2)
      read -rp 'Username: ' username || continue
      run_manager delete "$PROTO" "$username"
      ;;
    3)
      printf 'Username\tExpired\tCredential\tQuota\tMax IP\n'
      run_manager list "$PROTO"
      ;;
    0) exit 0 ;;
    *) echo 'Pilihan tidak valid.' ;;
  esac
  read -rp 'Tekan Enter untuk lanjut...' _ || exit 0
done
