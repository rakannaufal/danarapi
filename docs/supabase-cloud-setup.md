# Supabase cloud — web dan iOS

## Verifikasi 2 Oktober 2026

Proyek sudah memiliki migrasi 1–20, provider Google aktif, dan lima fungsi aplikasi. Uji akun sintetis membuktikan fetch, penyimpanan transaksi, saldo, target, anggaran, laporan, konflik edit dan ekspor. Scan AI struk sintetis menghasilkan total Rp 23.000 dan qty 2. Login Google pengguna, foto struk nyata, jaringan seluler dan rollout penegakan persetujuan AI tetap belum diselesaikan. Hasil terbaru serta gerbang rilis: `docs/production-readiness.md`.

## Riwayat pemeriksaan awal — 1 Oktober 2026

- Klien web dan iOS menggunakan proyek `zoccosfjulasqxczhvfm` melalui HTTPS dan publishable key yang diberikan. Key ini adalah konfigurasi publik, bukan akses administrator.
- Supabase Auth merespons. Provider Google masih nonaktif pada pemeriksaan awal; status terbaru diperiksa melalui `npm run cloud:check`.
- Tabel aplikasi belum tersedia. Empat fungsi aplikasi (`ledger`, `ios-data`, `export-data`, `receipt-scan`) masih mengembalikan `404 NOT_FOUND`.
- Key AI yang telah tersimpan di konfigurasi server berhasil mengakses daftar model. Model yang dipilih, `gemini-3.5-flash-lite`, tersedia dan mendukung `generateContent`.
- Konfigurasi klien tidak otomatis membuat database, mengaktifkan provider, atau men-deploy fungsi. Login dan ekstraksi produksi belum dinyatakan berhasil.

## 1. Akses deployment

Di terminal proyek, dengan Node.js 22+:

```sh
npx --yes supabase@2.119.0 login
```

Gunakan akun Supabase yang memiliki akses ke proyek ini. Selesaikan autentikasi melalui browser/terminal milik sendiri. Jangan kirim access token, password database, client secret OAuth, key AI, atau service-role key ke chat.

CLI dapat meminta password database ketika menghubungkan proyek. Gunakan prompt CLI; jangan menaruhnya dalam command line atau source code. `SUPABASE_ACCESS_TOKEN` dan `SUPABASE_DB_PASSWORD` boleh disediakan lewat secret manager CI.

## 2. Database: gunakan migrations yang sudah ada

Untuk proyek baru, gunakan **seluruh 20 file dalam `supabase/migrations` sesuai urutan nama**, dari `202609300001_core_schema.sql` sampai `202610020020_product_access_hardening.sql`. Migrasi membuat tabel, RLS, Storage privat, RPC ledger, rincian split bill, cache/kuota scan, target, QRIS, persetujuan AI, tiket bantuan, zona waktu, riwayat target/anggaran dan penolakan akses anonim. Jangan memasukkan fixture atau seed ke produksi.

Proyek `zoccosfjulasqxczhvfm` sudah memiliki migrations 1–20; migrasi 18–20 diterapkan pada 2 Oktober 2026 melalui CLI tanpa seed atau reset. Jangan menyalin ulang SQL awal ke proyek ini. Verifikasi riwayat remote dengan CLI sebelum deployment berikutnya.

Disarankan CLI karena menyimpan riwayat migration dan hanya menjalankan file yang belum diterapkan. Tidak perlu menyalin tes ke database. Jangan menggunakan `db reset`, `--include-seed`, `supabase/seed.sql`, `supabase/tests/*.sql`, atau bootstrap `tests/database` pada produksi: berkas tersebut digunakan untuk database pengujian dan fixture sintetis.

Alternatif SQL Editor hanya jika CLI belum dapat dipakai: jalankan setiap migration satu per satu, paling lama dahulu, pada proyek yang benar. Jangan menjalankan ulang file yang sudah berhasil. Deployment CLI berikutnya perlu menyelaraskan riwayat migration dengan status database; jangan menandai migration selesai sebelum SQL-nya benar-benar diterapkan.

