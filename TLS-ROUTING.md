# TuridaTunnel TLS routing

## DNS prerequisite

Create one DNS record pointing to this VPS:

- `sop.adyersasak.my.id` A/AAAA -> VPS public IP

The same hostname is used for Xray TLS and SSH-over-TLS. No `ssh.<domain>` DNS record or second certificate name is required.

## Traffic flow

- Public TCP/80: Nginx HTTP. `/ssh` -> WebSocket relay -> Dropbear `127.0.0.1:109`; Xray WS/HTTPUpgrade/gRPC paths -> their loopback Xray inbounds.
- Public TCP/443: HAProxy TCP passthrough -> Nginx TLS `127.0.0.1:9443` -> Xray loopback inbounds.
- Public TCP/8443: HAProxy TCP passthrough -> stunnel `127.0.0.1:9444` -> Dropbear `127.0.0.1:109`. SSH TLS clients use the same domain with port `8443`.
- OpenSSH remains on TCP/22; Dropbear also listens directly on TCP/109 and TCP/143.

Separate ports distinguish the two encrypted services because the same SNI hostname on the same TCP port cannot reliably distinguish arbitrary HTTPS/Xray traffic from raw SSH-over-TLS. HAProxy does not terminate TLS; Nginx and stunnel do.

## ACME

`modules/acme-manager.sh` issues one certificate for the main domain only, using `webroot` (default) or `standalone`. Standalone temporarily stops Nginx because it needs public port 80. Renewals use acme.sh cron and a deploy hook to refresh Nginx and stunnel certificate files.

Commands after install:

```bash
turidatunnel-acme webroot
turidatunnel-acme standalone
turidatunnel-acme renew
```
