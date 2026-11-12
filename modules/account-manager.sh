#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG=/etc/xray/config.json
ENV_FILE=/etc/turidatunnel/xray.env
DOMAIN_FILE=/etc/turidatunnel/domain
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
umask 077
install -d -m 0755 /run/lock
exec 9>/run/lock/turidatunnel-account.lock
flock -x 9
[[ -s "$CONFIG" && -s "$ENV_FILE" ]] || { echo 'Xray belum terpasang.' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'jq belum terpasang.' >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
DOMAIN="$(head -n1 "$DOMAIN_FILE")"

usage(){ echo "Usage: $0 {add|delete|list} {vless|vmess|trojan|shadowsocks} [username] [days]"; }
valid_proto(){ case "$1" in vless|vmess|trojan|shadowsocks) return 0;; *) return 1;; esac; }

add_user(){
  local proto="$1" user="$2" days="$3" id expiry method tmp
  [[ "$user" =~ ^[a-zA-Z0-9_.-]{1,32}$ ]] || { echo 'Username tidak valid (1-32 karakter: huruf, angka, _, ., -).'; exit 1; }
  [[ "$days" =~ ^[1-9][0-9]{0,3}$ ]] || { echo 'Masa aktif harus 1-9999 hari.'; exit 1; }
  if jq -e --arg u "$user" '[.inbounds[].settings.clients[]? | select(.email==$u)] | length>0' "$CONFIG" >/dev/null; then
    echo "Username $user sudah ada."; exit 1
  fi
  id="$(cat /proc/sys/kernel/random/uuid)"
  expiry="$(date -d "+${days} days" +%F)"
  case "$proto" in
    vless)
      jq --arg id "$id" --arg u "$user" '
        (.inbounds[] | select(.tag=="vless-ws" or .tag=="vless-grpc") | .settings.clients) += [{id:$id,email:$u}]' "$CONFIG" >"${CONFIG}.tmp" ;;
    vmess)
      jq --arg id "$id" --arg u "$user" '
        (.inbounds[] | select(.tag=="vmess-ws" or .tag=="vmess-grpc") | .settings.clients) += [{id:$id,alterId:0,email:$u}]' "$CONFIG" >"${CONFIG}.tmp" ;;
    trojan)
      jq --arg id "$id" --arg u "$user" '
        (.inbounds[] | select(.tag=="trojan-ws" or .tag=="trojan-grpc") | .settings.clients) += [{password:$id,email:$u}]' "$CONFIG" >"${CONFIG}.tmp" ;;
    shadowsocks)
      method=aes-128-gcm
      jq --arg id "$id" --arg u "$user" --arg method "$method" '
        (.inbounds[] | select(.tag=="ss-ws" or .tag=="ss-grpc") | .settings.clients) += [{method:$method,password:$id,email:$u}]' "$CONFIG" >"${CONFIG}.tmp" ;;
  esac
  /usr/local/bin/xray run -test -config "${CONFIG}.tmp" >/dev/null
  mv "${CONFIG}.tmp" "$CONFIG"
  chown root:www-data "$CONFIG"
  chmod 0640 "$CONFIG"
  install -d -m 0750 /etc/turidatunnel
  printf '%s\t%s\t%s\t%s\n' "$proto" "$user" "$id" "$expiry" >> /etc/turidatunnel/users.tsv
  chmod 0640 /etc/turidatunnel/users.tsv
  systemctl restart xray
  echo "Username : $user"
  echo "Protocol : $proto (WS + gRPC)"
  echo "Password/UUID : $id"
  echo "Expired : $expiry"
  case "$proto" in
    vless)
      echo "VLESS WS : vless://${id}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=%2Fvless&sni=${DOMAIN}#${user}"
      echo "VLESS gRPC: vless://${id}@${DOMAIN}:443?encryption=none&security=tls&type=grpc&serviceName=vless-grpc&sni=${DOMAIN}#${user}" ;;
    vmess)
      printf 'vmess://'
      printf '{"v":"2","ps":"%s","add":"%s","port":"443","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"/vmess","tls":"tls","sni":"%s"}' "$user" "$DOMAIN" "$id" "$DOMAIN" "$DOMAIN" | base64 -w0
      echo ;;
    trojan)
      echo "Trojan WS : trojan://${id}@${DOMAIN}:443?security=tls&type=ws&path=%2Ftrojan-ws&sni=${DOMAIN}#${user}"
      echo "Trojan gRPC: trojan://${id}@${DOMAIN}:443?security=tls&type=grpc&serviceName=trojan-grpc&sni=${DOMAIN}#${user}" ;;
    shadowsocks)
      ss_userinfo="$(printf 'aes-128-gcm:%s' "$id" | base64 -w0)"
      echo "Shadowsocks WS: ss://${ss_userinfo}@${DOMAIN}:443?plugin=v2ray-plugin%3Bmode%3Dwebsocket%3Bhost%3D${DOMAIN}%3Bpath%3D%2Fss-ws%3Btls#${user}"
      echo "Shadowsocks password: $id (method: aes-128-gcm; gRPC service: ss-grpc)" ;;
  esac
}

delete_user(){
  local proto="$1" user="$2"
  [[ "$user" =~ ^[a-zA-Z0-9_.-]{1,32}$ ]] || { echo 'Username tidak valid.'; exit 1; }
  local tagprefix
  case "$proto" in
    vless|vmess|trojan) tagprefix="$proto" ;;
    shadowsocks) tagprefix="ss" ;;
  esac
  jq --arg u "$user" --arg p "$tagprefix" '
    (.inbounds[] | select(.tag | startswith($p)) | .settings.clients) |= map(select(.email != $u))' "$CONFIG" >"${CONFIG}.tmp"
  /usr/local/bin/xray run -test -config "${CONFIG}.tmp" >/dev/null
  mv "${CONFIG}.tmp" "$CONFIG"
  chown root:www-data "$CONFIG"
  chmod 0640 "$CONFIG"
  if [[ -f /etc/turidatunnel/users.tsv ]]; then
    awk -F '\t' -v p="$proto" -v u="$user" '!( $1==p && $2==u )' /etc/turidatunnel/users.tsv > /etc/turidatunnel/users.tsv.tmp
    mv /etc/turidatunnel/users.tsv.tmp /etc/turidatunnel/users.tsv
  fi
  systemctl restart xray
  echo "Akun $user dihapus dari protokol $proto."
}

list_users(){
  local proto="$1"
  if [[ -f /etc/turidatunnel/users.tsv ]]; then
    awk -F '\t' -v p="$proto" '$1==p {printf "%s\t%s\t%s\n",$2,$4,$3}' /etc/turidatunnel/users.tsv
  fi
}

ACTION="${1:-}"; PROTO="${2:-}"
case "$ACTION" in
  add|delete|list) ;;
  *) usage; exit 2 ;;
esac
valid_proto "$PROTO" || { usage; exit 2; }
if [[ "$ACTION" == list ]]; then list_users "$PROTO"; exit 0; fi
USER_NAME="${3:-}"
if [[ -z "$USER_NAME" ]]; then read -rp 'Username: ' USER_NAME; fi
if [[ "$ACTION" == add ]]; then
  DAYS="${4:-}"
  if [[ -z "$DAYS" ]]; then read -rp 'Masa aktif (hari): ' DAYS; fi
  add_user "$PROTO" "$USER_NAME" "$DAYS"
else
  delete_user "$PROTO" "$USER_NAME"
fi
