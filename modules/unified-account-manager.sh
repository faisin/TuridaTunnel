#!/usr/bin/env bash
# Unified account front-end. SSH identities are Linux users; Xray identities
# are managed by account-manager.sh. All records share users.tsv.
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
BASE="$(cd -- "$(dirname -- "$0")" && pwd -P)"
DB=/etc/turidatunnel/users.tsv
install -d -m 0750 /etc/turidatunnel
: >> "$DB"; chmod 0640 "$DB"
valid_user(){ [[ "$1" =~ ^[a-zA-Z0-9_.-]{1,32}$ ]] && [[ "$1" != root ]]; }
exists(){ awk -F '\t' -v u="$1" '$2==u {found=1} END{exit !found}' "$DB"; }
ssh_add(){
  local u="$1" days="$2" quota="$3" maxip="$4" pass exp
  valid_user "$u" || { echo 'Username tidak valid.' >&2; return 1; }
  [[ "$days" =~ ^[1-9][0-9]{0,3}$ && "$quota" =~ ^[0-9]+([.][0-9]+)?$ && "$maxip" =~ ^[1-9][0-9]{0,2}$ ]] || { echo 'Parameter days/quota/max_ip tidak valid.' >&2; return 1; }
  ! exists "$u" || { echo 'Username sudah terdaftar di database TuridaTunnel.' >&2; return 1; }
  ! getent passwd "$u" >/dev/null || { echo 'Username Linux sudah ada di luar database TuridaTunnel.' >&2; return 1; }
  pass="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-16)"
  exp="$(date -d "+${days} days" +%F)"
  useradd -m -s /bin/bash "$u"
  printf '%s:%s\n' "$u" "$pass" | chpasswd
  chage -E "$(date -d "$exp" +%F)" "$u"
  # PAM maxlogins applies to PAM-backed sshd and Dropbear builds.
  install -d -m 0755 /etc/security/limits.d
  touch /etc/security/limits.d/90-turidatunnel.conf
  sed -i "/^${u}[[:space:]]\+hard[[:space:]]\+maxlogins[[:space:]]/d" /etc/security/limits.d/90-turidatunnel.conf
  printf '%s hard maxlogins %s\n' "$u" "$maxip" >> /etc/security/limits.d/90-turidatunnel.conf
  for pam in /etc/pam.d/sshd /etc/pam.d/dropbear; do
    [[ -f "$pam" ]] || continue
    grep -qE '^[[:space:]]*session[[:space:]]+required[[:space:]]+pam_limits\.so' "$pam" || printf '\nsession required pam_limits.so\n' >> "$pam"
  done
  printf 'ssh\t%s\t%s\t%s\t%s\t%s\n' "$u" 'linux-password' "$exp" "$quota" "$maxip" >> "$DB"
  chmod 0640 "$DB"
  systemctl reload ssh 2>/dev/null || systemctl restart ssh
  systemctl restart turidatunnel-dropbear 2>/dev/null || true
  printf 'SSH account created\nUsername: %s\nPassword: %s\nExpiry: %s\nMax concurrent logins: %s\nQuota configured: %s GB\n' "$u" "$pass" "$exp" "$maxip" "$quota"
  echo 'NOTE: SSH per-account traffic quota is recorded as policy only; byte-level enforcement is not enabled by this module.'
}
ssh_delete(){
  local u="$1"; valid_user "$u" || { echo 'Username tidak valid.' >&2; return 1; }
  awk -F '\t' -v u="$u" '$1=="ssh" && $2==u {found=1} END{exit !found}' "$DB" || { echo 'Akun SSH TuridaTunnel tidak ditemukan.'; return 1; }
  userdel -r "$u" 2>/dev/null || userdel "$u"
  sed -i "/^${u}[[:space:]]\+hard[[:space:]]\+maxlogins[[:space:]]/d" /etc/security/limits.d/90-turidatunnel.conf 2>/dev/null || true
  awk -F '\t' -v u="$u" '!( $1=="ssh" && $2==u )' "$DB" > "$DB.tmp"; cat "$DB.tmp" > "$DB"; rm -f "$DB.tmp"
  echo "Akun SSH $u dihapus."
}
ssh_list(){ awk -F '\t' '$1=="ssh" {printf "%-20s %-12s quota=%sGB maxIP=%s\n",$2,$4,$5,$6}' "$DB"; }
if [[ $# -gt 0 ]]; then
  action="$1"; proto="${2:-}"; shift 2 || true
  if [[ "$proto" == ssh ]]; then
    case "$action" in add) ssh_add "$@";; delete) ssh_delete "$@";; list) ssh_list;; *) exit 2;; esac
  else
    exec "$BASE/account-manager.sh" "$action" "$proto" "$@"
  fi
  exit
fi
while true; do
  echo; echo '====== TURIDATUNNEL ACCOUNT CENTER ======'
  echo '1. Tambah akun SSH (OpenSSH + Dropbear + SSH-WS)'
  echo '2. Hapus akun SSH'
  echo '3. Daftar akun SSH'
  echo '4. Kelola akun VLESS'
  echo '5. Kelola akun VMess'
  echo '6. Kelola akun Trojan'
  echo '7. Kelola akun Shadowsocks'
  echo '0. Kembali'
  read -rp 'Pilih: ' c
  case "$c" in
    1) read -rp 'Username: ' u; read -rp 'Masa aktif (hari): ' d; read -rp 'Quota GB (0=unlimited): ' q; read -rp 'Maksimal IP/login bersamaan: ' m; ssh_add "$u" "$d" "$q" "$m" ;;
    2) read -rp 'Username: ' u; ssh_delete "$u" ;;
    3) ssh_list ;;
    4) bash "$BASE/protocol-menu.sh" vless ;;
    5) bash "$BASE/protocol-menu.sh" vmess ;;
    6) bash "$BASE/protocol-menu.sh" trojan ;;
    7) bash "$BASE/protocol-menu.sh" shadowsocks ;;
    0) exit 0 ;;
    *) echo 'Pilihan tidak valid.' ;;
  esac
done
