# Danarapi iOS R1

Aplikasi native SwiftUI untuk iOS 17. PostgreSQL/RPC tetap sumber kebenaran finansial. Mode Demo berjalan lokal dari fixture sintetis tanpa Supabase.

## Goals, anggaran dan split per menu

- Beranda menampilkan goals terkumpul dan total anggaran bulan sekarang, menggantikan kartu utang/piutang. Saldo tetap berasal dari ledger; kewajiban tetap tersedia dalam detail tagihan.
- Goals: tambah tujuan pembelian/pencapaian, target tabungan, progres manual, deadline opsional, ubah dan hapus. Progres tidak memindahkan uang atau mengubah saldo/pengeluaran.
- Anggaran: pilih kategori pengeluaran aktif atau buat kategori baru langsung dari editor. Pilih bulan dan limit; dashboard tidak mencampur anggaran berbagai bulan.
- Laporan: navigasi bulan sebelumnya/berikutnya, rentang kalender Asia/Jakarta dengan akhir eksklusif. Grafik kategori dan selisih pemasukan–pengeluaran bukan saldo penutupan rekening.
- Split bill: menu, jumlah, harga satuan, jumlah yang dimakan tiap orang; foto/kamera/teks struk membantu mengisi draft. Semua kuantitas harus dibagikan tepat sekali, kemudian tombol Hitung menampilkan porsi per orang.
- Foto/galeri/PDF struk memakai ekstraksi AI melalui Supabase cloud setelah login. Periksa nama, jumlah, harga, total dan penyesuaian; hasil bukan transaksi otomatis. Bridge Mac hanya untuk pengujian development eksplisit. Panduan produksi: `docs/supabase-cloud-setup.md`.
- Pajak/layanan/diskon dibagi proporsional subtotal menu dengan largest remainder. Aturan yang sama diuji di PostgreSQL, Swift dan TypeScript melalui `item-split-v1.json`. Akun nyata memerlukan internet; server memvalidasi porsi sebelum posting.
- Putih–biru, permukaan ringan, kartu continuous-rounded, header compact dan angka responsif. Dark mode tetap tersedia.

Rincian keputusan produk: `docs/product-update-planning.md`. Data transaksi Demo menggunakan periode sintetis Juli–September 2026; pilih September untuk melihat laporan fixture bila bulan perangkat sudah berubah. Goal contoh tersedia lokal, bukan saldo tambahan.

## Menjalankan di Xcode

1. Gunakan macOS dengan Xcode yang mendukung iOS 17 dan selesaikan lisensi/komponen Xcode secara manual:

   ```sh
   sudo xcodebuild -license
   sudo xcodebuild -runFirstLaunch
   xcrun simctl list devices available
   ```

   Xcode 27.0 (`27A266a`) tersedia. Run penuh terbaru: XCTest aplikasi 31/31 dan UI test 7/7 lulus pada `Danarapi-R1-Verification` (iPhone 17 Pro Simulator, iOS 26.5). Runtime iOS 16.2 lama tercatat unavailable dan tidak memenuhi target minimum. Bukti terbaru ada di `docs/ios-r1-testing.md`.
2. Konfigurasi proyek cloud sudah tersedia di `Configuration/Base.xcconfig`. Salin `Configuration/Local.xcconfig.example` menjadi `Configuration/Local.xcconfig` hanya untuk override proyek.
3. Gunakan publishable/anon key publik, bukan service-role key. Login nyata memerlukan provider Google aktif, callback iOS dan backend terdeploy sesuai `docs/supabase-cloud-setup.md`.
4. Buka `Danarapi.xcodeproj`, pilih scheme `Danarapi`, lalu pilih `Danarapi-R1-Verification` atau iPhone Simulator iOS 17+ lainnya.
5. Tekan Run. Pilih **Coba Demo** untuk alur tanpa backend.

### Runner tes bukan aplikasi

Jalankan `Danarapi.app`, bukan `DanarapiAppUITests-Runner.app`. Runner hanya dipakai lewat Product → Test (⌘U) atau `xcodebuild test`; ia membutuhkan konteks peluncuran XCTest. Product → Run (⌘R) pada scheme `Danarapi` meluncurkan aplikasi sebenarnya.

Crash runner pada 30 September 2026 pukul 21:47:58 WIB mencatat `Library not loaded: @rpath/XCTest.framework/XCTest` dan berhenti sebelum kode tes berjalan. Runner yang diluncurkan melalui `xcodebuild test` pada pukul 22:35–22:37 WIB berhasil menjalankan seluruh tes. Jangan memperbaikinya dengan menyalin framework XCTest ke aplikasi produksi. Layar runner kosong bukan tampilan Beranda Danarapi.

