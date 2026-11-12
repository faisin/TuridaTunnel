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

usage(){ echo "Usage: $0 {add|delete|list} {vless|vmess|trojan|shadowsocks} [username] [days] [quota_gb] [max_ip]"; }
valid_proto(){ case "$1" in vless|vmess|trojan|shadowsocks) return 0;; *) return 1;; esac; }

add_user(){
  local proto="$1" user="$2" days="$3" quota_gb="${4:-0}" max_ip="${5:-1}" id expiry method tmp
  [[ "$user" =~ ^[a-zA-Z0-9_.-]{1,32}$ ]] || { echo 'Username tidak valid (1-32 karakter: huruf, angka, _, ., -).'; exit 1; }
  [[ "$days" =~ ^[1-9][0-9]{0,3}$ ]] || { echo 'Masa aktif harus 1-9999 hari.'; exit 1; }
  [[ "$quota_gb" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo 'Quota GB harus angka (0=unlimited).'; exit 1; }
  [[ "$max_ip" =~ ^[1-9][0-9]{0,2}$ ]] || { echo 'Limit IP harus 1-999.'; exit 1; }
  if jq -e --arg u "$user" '[.inbounds[].settings.clients[]? | select(.email==$u)] | length>0' "$CONFIG" >/dev/null; then
    echo "Username $user sudah ada."; exit 1
  fi
  id="$(cat /proc/sys/kernel/random/uuid)"
  expiry="$(date -d "+${days} days" +%F)"
  case "$proto" in
    vless)
      jq --arg id "$id" --arg u "$user" '
        (.inbounds[] | select(.tag=="vless-ws" or .tag=="vless-grpc" or .tag=="vless-hu") | .settings.clients) += [{id:$id,email:$u}]' "$CONFIG" >"${CONFIG}.tmp" ;;
    vmess)
      jq --arg id "$id" --arg u "$user" '
        (.inbounds[] | select(.tag=="vmess-ws" or .tag=="vmess-grpc" or .tag=="vmess-hu") | .settings.clients) += [{id:$id,alterId:0,email:$u}]' "$CONFIG" >"${CONFIG}.tmp" ;;
    trojan)
      jq --arg id "$id" --arg u "$user" '
        (.inbounds[] | select(.tag=="trojan-ws" or .tag=="trojan-grpc" or .tag=="trojan-hu") | .settings.clients) += [{password:$id,email:$u}]' "$CONFIG" >"${CONFIG}.tmp" ;;
    shadowsocks)
      method=aes-128-gcm
      jq --arg id "$id" --arg u "$user" --arg method "$method" '
        (.inbounds[] | select(.tag=="ss-ws" or .tag=="ss-grpc" or .tag=="ss-hu") | .settings.clients) += [{method:$method,password:$id,email:$u}]' "$CONFIG" >"${CONFIG}.tmp" ;;
  esac
  /usr/local/bin/xray run -test -config "${CONFIG}.tmp" >/dev/null
  mv "${CONFIG}.tmp" "$CONFIG"
  chown root:www-data "$CONFIG"
  chmod 0640 "$CONFIG"
  install -d -m 0750 /etc/turidatunnel
  # A deleted/recreated account starts with a fresh quota and IP lease history.
  if [[ -s /etc/turidatunnel/limits-state.json ]]; then
    python3 - "$user" <<'PYRESET'
