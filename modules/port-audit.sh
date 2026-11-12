#!/usr/bin/env bash
set -Eeuo pipefail

fail=0
assert_not_process(){
  local port="$1" forbidden="$2" label="$3" output
  output="$(ss -H -lntp "sport = :${port}" 2>/dev/null || true)"
  if [[ "$output" == *"${forbidden}"* ]]; then
    printf '[FAIL] %s: proses %s juga mengikat port %s: %s\n' "$label" "$forbidden" "$port" "$output"
    fail=1
  fi
}
check_listener(){
  local port="$1" expected="$2" label="$3" output
  output="$(ss -H -lntp "sport = :${port}" 2>/dev/null || true)"
  if [[ -z "$output" ]]; then
    printf '[WARN] %-18s port %s belum listen (modul belum aktif?)\n' "$label" "$port"
    return 0
  fi
  if [[ "$output" == *"${expected}"* ]]; then
    printf '[ OK ] %-18s port %s\n' "$label" "$port"
  else
    printf '[FAIL] %-18s port %s dipakai proses lain: %s\n' "$label" "$port" "$output"
    fail=1
  fi
}
check_listener 80 nginx 'Nginx HTTP'
check_listener 443 haproxy 'HAProxy TLS'
check_listener 9443 nginx 'Nginx TLS internal'
check_listener 22 sshd 'OpenSSH'
check_listener 109 dropbear 'Dropbear 109'
check_listener 143 dropbear 'Dropbear 143'
check_listener 2082 python3 'SSH-WS relay'
assert_not_process 80 haproxy 'Nginx public HTTP'
assert_not_process 443 nginx 'HAProxy public TLS'
if ss -H -lnt 'sport = :9443' 2>/dev/null | grep -E '0\.0\.0\.0:9443|\*:9443|\[::\]:9443' >/dev/null; then
  echo '[FAIL] Nginx TLS backend :9443 harus bind ke 127.0.0.1 saja.'
  fail=1
fi
# Ensure public web ports are not claimed by legacy stunnel/xray listeners.
if ss -H -lntp 'sport = :80 or sport = :443' | grep -E 'stunnel|xray|dropbear' >/dev/null; then
  echo '[FAIL] Ditemukan service legacy mengambil port publik 80/443.'
  fail=1
fi
exit "$fail"