## 3. Secret scan dan deployment backend

Konfigurasi server berada pada `supabase/.env`, bukan variabel `VITE_*` atau konfigurasi iOS. File yang sudah ada dipakai tanpa menampilkan key. Untuk workspace baru, salin `supabase/.env.example` ke `supabase/.env` dan isi `GEMINI_API_KEY` secara lokal.

```sh
npm run cloud:plan
npm run cloud:deploy
npm run cloud:check
```

- `cloud:plan`: validasi akses model dan batas scan, hubungkan proyek, tampilkan migration yang akan diterapkan. Tidak mengubah database, secret cloud, atau fungsi. Metadata koneksi CLI lokal tetap dibuat.
- `cloud:deploy`: jalankan migrations yang belum diterapkan, kirim hanya secret scan/CORS yang diizinkan, deploy lima fungsi (ledger, ios-data, export-data, product-info, receipt-scan), periksa backend. Tidak menjalankan seed, reset, tes akun, atau menghapus fungsi lain. Pastikan web dan iOS mendukung persetujuan AI sebelum mengaktifkan penegakan scan; klien lama perlu diperbarui.
- Secret sementara berizin `0600`, dihapus setelah command selesai. Key AI tidak dicetak; konfigurasi `SUPABASE_*` server bawaan tidak ditimpa.
- JWT verification tetap aktif. Scan juga memvalidasi sesi ke Supabase Auth sebelum parsing gambar, pemakaian kuota, atau panggilan AI. Publishable key dikirim sebagai `apikey`; `Authorization` berisi access token pengguna, bukan publishable key.
- Kuota default: 50 scan/pengguna/hari, jeda panggilan model 4 detik. Cache per pengguna dan pembatasan retry mengikuti implementasi existing. Kuota penyedia/billing tetap berlaku.

Jika web telah memiliki domain produksi, gunakan **origin yang sebenarnya**, misalnya dengan mengganti placeholder berikut:

```sh
npm run cloud:plan -- https://DOMAIN_WEB_ANDA
npm run cloud:deploy -- https://DOMAIN_WEB_ANDA
```

Origin default untuk pengembangan adalah `http://127.0.0.1:5173`; `http://localhost:5173` juga diizinkan. Domain web bukan alamat Supabase. Jangan menggunakan `*` pada allowlist. iOS tidak bergantung pada origin browser atau server Mac.

`cloud:check` sengaja keluar dengan status gagal jika provider, schema, atau fungsi belum siap. Keberhasilan `cloud:deploy` tidak membuktikan OAuth/scan AI end-to-end: backend check tidak mengunggah gambar atau mengautentikasi pengguna.

## 4. Google

Supabase Dashboard → **Authentication → Sign In / Providers**:

### Google

1. Buat OAuth client jenis Web Application pada Google Cloud Console. Lengkapi consent screen, audience, dan test users bila aplikasi masih dalam testing.
2. Tambahkan redirect URI provider ini:
   `https://zoccosfjulasqxczhvfm.supabase.co/auth/v1/callback`
3. Isi Client ID dan Client Secret pada provider Google di Supabase; aktifkan dan simpan.
4. Jika aplikasi masih mode testing, akun pengguna harus termasuk test users. Jangan menganggap key Supabase sebagai Client Secret Google.

Login Apple tidak digunakan. Konfigurasi provider Apple tidak diperlukan untuk menjalankan aplikasi.

Klien mengecek ketersediaan provider sebelum membuka login, sehingga provider nonaktif menghasilkan pesan yang dapat dipahami, bukan halaman error mentah.

## 5. Redirect aplikasi

Dashboard → **Authentication → URL Configuration**:

- `Site URL`: URL web produksi sebenarnya. Selama pengujian lokal boleh `http://127.0.0.1:5173`.
- Redirect allowlist: `http://127.0.0.1:5173`, `http://localhost:5173`, `id.danarapi.app://auth/callback`, serta URL/path web produksi yang digunakan aplikasi.
- Callback provider Google tetap HTTPS `/auth/v1/callback` Supabase. Callback aplikasi iOS adalah URL scheme `id.danarapi.app://auth/callback`; keduanya berbeda.
- Web memakai PKCE, menukar authorization code, membersihkan callback, mempertahankan pemilik akun saat reautentikasi. iOS memakai browser sistem dan PKCE, menyimpan sesi di Keychain.
- Edit `supabase/config.toml` hanya menyiapkan Auth lokal; migrasi/deploy functions **tidak** otomatis mengubah konfigurasi Auth hosted. Atur dashboard tersebut secara eksplisit.

## 6. Build klien

Web memiliki konfigurasi publik default di `apps/web/src/cloud.ts`. Override opsional melalui `.env.local` di root:

```dotenv
VITE_SUPABASE_URL=https://zoccosfjulasqxczhvfm.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_HFNe0r92MxPPmck_SxfvdA_dwVecyjx
```

`VITE_SUPABASE_ANON_KEY` tetap didukung untuk kompatibilitas; jangan mengisi kedua nama dengan proyek berbeda. Override setengah lengkap ditolak agar URL/key proyek tidak tercampur. Build ulang web setelah mengubah environment.

iOS memiliki konfigurasi default di `apps/ios/Configuration/Base.xcconfig`. `Local.xcconfig` adalah override opsional. Nama existing `SUPABASE_ANON_KEY` menerima publishable key; `https:/$()/...` diperlukan agar xcconfig tidak memotong URL sebagai komentar. Build ulang dan install aplikasi setelah perubahan konfigurasi.

Scan default menggunakan backend Supabase, bukan bridge Mac. Kamera/galeri/PDF masuk draft; verifikasi rincian sebelum menyimpan transaksi. QRIS bukan pemrosesan pembayaran.

## 7. Pengujian

Tes diperlukan untuk verifikasi, **bukan dimasukkan ke produksi**:

```sh
npm run web:typecheck
npm run web:lint
npm run web:test
npm run web:build
npm run test:cloud
npm run test:edge
sh tests/database/plain-postgres.sh
```

Tes database menggunakan database lokal disposable. Tes cloud operations memakai mock CLI/HTTP, memverifikasi bahwa plan tidak mengubah server dan deploy tidak menjalankan seed/reset. `npm run cloud:check` memeriksa proyek nyata tanpa membuat akun, transaksi atau memanggil model untuk ekstraksi.

Setelah konfigurasi dashboard/deploy selesai:

1. Login Google pada web dan iPhone; cek pemulihan sesi dan keluar akun.
2. Buat akun keuangan, transaksi, target dan anggaran; cocokkan saldo dan laporan di kedua klien memakai akun yang sama.
3. Uji foto, galeri dan PDF pada web/iOS. Cocokkan menu, jumlah, harga, service, pajak, diskon dan total; periksa hasil largest remainder.
4. Matikan Mac, nonaktifkan Wi-Fi iPhone, gunakan seluler. Login/scan harus tetap berjalan melalui HTTPS Supabase.
5. Uji sesi kedaluwarsa, provider nonaktif, gambar tidak valid, kuota, dan gangguan jaringan. Tidak boleh menghasilkan transaksi palsu atau posting ganda.
6. Uji isolasi dua akun pada staging, bukan dengan tes penghapusan terhadap akun pengguna produksi.

Proyek ini sudah mengaktifkan Google, callback iOS, lima fungsi backend, secret scan server dan CORS untuk Vercel serta pengembangan lokal. Migrasi 1–20 sudah diterapkan. Pembaruan `ios-data`, `export-data`, dan `product-info` sudah terdeploy; penegakan persetujuan AI pada sumber `receipt-scan` menunggu rollout klien yang kompatibel. Uji akun sintetis membuktikan fetch dashboard, transaksi/idempotensi, saldo, target, anggaran, laporan, ekspor dan ekstraksi struk sintetis. Login Google akun pengguna dan foto struk nyata tetap perlu diuji ulang di perangkat. Rincian perbaikan ada di `docs/cloud-login-repair.md`; gerbang rilis dan hasil pengujian terbaru ada di `docs/production-readiness.md`.