Regenerasi proyek setelah menambah berkas Swift:

```sh
ruby apps/ios/scripts/generate_project.rb
```

## Backend akun nyata

Dari root repo:

```sh
supabase start
supabase db reset --local
supabase functions serve ledger --env-file .env.local
supabase functions serve ios-data --env-file .env.local
supabase functions serve export-data --env-file .env.local
```

Konfigurasi aplikasi menerima endpoint HTTPS. Untuk Supabase lokal, gunakan reverse proxy HTTPS dengan sertifikat yang dipercaya Simulator/perangkat, atau proyek Supabase staging. URL HTTP lokal tidak diaktifkan diam-diam dan tidak ada pengecualian ATS. Jangan memasukkan service-role key ke aplikasi.

Perubahan ini memerlukan migration `202609300008_goals_item_split.sql`. Terapkan migrasi sebelum deploy ulang `ledger`, `ios-data`, `export-data` atau menghubungkan aplikasi baru; backend lama belum menyediakan `savings_goals`/RPC menu. Pada proyek staging gunakan `supabase db push` setelah memilih proyek yang benar. Jangan memakai `supabase db reset` pada data pengguna yang perlu dipertahankan. Integrasi HTTP Supabase akun nyata belum terverifikasi di host ini.

Auth memakai adapter native `URLSession` ke API Supabase; sesi tidak diserahkan kepada penyimpanan default SDK. Gunakan template email kode `{{ .Token }}` untuk signup dan recovery agar formulir OTP enam digit dapat diuji. Batas laju tetap ditegakkan server; countdown kirim ulang 60 detik di UI bukan pengganti rate limit.

## Pengujian

```sh
npm run check:json
npm run test:contracts
npm run test:swift:fixture
npm run test:swift:typecheck
swift test --package-path apps/ios
xcodebuild -project apps/ios/Danarapi.xcodeproj -scheme Danarapi \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project apps/ios/Danarapi.xcodeproj -scheme Danarapi \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcrun simctl list devices available
xcodebuild -project apps/ios/Danarapi.xcodeproj -scheme Danarapi \
  -destination 'platform=iOS Simulator,id=<UDID dari simctl>' -parallel-testing-enabled NO test
```

`DanarapiAppTests` mencakup fixture pembulatan, QRIS/CRC, teks ambigu, aturan merchant, ledger Demo, pagination, laporan seluruh halaman, edit/lock split, konversi transaksi tanpa hitung ganda, overpay, isolasi outbox, dan ekspor ZIP. Tambahan regresi menguji skenario ledger server dari `ledger-v1.json`, draft tidak mengubah saldo, proyeksi outbox setelah reload cache, backoff/idempotensi, konflik menjadi pengeluaran baru, bigint string ketat, tanggal server pecahan detik, query Auth, OTP recovery tanpa mengganti sesi, dan refresh Keychain setelah logout.

`DanarapiAppUITests` mencakup navigasi Demo, pengeluaran, impor teks tetap draft, goal baru, kategori/anggaran baru, laporan bulanan, dan pembagian menu tiga orang. Swift 6 strict concurrency juga memeriksa source XCTest/UI test; **type-check dan build-for-testing bukan bukti eksekusi tes**. Run penuh terbaru: XCTest aplikasi 31/31, UI test 7/7, SwiftPM 4/4 dan kontrak TypeScript/Demo 33/33 lulus. Build web, pemeriksaan tiga Edge Functions dan smoke PostgreSQL sebagai role `authenticated` juga lulus. Jangan menjalankan runner UI langsung: gunakan Test (`Cmd+U`) dan biarkan ad-hoc signing Simulator aktif. Kamera, Foto, biometrik, Data Protection sidecar/migrasi, VoiceOver, Dynamic Type, Reduce Motion, performa dan integrasi Supabase akun nyata tetap perlu QA. Bukti terbaru ada di `docs/ios-r1-testing.md`.

Simulator lama tertahan pada boot layanan sistem; data tidak dihapus. Tes berhasil pada perangkat terpisah `Danarapi-R1-Verification`, UDID `B5C1D4B1-201B-4039-8CD9-0B5EB426F086`. Tema terang/gelap telah diperiksa secara visual di Simulator.

## Peluncuran iPhone dari Xcode

Run (`Cmd+R`) memakai konfigurasi Debug tanpa menempelkan LLDB. Pada iPhone pengujian, LLDB tertahan ketika membaca simbol perangkat sebelum UI tampil; menghentikan peluncuran menghasilkan `SIGKILL`. Peluncuran aplikasi tanpa debugger berhasil menampilkan UI. Ini workaround tooling Xcode, bukan perubahan data, signing, atau logika aplikasi.