import json,sys
p='/etc/turidatunnel/limits-state.json'; u=sys.argv[1]
try: d=json.load(open(p))
except Exception: d={'prev':{},'total':{},'leases':{},'disabled':{}}
for k in ('prev','total','leases','disabled'): d.setdefault(k,{}).pop(u,None)
tmp=p+'.tmp'; json.dump(d,open(tmp,'w')); import os; os.chmod(tmp,0o600); os.replace(tmp,p)
PYRESET
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$proto" "$user" "$id" "$expiry" "$quota_gb" "$max_ip" >> /etc/turidatunnel/users.tsv
  chmod 0640 /etc/turidatunnel/users.tsv
  systemctl restart xray
  echo "Username : $user"
  echo "Protocol : $proto (WS + HTTPUpgrade + gRPC)"
  echo "Quota    : $quota_gb GB (0=unlimited)"
  echo "Max IP   : $max_ip (enforcement lease controller)"
  echo "Password/UUID : $id"
  echo "Expired : $expiry"
  case "$proto" in
    vless)
      echo "VLESS HTTPUpgrade: vless://${id}@${DOMAIN}:443?encryption=none&security=tls&type=httpupgrade&host=${DOMAIN}&path=%2Fvless-hu&sni=${DOMAIN}#${user}"
      echo "VLESS WS : vless://${id}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=%2Fvless&sni=${DOMAIN}#${user}"
      echo "VLESS gRPC: vless://${id}@${DOMAIN}:443?encryption=none&security=tls&type=grpc&serviceName=vless-grpc&sni=${DOMAIN}#${user}" ;;
    vmess)
      echo "VMess HTTPUpgrade: client harus memakai network httpupgrade, path /vmess-hu, TLS, host ${DOMAIN}."
      printf 'vmess://'
      printf '{"v":"2","ps":"%s","add":"%s","port":"443","id":"%s","aid":"0","net":"httpupgrade","type":"none","host":"%s","path":"/vmess-hu","tls":"tls","sni":"%s"}' "$user" "$DOMAIN" "$id" "$DOMAIN" "$DOMAIN" | base64 -w0
      echo ;;
    trojan)
      echo "Trojan HTTPUpgrade: trojan://${id}@${DOMAIN}:443?security=tls&type=httpupgrade&host=${DOMAIN}&path=%2Ftrojan-hu&sni=${DOMAIN}#${user}"
      echo "Trojan WS : trojan://${id}@${DOMAIN}:443?security=tls&type=ws&path=%2Ftrojan-ws&sni=${DOMAIN}#${user}"
      echo "Trojan gRPC: trojan://${id}@${DOMAIN}:443?security=tls&type=grpc&serviceName=trojan-grpc&sni=${DOMAIN}#${user}" ;;
    shadowsocks)
      echo "Shadowsocks HTTPUpgrade: plugin v2ray-plugin;mode=websocket not compatible with HTTPUpgrade; use a client supporting Xray httpupgrade transport."
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
    (.inbounds[] | select((.tag | startswith($p)) or (.tag=="ss-hu" and $p=="ss")) | .settings.clients) |= map(select(.email != $u))' "$CONFIG" >"${CONFIG}.tmp"
  /usr/local/bin/xray run -test -config "${CONFIG}.tmp" >/dev/null
  mv "${CONFIG}.tmp" "$CONFIG"
  chown root:www-data "$CONFIG"
  chmod 0640 "$CONFIG"
  if [[ -f /etc/turidatunnel/users.tsv ]]; then
    awk -F '\t' -v p="$proto" -v u="$user" '!( $1==p && $2==u )' /etc/turidatunnel/users.tsv > /etc/turidatunnel/users.tsv.tmp
    mv /etc/turidatunnel/users.tsv.tmp /etc/turidatunnel/users.tsv
  fi
  systemctl restart xray
  if [[ -s /etc/turidatunnel/limits-state.json ]]; then
    python3 - "$user" <<'PYDELSTATE'
import json,sys,os
p='/etc/turidatunnel/limits-state.json'; u=sys.argv[1]
try: d=json.load(open(p))
except Exception: raise SystemExit(0)
for k in ('prev','total','leases','disabled'): d.setdefault(k,{}).pop(u,None)
t=p+'.tmp'; json.dump(d,open(t,'w')); os.chmod(t,0o600); os.replace(t,p)
PYDELSTATE
  fi
  echo "Akun $user dihapus dari protokol $proto."
}

list_users(){
  local proto="$1"
  if [[ -f /etc/turidatunnel/users.tsv ]]; then
    awk -F '\t' -v p="$proto" '$1==p {printf "%s\t%s\t%s\t%s\t%s\n",$2,$4,$3,$5,$6}' /etc/turidatunnel/users.tsv
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
  QUOTA="${5:-}"; MAXIP="${6:-}"
  if [[ -z "$QUOTA" ]]; then read -rp 'Quota GB (0=unlimited): ' QUOTA; fi
  if [[ -z "$MAXIP" ]]; then read -rp 'Maksimal IP bersamaan: ' MAXIP; fi
  add_user "$PROTO" "$USER_NAME" "$DAYS" "$QUOTA" "$MAXIP"
else
  delete_user "$PROTO" "$USER_NAME"
fi
