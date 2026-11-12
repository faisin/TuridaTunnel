#!/usr/bin/env bash
set -Eeuo pipefail

# TuridaTunnel SSH module: OpenSSH owns 22; Dropbear owns 109 and 143.
# All listeners bind explicitly and never use 80/443 (reserved for Nginx/HAProxy).
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
. /etc/os-release
case "${ID}:${VERSION_ID}" in
  debian:12|debian:13|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) ;;
  *) echo "Unsupported OS: ${PRETTY_NAME:-unknown}" >&2; exit 1 ;;
esac
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openssh-server dropbear-bin iproute2

# Preserve existing SSH security settings; do not replace the whole config.
install -d -m 0755 /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/60-turidatunnel.conf <<'SSH'
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
AllowTcpForwarding yes
X11Forwarding yes
SSH
sshd -t
systemctl enable ssh
systemctl restart ssh

# Disable distro Dropbear service to prevent duplicate listeners.
systemctl disable --now dropbear 2>/dev/null || true
# Generate persistent host keys before systemd starts Dropbear. This fixes the
# observed fresh-install failure: "No hostkeys available".
install -d -m 0700 /etc/dropbear
for key_type in rsa ecdsa ed25519; do
  key_file="/etc/dropbear/dropbear_${key_type}_host_key"
  if [[ ! -s "$key_file" ]]; then
    dropbearkey -t "$key_type" -f "$key_file"
  fi
  chmod 0600 "$key_file"
done
cat >/etc/systemd/system/turidatunnel-dropbear.service <<'UNIT'
[Unit]
Description=TuridaTunnel Dropbear SSH service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/sbin/dropbear -F -E -R -p 109 -p 143
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
# Debian package path can differ on architecture/release.
if [[ ! -x /usr/sbin/dropbear ]]; then
  DROPBEAR_BIN="$(command -v dropbear || true)"
  [[ -n "$DROPBEAR_BIN" ]] || { echo 'Dropbear binary not found after package install.' >&2; exit 1; }
  sed -i "s#^ExecStart=.*#ExecStart=${DROPBEAR_BIN} -F -E -p 109 -p 143#" /etc/systemd/system/turidatunnel-dropbear.service
fi
systemctl daemon-reload
systemctl reset-failed turidatunnel-dropbear.service 2>/dev/null || true
systemctl enable --now turidatunnel-dropbear.service
systemctl is-active --quiet turidatunnel-dropbear.service || { journalctl -u turidatunnel-dropbear -n 40 --no-pager; exit 1; }

# Python 3 WebSocket relay: Nginx :80 / HAProxy :443 -> local :2082 -> Dropbear :109.
BASE_DIR="$(dirname "$(readlink -f "$0")")"
install -d -m 0755 /usr/local/lib/turidatunnel
install -m 0755 "$BASE_DIR/modules/ssh-ws-relay.py" /usr/local/lib/turidatunnel/ssh-ws-relay.py
cat >/etc/systemd/system/turidatunnel-ssh-ws.service <<'UNIT'
[Unit]
Description=TuridaTunnel SSH WebSocket relay
After=network-online.target turidatunnel-dropbear.service
Wants=network-online.target
Requires=turidatunnel-dropbear.service
[Service]
User=www-data
Group=www-data
ExecStart=/usr/bin/python3 /usr/local/lib/turidatunnel/ssh-ws-relay.py --listen 127.0.0.1 --port 2082 --target 127.0.0.1 --target-port 109
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now turidatunnel-ssh-ws.service

# BadVPN UDP gateway binary is bundled for amd64 only; other architectures skip safely.
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64)
    BIN_DIR="$(dirname "$(readlink -f "$0")")/bin/amd64"
    (cd "$BIN_DIR" && sha256sum -c newudpgw.sha256)
    install -D -m 0755 "$BIN_DIR/newudpgw" /usr/local/bin/badvpn-udpgw
    cat >/etc/systemd/system/turidatunnel-badvpn.service <<'UNIT'
[Unit]
Description=TuridaTunnel BadVPN UDP Gateway
After=network-online.target
Wants=network-online.target
[Service]
User=nobody
Group=nogroup
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 500
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now turidatunnel-badvpn.service
    ;;
  *) echo "BadVPN binary belum dibundel untuk ${ARCH}; modul SSH tetap aktif." ;;
esac

printf '\nSSH module ready. OpenSSH :22; Dropbear :109/:143; SSH-WS via Nginx /ssh; BadVPN localhost:7300 (amd64).\n'
