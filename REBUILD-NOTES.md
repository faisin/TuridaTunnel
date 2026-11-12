# Rebuild notes — unified account center revision

Changes in this revision:
- Added `modules/unified-account-manager.sh` and command `turidatunnel-accounts`.
- Added menu option 23 to open the unified account center.
- SSH account creation provisions one Linux account shared by OpenSSH, Dropbear, and the existing SSH-WS relay; account deletion removes it.
- SSH account records use the same `/etc/turidatunnel/users.tsv` registry format as Xray records.
- SSH expiry is handled by the expiry job and dispatched to the SSH account deleter.
- PAM `maxlogins` policy is written for SSH users, with PAM limits session hooks added to sshd/Dropbear PAM files where present.
- Installer initializes the shared registry and installs the unified account-center command.

Important limitations:
- SSH quota is stored but is NOT byte-metered or enforced in this revision.
- SSH maxlogins is a concurrent-login/session ceiling, not a unique-source-IP ceiling. Dropbear enforcement depends on its build using PAM.
- Xray's existing quota/IP controller is retained; its rolling access-log lease logic is not exact live-socket IP enforcement.
- SSH and Xray credentials remain protocol-specific. Shared registry means shared lifecycle metadata, not one password/UUID usable across every protocol.

Static checks performed:
- `bash -n` on every shell script.
- Python bytecode compilation on enforcement and SSH relay modules.

Not performed: fresh VPS installation, client connection tests, live quota exhaustion tests, or multi-IP concurrency tests. Do not treat the remaining quota/IP limitations as production-ready.
