# Danarapi Web R1

Vue 3 + TypeScript + Vite, UI mandiri: sidebar desktop, navigasi bawah ponsel, tema Sistem/Terang/Gelap. Bahasa Indonesia, Rupiah integer/string desimal, periode sesuai zona waktu pilihan. PostgreSQL/RPC tetap otoritas finansial akun nyata.

## Menjalankan

```sh
npm ci --prefix apps/web
npm run web:dev
```

Buka `http://127.0.0.1:5173`, pilih **Coba Demo**. Demo tidak memerlukan akun atau server. Fixture `tests/fixtures/demo-seed-v1.json` menyediakan 200 transaksi sintetis tiga bulan; perubahan hanya di memori sampai reload/reset/keluar. Tidak memakai localStorage untuk data keuangan.

Konfigurasi publik Supabase sudah tersedia di `src/cloud.ts`; override opsional melalui `VITE_SUPABASE_URL` dan `VITE_SUPABASE_PUBLISHABLE_KEY` dalam `.env.local` root (`VITE_SUPABASE_ANON_KEY` tetap didukung). Akun nyata memakai Google, seluruh migrations dan fungsi `ledger`, `ios-data`, `export-data`, `receipt-scan`. Atur provider, redirect aplikasi dan `ALLOWED_ORIGINS` sesuai `docs/supabase-cloud-setup.md`. Akun baru memperoleh Tunai; saldo awal opsional melalui Pengaturan → Akun.

## Cakupan

- Login Google dengan PKCE, refresh/logout; sesi Supabase JS memakai `sessionStorage` dengan key `danarapi.auth`, bukan default localStorage. Bukan jaminan setara Keychain; menutup tab tidak otomatis mencabut token server.
- CRUD akun/kategori, arsip, urutan, aturan merchant; transaksi dan transfer; penghapusan/Urungkan 10 detik; pencarian/filter gabungan dan CSV tampilan.
- Split bill sama rata, nominal, persentase; pembayar Saya/teman, pelunasan sebagian, overpay, reversal beralasan, penghapusan kewajiban nonkas, konversi transaksi/review atomik, salin ringkasan.
- JPEG/PNG QR, PDF berlapis teks, tempel teks, ekstraksi berindikator keyakinan/evidence, deduplikasi hash sumber/kandidat; Perlu Ditinjau, koreksi/konfirmasi, Tolak/Urungkan, Gabung bukti. Gambar dibersihkan dari metadata sebelum upload. HEIC harus dikonversi oleh pengguna ke JPEG/PNG; tidak mengklaim konversi HEIC otomatis.
- Anggaran bulanan, laporan bulan/tahun, kategori, arus kas per akun, tren tiga bulan, piutang/utang/posisi bersih, enam CSV sesuai periode, ZIP penuh dengan manifest/checksum/lampiran, autentikasi ulang untuk hapus akun, kebijakan privasi `/privacy` dan jalur `/hapus-akun`.

Foto/galeri/PDF struk memakai ekstraksi AI server setelah login dan masuk draft rincian; hasil harus ditinjau sebelum posting. QRIS menjadi pengeluaran hanya setelah konfirmasi akun dan nominal, bukan pembayaran oleh aplikasi. Target, anggaran dan laporan memakai ledger yang sama. Sinkron/outbox web offline belum tersedia. Detail transaksi manual dan split bill menyediakan unggah/pratinjau lampiran tanpa mengubah ledger; hasil impor yang dikonfirmasi mempertahankan tautan lampiran.

Perlu Ditinjau pada Demo menyediakan tombol contoh PDF/QRIS sintetis. Aset lokal `public/demo` dibuat dari fixture bersama; regenerasi: `node apps/web/scripts/generate-import-samples.mjs`. PDF.js/jsQR dimuat saat impor, bukan pada halaman awal.

## Kontrak dan batas

