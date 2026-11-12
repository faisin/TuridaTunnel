# TuridaTunnel

Installer publik untuk Debian 12/13 dan Ubuntu 22.04/24.04/26.04.

## Instalasi

Pastikan repositori `faisin/turidatunnel` disetel **Public**. Jalankan sebagai root pada VPS:

```bash
apt-get update
apt-get install -y ca-certificates curl
curl -fsSL https://raw.githubusercontent.com/faisin/turidatunnel/main/setup.sh | bash
```

Installer meminta domain yang DNS A/AAAA-nya sudah mengarah ke VPS. Tidak ada registrasi IP, lisensi IP, GitHub token, Telegram bot token, atau Cloudflare API token. DNS dikelola manual oleh pemilik domain.

## Arsitektur port

```text
Internet
  TCP/80  -> Nginx HTTP -> Xray WS/gRPC loopback
  TCP/443 -> HAProxy TCP passthrough -> Nginx TLS 127.0.0.1:9443 -> Xray loopback
  TCP/22  -> OpenSSH
  TCP/109 -> Dropbear
  TCP/143 -> Dropbear
  HTTP/WebSocket path /ssh -> Nginx -> local Python 3 relay 127.0.0.1:2082 -> Dropbear :109
  UDPGW   -> 127.0.0.1:7300 (amd64)
```

Port publik 80 hanya dimiliki Nginx dan port publik 443 hanya dimiliki HAProxy. Nginx TLS bind pada loopback 9443, bukan port publik.

## Modul akun

Menu utama: `menu`.

- VMess: `menu-vmess`
- VLESS: `menu-vless`
- Trojan: `menu-trojan`
- Shadowsocks: `menu-ss`
- SSH: `menu-ssh` (OpenSSH, Dropbear, dan SSH-WS melalui path `/ssh`)
- Restart layanan: `restart`
- Audit port: `turidatunnel-port-audit`

Akun Xray dibuat/dihapus melalui `modules/account-manager.sh`; masa aktif disimpan terpisah dan diperiksa setiap hari oleh cron.

## Binary

- `bin/amd64/newudpgw`: BadVPN UDP gateway amd64, disertai SHA-256.
- Xray diunduh dari rilis resmi XTLS sesuai arsitektur.
- Nginx, HAProxy, OpenSSH, Dropbear, Certbot, dan vnStat dipasang dari repositori paket OS.

Arsitektur selain amd64 tetap memasang SSH/Xray, tetapi BadVPN dilewati sampai binary sesuai arsitektur tersedia.

## Integrasi tanpa token

Cloudflare automation, GitHub backup otomatis, dan Telegram bot dinonaktifkan. Backup/restore menggunakan arsip lokal di `/root/turidatunnel-backups`; tidak mengunggah data server ke layanan eksternal.

## Catatan sertifikat

Certbot menggunakan HTTP webroot pada port 80. Jika DNS belum benar atau port 80 tidak dapat dijangkau, installer membuat sertifikat self-signed sementara. Koneksi TLS publik memerlukan sertifikat Let's Encrypt yang valid.

## Pengujian

Pemeriksaan sintaks Bash/Python dan konfigurasi Nginx dilakukan secara statis. Instalasi runtime penuh tetap perlu diuji pada VPS staging untuk setiap target OS sebelum dipakai pada server produksi.
