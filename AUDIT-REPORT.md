# TuridaTunnel — laporan rekonstruksi modul

## Arsitektur port final

```text
Internet
  TCP/80  -> Nginx HTTP
              ├─ WS -> Xray loopback inbounds
              └─ gRPC -> Xray loopback inbounds

  TCP/443 -> HAProxy TCP passthrough
              -> 127.0.0.1:9443 Nginx TLS
                   ├─ WS -> Xray loopback inbounds
                   └─ gRPC -> Xray loopback inbounds

  TCP/22  -> OpenSSH
  TCP/109 -> Dropbear
  TCP/143 -> Dropbear
  WS `/ssh` -> Nginx -> Python 3 relay loopback :2082 -> Dropbear :109
  UDPGW   -> 127.0.0.1:7300 (amd64)
```

Tidak ada modul aktif yang mengambil port publik 80/443 selain Nginx/HAProxy sesuai pembagian di atas. Nginx TLS hanya bind ke loopback 127.0.0.1:9443.

## Perubahan utama

1. `setup.sh` menjadi installer utama: validasi OS, instal dependensi, clone repo publik, simpan domain lokal, pasang symlink command, pasang SSH, Xray, cron expiry, dan audit port.
2. `ins-xray.sh` direkonstruksi: unduh Xray resmi sesuai arsitektur, buat sertifikat melalui Certbot webroot, buat konfigurasi Xray JSON valid tanpa marker komentar, buat Nginx WS/gRPC routing, dan konfigurasi HAProxy.
3. Xray menyediakan inbound VLESS, VMess, Trojan, dan Shadowsocks untuk WS serta gRPC. Semua inbound hanya bind pada 127.0.0.1 dengan port acak yang disimpan di `/etc/turidatunnel/xray.env`.
4. `modules/account-manager.sh` mengelola tambah/hapus/daftar akun dengan `jq`, mencatat masa aktif pada `/etc/turidatunnel/users.tsv`, memvalidasi config sebelum reload, dan menghasilkan parameter koneksi.
5. `modules/protocol-menu.sh` menyediakan menu akun per protokol; wrapper `add-*` dan `menu-*` diarahkan ke manager tunggal.
6. `modules/expire-users.sh` menghapus akun kedaluwarsa melalui cron harian.
7. `ssh-vpn.sh`/`ssh-vpn2.sh` memasang OpenSSH :22, Dropbear :109/:143, SSH WebSocket relay Python 3 lokal :2082, serta BadVPN lokal :7300 pada amd64. Tidak lagi menggunakan Python 2 atau custom Stunnel.
8. Binary BadVPN amd64 disertakan di `bin/amd64/newudpgw` bersama SHA-256. Arsitektur lain melewati BadVPN dengan aman.
9. `restart.sh`, `menu.sh`, `menu4.sh`, `running.sh`, dan status service disesuaikan dengan service systemd baru; HAProxy ditampilkan sebagai service terpisah.
10. Backup/restore menjadi lokal dan tidak menyalin `/etc/shadow`, `/etc/passwd`, atau kredensial sistem.
11. BBR hanya mengaktifkan BBR bawaan kernel jika tersedia; tidak mengunduh kernel pihak ketiga.
12. vnStat dipasang dari repositori OS; integrasi Cloudflare, GitHub backup, dan Telegram bot dinonaktifkan tanpa kredensial.
13. File OAuth `rclone.conf`, arsip Stunnel lama, skrip Python 2, binary speedtest amd64 yang tidak dipakai, dan file konfigurasi lama yang tidak lagi digunakan dikeluarkan dari paket.
14. `ram.sh` yang sebenarnya Python diperbaiki menjadi `ram.py` dengan Python 3.
15. `.gitignore` ditambahkan untuk menghindari commit key, token, file runtime, backup, dan log.

## Target OS

Installer memvalidasi Debian 12/13 dan Ubuntu 22.04/24.04/26.04. Pengujian statis Bash dan Python berhasil. Nginx test untuk bentuk konfigurasi internal berhasil pada Debian 13; directive `listen ... http2` masih kompatibel pada Nginx lama, tetapi dapat memberi peringatan deprecated pada versi baru.

## Batasan / perlu diuji di VPS staging

- Belum dilakukan instalasi runtime penuh pada kelima image OS. Ubuntu 26.04 perlu diuji pada image rilis dan repositori paket final.
- Binary BadVPN yang disertakan hanya amd64. Xray dipilih sesuai amd64/arm64/armhf dari rilis resmi.
- Jika DNS belum mengarah ke VPS atau HTTP port 80 tidak dapat dijangkau, Certbot gagal dan installer membuat sertifikat self-signed sementara. TLS klien publik tidak akan mempercayai sertifikat sementara tersebut.
- Shadowsocks WS/gRPC dan semua format URI perlu diuji dengan aplikasi klien yang benar-benar dipakai.
- Modul menu historis di luar jalur instalasi utama masih perlu pengujian fungsional satu per satu; menu SOCKS dinonaktifkan agar tidak menulis inbound yang tidak tersedia.
- Pastikan repositori `faisin/turidatunnel` di GitHub berstatus Public sebelum menjalankan installer publik.

## Tindakan keamanan penting

Paket terbaru tidak berisi token OAuth lama. Namun file `rclone.conf` sebelumnya pernah memuat access token dan refresh token. Cabut/revoke token tersebut pada penyedia Google/Drive terkait. Penghapusan file dari paket baru tidak menghapus salinan dari riwayat Git, ZIP lama, atau perangkat lain.