Untuk breakpoint, aktifkan kembali **Product → Scheme → Edit Scheme → Run → Info → Debug executable** ketika simbol perangkat sudah siap. Test tetap memakai LLDB. Jangan menghapus aplikasi atau mereset data untuk mengatasi masalah ini.

## Alur yang tersedia

- Onboarding, Demo satu langkah, signup/OTP/kirim ulang, login, recovery OTP dan kata sandi baru, serta login ulang akun yang sama ketika sesi habis.
- Beranda, akun/kategori/aturan merchant, transaksi/transfer, split bill/pelunasan/penghapusan kewajiban/reversal, Perlu Ditinjau dan deteksi kandidat duplikat.
- QRIS kamera/Foto, ambil foto bukti, OCR gambar lokal serta impor PDF/teks; seluruh hasil tetap draft, tidak ada pembayaran.
- Anggaran, laporan, CSV tampilan, ZIP penuh, Share Sheet, reset Demo, penghapusan akun, tema, sembunyikan nominal, dan pengunci perangkat.

## Perubahan offline

Outbox milik akun diproyeksikan ulang dari payload tersimpan saat restart/reload, dengan ID lokal stabil berbasis mutation UUID. Saldo/laporan server tidak dihitung ulang secara otoritatif oleh iOS. Catatan dengan mutasi belum sinkron tidak dapat diedit/dihapus lagi sebelum antreannya diselesaikan. Tombstone hapus diterapkan kembali pada cache sehingga catatan tidak muncul ulang.

Sinkronisasi berurutan memakai mutation UUID yang sama, retry eksponensial 2–300 detik hanya ketika aplikasi aktif dan protected data tersedia, serta retry manual di Pengaturan. Konflik menghentikan antrean tanpa menimpa server. Pengaturan menyediakan perbandingan payload perangkat dengan versi server, buang perubahan dengan konfirmasi, atau simpan pengeluaran konflik sebagai catatan baru dengan peringatan risiko hitung ganda. Logout menawarkan sinkronkan dulu atau buang secara eksplisit.

Transaksi/transfer akun nyata ditulis ke outbox sebelum dikirim, termasuk ketika online. Respons jaringan hilang atau restart tidak mengganti UUID operasi. Kegagalan refresh setelah acknowledgement server tidak meminta pengguna mengulang mutasi yang sudah diterima.

Operasi ledger online lainnya mempertahankan UUID retry untuk payload identik selama sesi repository sampai acknowledgement. Split bill tetap tidak masuk antrean offline. Bila aplikasi ditutup setelah kegagalan jaringan operasi online tersebut, periksa riwayat server sebelum membuat ulang; resume lintas restart untuk split bill bukan bagian outbox R1.

Jika store terlindungi gagal dibuka, aplikasi menampilkan keterbatasan dan tidak mengakui mutasi di memori sebagai tersimpan permanen. Pencatatan transaksi/transfer akun nyata ditahan sampai store kembali tersedia; tidak dialihkan diam-diam ke penyimpanan sementara. Demo tetap dapat berjalan. Upgrade schema SwiftData dan proteksi store/WAL/SHM masih memerlukan uji runtime/perangkat.

## Batas R1

- Split bill akun nyata, pelunasan, penghapusan kewajiban, unggah/konfirmasi review, ekspor penuh, dan hapus akun memerlukan internet.
- Transaksi dan transfer akun nyata dapat masuk outbox SwiftData saat offline; server merekonsiliasi saat aplikasi aktif kembali.
- QRIS dan impor selalu menjadi draft. Tidak ada tombol bayar atau verifikasi pembayaran.
- Lampiran JPEG/PNG/HEIC/PDF akun nyata divalidasi hingga 5 MB dan diunggah ke bucket privat; konfirmasi/merge/konversi memindahkan relasinya secara atomik.
- Riwayat transaksi dimuat 30 item per halaman dengan cursor `(occurred_at,id)`; laporan periode dihitung server dari seluruh ledger, bukan hanya halaman aktif.
- Aturan merchant hanya memberi saran kategori dan tidak menyimpan transaksi otomatis.
- OCR gambar tersedia untuk draft sejak pembaruan produk ini. Format struk ambigu, harga pecahan atau gambar tidak terbaca tetap dapat diisi manual. PDF scan tanpa lapisan teks belum memakai OCR PDF.
- Face ID/Touch ID hanya mengunci tampilan lokal, bukan MFA server.
- Token desain dibaca dari resource `contracts/design-tokens.json`; typography tetap native Apple, rounded untuk judul/nominal, layout ringkasan beradaptasi dengan Dynamic Type besar. QA visual/manual belum boleh dianggap lulus dari kode.
