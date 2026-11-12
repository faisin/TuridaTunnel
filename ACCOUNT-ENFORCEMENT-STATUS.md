# Account management / enforcement status

This revision adds a shared account registry (`/etc/turidatunnel/users.tsv`) and a unified account-center entry point (`turidatunnel-accounts`). SSH account creation provisions a Linux account used by both OpenSSH and Dropbear/SSH-WS; SSH deletion and expiry remove that account. PAM `maxlogins` is configured for PAM-backed sshd/Dropbear authentication.

Important enforcement boundaries (do not advertise as fully implemented):

* SSH quota is stored as policy metadata only. This package does not yet meter per-user ingress+egress bytes or block an SSH account exactly at its quota.
* PAM `maxlogins` limits concurrent logins/sessions, not unique source IP addresses. Dropbear must be PAM-enabled for the same rule to apply there.
* Xray quota/IP controller remains based on Xray Stats API and access-log rolling IP leases, not an exact live-socket IP counter. It should be treated as best-effort until tested against the exact packaged Xray build and client traffic.
* Xray users and SSH users share the registry format but still use protocol-specific credential stores; they are not one interchangeable credential across protocols.

Do not call quota or unique-IP enforcement production-ready until packet accounting and live connection tests are completed.