Adapter menggunakan gateway yang sama dengan iOS. Transaksi diambil dengan keyset backend `(occurred_at,id)`, 30 per respons; untuk filter gabungan, laporan lokal, dan CSV yang konsisten, web R1 memprefetch snapshot lengkap lalu menampilkan halaman keyset lokal 30 item. Ini bukan delta sync atau optimasi dataset besar. Laporan pribadi akun nyata memakai query server `ios-data/report`; transaksi/bill/kejadian yang sama dipakai untuk arus kas. Setiap mutasi ledger mempertahankan UUID retry sampai server berhasil. Konflik versi menampilkan pesan, tidak menimpa data diam-diam.

Anggaran mengikuti zona waktu profil server; preferensi zona waktu disimpan pada profil akun nyata dan lokal untuk Demo. Ekspor penuh server dibatasi total lampiran 50 MB dan gagal eksplisit bila melewati batas; tidak mengunduh arsip parsial sebagai berhasil.

Token v1.1 dari `contracts/design-tokens.json` dipakai langsung, termasuk palet dan radius. Keputusan putih/navy/biru pada `docs/product-update-planning.md` menggantikan baseline warna lama PRD; referensi keputusan kini ada di §6.2. Font variable Latin dan OFL berada di `public/fonts`/`public/licenses`; ikon Lucide memakai ISC. Tidak ada font CDN runtime.

## Keamanan

`index.html` menetapkan CSP untuk pengembangan; `vercel.json` menyediakan CSP/header produksi, larangan kamera/mikrofon, serta route publik. Ganti allowlist `connect-src` jika memakai host Supabase khusus; jangan melonggarkan `script-src`. Render teks melalui interpolasi Vue, tanpa `v-html`. PDF/QR diproses lokal dengan batas ukuran/halaman; PDF.js diperbarui ke rilis aman dari audit npm. Font, worker, dan parser disajikan dari origin sendiri. Tidak ada deployment yang dilakukan dalam pekerjaan ini.

Retensi otomatis tinjauan 30/90 hari, backup produksi, kanal dukungan, SMTP, pemulihan sesi nyata, dan penghapusan Storage produksi tetap gerbang publikasi; kebijakan privasi menjelaskan status sebenarnya.

## Pengujian

```sh
npm run check:web
cd apps/web && npx playwright install chromium && cd ../..
npm run web:e2e
npm run test:edge
npm run test:swift
sh tests/database/plain-postgres.sh
```

Lint/typecheck/build dan 33 tes kontrak/domain lulus. Lanjutan menambah E2E WebKit, lampiran posted dan snapshot 50.000 transaksi; 15 tes gateway/retensi mock; paritas enam CSV web/server/Swift pada 12 periode/timezone; sepuluh migrasi dan round-trip backup data sintetis. Hasil akhir: `docs/web-r1-continuation.md` serta `apps/web/artifacts/verification`. Screenshot multi-engine dan manifest SHA-256: `apps/web/artifacts/visual`; HTML report/trace diabaikan Git. Firefox gagal meluncurkan profil pada host ini. WebKit bukan Safari perangkat asli. Uji otomatis 20 input/10 split bukan pengganti uji kegunaan manusia. R1 akun nyata belum dinyatakan selesai.

Perintah tambahan dari root: `npm run test:export:parity`, `npm run test:web:performance`. Jalankan suite Playwright berurutan dalam satu proses, bukan dua proses yang berbagi `test-results` dan Vite server.

Retensi backend diimplementasikan tetapi belum diterapkan/dijadwalkan produksi: ditolak 30 hari, pending 90 hari hanya setelah penerimaan kebijakan tercatat dengan tenggang 7 hari. UI privasi mencatat penerimaan pada server; endpoint operator membutuhkan `RETENTION_JOB_SECRET`. Jangan menaruh secret ini pada `VITE_*`. Aktivasi penghapusan produksi memerlukan persetujuan operator tersendiri. `VITE_SUPPORT_EMAIL` hanya diisi setelah alamat dukungan nyata ditetapkan. Backup/restore yang diuji mencakup database sintetis, bukan Storage/backup penyedia produksi.
