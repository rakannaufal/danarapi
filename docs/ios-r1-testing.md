# Verifikasi iOS R1

## Status lokal pembaruan goals dan split per menu

| Pemeriksaan | Status | Bukti/keterbatasan |
| --- | --- | --- |
| Source aplikasi iOS 17 | Lulus type-check | `tests/swift/typecheck.sh`, Swift 6 strict concurrency; `/tmp/danarapi-planning-complete-typecheck.log` |
| Source XCTest/UI test | Lulus type-check | module aplikasi dibangun dengan `-enable-testing`; source XCTest dan UI test tanpa diagnostic |
| Golden fixture Swift | Lulus | `tests/swift/golden.sh` |
| Kontrak TypeScript/Demo | Lulus 33/33 | `npm run test:contracts`; empat kasus menu dari fixture yang sama dengan Swift/PostgreSQL; `/tmp/danarapi-planning-complete-contracts.log` |
| JSON dan pola secret | Lulus | 8 berkas JSON, 200 transaksi sintetis; `npm run check:json`, `npm run check:secrets` |
| Edge Functions | Lulus | `deno check` tiga fungsi pada pembaruan planning |
| PostgreSQL migrasi/RLS/ledger | Lulus | PostgreSQL 15, migrasi `001`–`008`, seed, smoke, goals RLS/version/idempotency, menu, penolakan porsi palsu/RPC lama, normalisasi UUID huruf besar iOS, konkurensi. Calculator, mutasi dan constraint deferred diuji sebagai `authenticated`, bukan hanya superuser; `/tmp/danarapi-planning-auth-verified-postgres.log` |
| Xcode build aplikasi/tes | Lulus | Xcode 27.0 (`27A266a`), arm64 Simulator, minimum iOS 17; aplikasi, XCTest dan runner dikompilasi/link dalam run penuh terbaru dengan ad-hoc signing; `/tmp/danarapi-planning-complete.log`. Build generic arm64/x86_64 sebelumnya: `/tmp/danarapi-ios-build.log`, `/tmp/danarapi-ios-test-build.log` |
| Simulator XCTest aplikasi | Lulus 31/31 | `Danarapi-R1-Verification`, iPhone 17 Pro, iOS 26.5, UDID `B5C1D4B1-201B-4039-8CD9-0B5EB426F086`; `/tmp/danarapi-planning-complete.log`; mencakup OCR Vision struk sintetis, goals tanpa efek ledger, batas bulan eksklusif |
| Simulator UI test | Lulus 7/7 | Run penuh terbaru selesai tanpa kegagalan: navigasi, pengeluaran, draft impor, goal baru, kategori/anggaran baru, pemilihan bulan dan pembagian menu tiga orang; `/tmp/danarapi-planning-complete.xcresult` |
| SwiftPM XCTest | Lulus 4/4 | XCTest kontrak macOS; `/tmp/danarapi-planning-final-swiftpm.log`; bukan eksekusi tes aplikasi iOS |
| Build web | Lulus | `vue-tsc --noEmit` dan Vite production build; `/tmp/danarapi-planning-web-build-current.log`. Kendala dependensi pada run sebelumnya sudah teratasi |
| Tema terang/gelap | Lulus inspeksi visual Simulator | `/tmp/danarapi-planning-light.png`, `/tmp/danarapi-planning-dark.png`; palet putih–biru, font rounded dan kartu goals/anggaran. Bukan pengganti QA aksesibilitas perangkat |
| Supabase Storage/pgTAP asli | Belum terverifikasi | Supabase CLI dan Docker belum tersedia; kebijakan SQL terpasang pada bootstrap PostgreSQL, tetapi HTTP Storage belum dijalankan |
| Kamera/Foto/biometrik iPhone | Belum terverifikasi | memerlukan iPhone nyata |
| SwiftData Data Protection | Belum terverifikasi di perangkat | periksa store, WAL, SHM, restart, lock/unlock, backup exclusion |
| VoiceOver/Dynamic Type 200% | Belum terverifikasi manual | kode memakai label native dan Dynamic Type; tetap perlu QA perangkat |
| Performa cold start <2,5 detik | Belum diukur | memerlukan build Release pada iPhone uji |

