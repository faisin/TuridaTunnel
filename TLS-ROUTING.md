# TuridaTunnel TLS routing

## DNS prerequisites

Create both records pointing to this VPS before ACME issuance:

- `sop.adyersasak.my.id` A/AAAA -> VPS public IP (Xray HTTPS endpoint)
- `ssh.sop.adyersasak.my.id` A/AAAA -> VPS public IP (native SSH-over-TLS endpoint)

The SSH TLS endpoint uses a dedicated SNI name because HAProxy TCP passthrough cannot route encrypted HTTP paths before TLS termination. A single SNI hostname cannot reliably distinguish arbitrary HTTPS/Xray traffic from raw SSH-over-TLS.

## Traffic flow

- Public TCP/80: Nginx HTTP. `/ssh` -> WebSocket relay -> Dropbear `127.0.0.1:109`; Xray WS/HTTPUpgrade/gRPC paths -> their loopback Xray inbounds.
- Public TCP/443: HAProxy TCP/TLS SNI router (TLS passthrough). `ssh.sop.adyersasak.my.id` -> stunnel `127.0.0.1:8443` -> Dropbear `127.0.0.1:109`. Main domain -> Nginx TLS `127.0.0.1:9443` -> Xray loopback inbounds.
- OpenSSH remains on TCP/22; Dropbear also listens directly on TCP/109 and TCP/143.

HAProxy owns the public 443 socket and routes TLS by SNI. TLS is terminated by stunnel for the SSH SNI and by Nginx for the main domain. This is TLS passthrough at HAProxy, not TLS termination there.

## ACME

`modules/acme-manager.sh` supports `webroot` (default) and `standalone`. Both issue one SAN certificate for the main domain and `ssh.<domain>`. Standalone temporarily stops Nginx because it needs public port 80. Renewals use acme.sh cron and a deploy hook to refresh Nginx and stunnel certificate files.

Commands after install:

```bash
turidatunnel-acme webroot
turidatunnel-acme standalone
turidatunnel-acme renew
```
