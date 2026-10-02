# Perbaikan login dan backend

## Akar masalah

- Supabase memakai Site URL `http://localhost:3000`. Allowlist tidak memuat `id.danarapi.app://auth/callback`, meskipun iOS sudah mengirim redirect yang benar.
- Empat fungsi Edge belum terdeploy. Browser gagal melakukan preflight sebelum request data, lalu menampilkan `Failed to fetch`.
- Schema awal sudah dijalankan manual melalui SQL Editor, tetapi riwayat migrations CLI belum tersedia.
- Insert anggaran, draft, lampiran dan aturan merchant tidak mengirim `user_id`; kolom belum memiliki default dari sesi. Validasi kategori anggaran gagal sebelum data tersimpan.
- iOS mengirim bulan anggaran sebagai `YYYY-MM`, sedangkan backend hanya membentuk tanggal dengan benar dari format web `YYYY-MM-01`. Keduanya sekarang dinormalisasi menjadi tanggal awal bulan yang sama.
- Penyelesaian cache scan mengembalikan HTTP 204. Wrapper RPC selalu membaca JSON sehingga hasil AI yang sudah berhasil dianggap gagal. Kesalahan JSON pada tahap server juga salah dikategorikan sebagai gambar tidak valid.

## Konfigurasi aktif

- Proyek: `zoccosfjulasqxczhvfm`.
- Site URL: `https://danarapi.vercel.app/`, setelah situs Danarapi diverifikasi aktif.
- Redirect URLs: URL produksi, `http://localhost:5173/`, `http://127.0.0.1:5173/`, `id.danarapi.app://auth/callback`.
- Functions: `ledger`, `ios-data`, `export-data`, `receipt-scan`; JWT tetap wajib.
- CORS: origin Vercel dan dua origin lokal; tidak menggunakan wildcard.
- Secret penyedia AI hanya tersimpan di server. Publishable key tetap khusus klien, bukan kredensial admin.

## Database

Audit membandingkan 646 komponen schema terhadap 14 migrations: fungsi, kolom, constraints, policies, triggers, indexes dan views. Perbedaan format alias PostgreSQL 15/17 serta RLS cache yang lebih ketat dipertahankan. Riwayat migrations manual kemudian dicatat tanpa menjalankan ulang SQL awal.

- Migration 15 mengunci akses anonim pada view progres target dan application RPC. Hak authenticated yang sudah ada tetap berlaku.
- Migration 16 menetapkan `auth.uid()` sebagai default pemilik untuk `review_items`, `attachments`, `merchant_rules` dan `budgets`. RLS serta validasi lintas pemilik tetap aktif.
- Tidak menjalankan seed, reset, penghapusan saldo atau penggantian data akun pengguna.

## Perubahan klien dan scan

- Web/iOS membedakan data belum dimuat dari saldo nol yang benar. Fetch gagal pertama kali menampilkan aksi coba lagi/keluar, bukan dashboard kosong seolah berhasil.
- Web mempertahankan error pemuatan saat navigasi, menjaga state terhadap pergantian sesi, dan membedakan mutasi berhasil dari refresh yang gagal.
- iOS hanya menerbitkan dashboard setelah snapshot dan laporan berhasil, atau memakai cache pemilik yang sesuai saat offline.
- RPC scan menerima 204/body kosong; error server tidak lagi dilabeli error gambar. Diagnostik hanya mencatat tahap dan ID request, tanpa foto, OCR, token atau API key.
- Pembaca HTTP menyalin setiap chunk untuk menjaga payload ketika buffer jaringan digunakan ulang.

## Bukti dan batas pengujian

- Uji cloud memakai akun sintetis sementara: fetch akun baru, insert transaksi, saldo, idempotensi, target, anggaran, laporan, update/hapus transaksi sintetis dan ekspor ZIP lolos.
- Scan AI cloud struk sintetis lolos: total Rp 23.000, qty 2. Akun uji serta datanya dibersihkan setelah setiap percobaan.
- Build simulator iOS berhasil. Build terbaru dipasang pada iPhone tersambung; 13 unit test transport/PKCE lolos. Ini bukan bukti login Google interaktif pengguna sudah selesai.
- Skenario backend tidak tersedia, network gagal, retry dan logout lolos pada Chromium/WebKit. Firefox lokal gagal membuat profil sebelum tes berjalan; tidak dinyatakan lolos.
- Regresi HTTP 204 scan dan buffer HTTP dipastikan gagal sebelum perbaikan, kemudian lolos.

Tutup browser login lama di iPhone lalu ulangi Google. Muat ulang web. Untuk deployment berikutnya gunakan CLI; jangan ulang SQL migrations yang sudah tercatat. Perubahan sumber UI web tetap memerlukan commit/push dan deployment Vercel terpisah; perubahan hosted Auth, database dan Edge Functions sudah aktif.

```sh
npm run cloud:check -- --origin https://danarapi.vercel.app
npm run cloud:check -- --origin http://localhost:5173
npm run cloud:plan -- https://danarapi.vercel.app
```