Run penuh terbaru menghasilkan `TEST SUCCEEDED`, 31 XCTest aplikasi dan 7 UI test tanpa kegagalan. Log mencatat selesai pada 1 Oktober 2026 pukul 04:00 WIB. Artefak `/tmp` bersifat sementara; simpan salinan jika diperlukan untuk audit.

Simulator lama (`94B0A2E5-BED3-4A35-8177-25A70919E111`) tertahan saat boot dengan crash layanan sistem `containermanagerd`. Data Simulator lama tidak dihapus. Perangkat terpisah `Danarapi-R1-Verification` berhasil boot dan menjalankan seluruh tes; kendala boot lama bukan bukti crash aplikasi Danarapi.

Perintah run penuh dari root repo:

```sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild \
  -project apps/ios/Danarapi.xcodeproj -scheme Danarapi \
  -derivedDataPath /tmp/danarapi-ios-runtime \
  -destination 'platform=iOS Simulator,id=B5C1D4B1-201B-4039-8CD9-0B5EB426F086' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /tmp/danarapi-planning-next.xcresult test
```

Gunakan path result bundle baru setiap run. Jangan menambahkan `CODE_SIGNING_ALLOWED=NO` untuk tes runtime; runner memerlukan ad-hoc signing Simulator.

## Checklist iPhone

1. Pasang build Debug dan Release pada iPhone iOS 17+.
2. Tolak lalu izinkan Kamera dan Foto; pastikan jalur gambar/manual selalu tersedia.
3. Pindai QRIS fixture valid, CRC salah, QR non-QRIS, dan gambar tanpa QR. Semua hasil harus tetap draft.
4. Uji Face ID/Touch ID, kode perangkat, background privacy cover, restart, dan pergantian akun.
5. Buat transaksi/transfer offline, restart, reconnect, retry, konflik versi, logout dengan outbox, dan login akun berbeda.
6. Pastikan split bill akun nyata ditolak saat offline; Demo tetap berjalan.
7. Inspeksi SwiftData store beserta WAL/SHM: `NSFileProtectionComplete`, tidak ikut backup, tidak dapat dibaca ketika protected data unavailable.
8. Uji VoiceOver, urutan fokus, target sentuh 44 pt, tema terang/gelap, Reduce Motion, dan Dynamic Type 200%.
9. Jalankan 20 percobaan input cepat dan 10 percobaan split bill; catat hasil, jangan menganggap target lulus dari kode.
10. Ukur cold start Release dan scrolling riwayat 200+ item.

## Pengerasan sesi lanjutan

- URL Auth memisahkan path dan `grant_type` melalui `URLComponents`; tanda `?` tidak dikirim sebagai bagian path.
- Recovery menggunakan OTP dan update kata sandi tanpa memasukkan sesi recovery ke Keychain/dashboard. Signup menyediakan kirim ulang kode dengan cooldown UI.
- Keychain diperbarui secara atomik, refresh dikoalesensikan, pergantian identitas ditolak, dan refresh terlambat tidak boleh menghidupkan kembali sesi setelah logout. Pengunci gagal tertutup bila autentikasi perangkat tidak tersedia; kata sandi akun tetap menjadi fallback online.
- Decoder menolak nominal JSON numerik, pecahan, overflow dan string nonkanonik, serta menerima timestamp RFC 3339 server dengan pecahan detik.
- Cache/outbox menggunakan schema marker, proteksi sebelum store dibuka, ID proyeksi stabil, tombstone, retry/backoff, status konflik dan perbandingan dengan server. Mode penyimpanan sementara menahan seluruh pencatatan transaksi/transfer akun nyata, termasuk online.
- Respons dashboard, pagination dan laporan yang terlambat setelah pergantian identitas tidak diterapkan ke akun aktif. Refresh tidak menyimpan ulang snapshot yang sudah diproyeksikan outbox sebagai snapshot server.
- Kamera QR berhenti saat layar ditutup; kamera foto/gambar memakai OCR Apple Vision lokal untuk draft, tidak melakukan posting otomatis. Nominal OCR gambar tetap confidence rendah. Gate offline ditampilkan sebelum pemilihan lampiran akun nyata.
- Palet/radius/spacing/motion berasal dari token bundled, termasuk `on-primary` untuk tema gelap; angka utama mengikuti Dynamic Type dan kartu beralih ke satu kolom pada teks besar.

Tambahan source tes: `TransportContractTests`, `LedgerFixtureTests`, regresi proyeksi/backoff/konflik outbox, serta UI impor teks yang tetap draft. Helper assertion async diisolasi MainActor untuk code generation Swift 6, bukan hanya type-check. XCTest aplikasi dan UI test telah dieksekusi di Simulator. Migrasi store lama, race jaringan riil, integrasi Supabase akun nyata dan perilaku hardware belum terverifikasi; tidak disimpulkan dari keberhasilan tes Demo/fixture.

Pemeriksaan ulang pada 30 September 2026: JSON (6 berkas, 200 transaksi), kontrak TypeScript (5/5), golden fixture Swift, dan pemeriksaan pola secret lulus. Lisensi bukan lagi penghalang; sandbox awal menolak akses layanan Simulator/cache, lalu build dan SwiftPM berhasil setelah akses diizinkan. `PATH` dibatasi ke tool sistem untuk menghindari executable XAMPP lama yang tidak kompatibel dengan CPU host.

## Diagnosis screenshot runner

Laporan crash `DanarapiAppUITests-Runner-2026-09-30-214759.ips` menyatakan termination `DYLD / Library missing`, yaitu `@rpath/XCTest.framework/XCTest`, sebelum tes dijalankan. Ini adalah runner pengujian, bukan executable aplikasi Danarapi. Setelah runtime iOS 26.5 tersedia, peluncuran lewat `xcodebuild test` pada 30 September 2026 pukul 22:35–22:37 WIB menghasilkan `TEST SUCCEEDED`, 26 XCTest dan 3 UI test tanpa kegagalan. Untuk aplikasi pilih scheme Danarapi lalu Run; untuk runner gunakan Test. Tidak ada framework pengujian yang ditambahkan ke aplikasi produksi.

## Cakupan smoke PostgreSQL lokal

- Migrasi kosong dan seed Demo deterministik.
- RLS dua pengguna serta akun onboarding `Tunai`.
- Retry mutasi idempoten, overpay, write-off/reversal, dan konkurensi pelunasan.
- Edit metadata split setelah pelunasan; perubahan struktur ditolak `STRUCTURE_LOCKED`.
- Konfirmasi review memindahkan metadata lampiran ke transaksi.
- Konversi transaksi posted ke split bill membalik ledger lama dan memindahkan lampiran secara atomik.
- Goals tidak mengubah ledger; RLS pemilik, versi dan UUID idempotensi diuji.
- Empat fixture menu sama dengan Swift/TypeScript; total setiap orang, penyesuaian dan sisa pembulatan diuji.
- UUID peserta huruf besar dari iOS dinormalisasi sebelum penyimpanan. Constraint deferred menjaga konsistensi menu/porsi, termasuk mutasi lewat RPC lama.
- Calculator dan trigger validasi memakai `SECURITY DEFINER` dengan search path tetap; akses schema `private` tetap dicabut dari `authenticated`. Migration `008` juga memperbaiki konteks kedua trigger deferred split lama agar commit akun nyata dapat memvalidasi ledger tanpa membuka schema privat.
- Role `authenticated` menguji goals, split dan constraint deferred; kategori pengeluaran aktif diterima untuk anggaran, sedangkan kategori pemasukan, arsip dan milik akun lain ditolak.
