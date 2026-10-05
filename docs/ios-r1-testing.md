# Verifikasi iOS R1

## Persentase anggaran dan interaksi laporan, 5 Oktober 2026

Anggaran iOS menampilkan persentase total, setiap kategori, dan detail kategori; penggunaan di atas 100% tidak dipotong pada label. Web menambahkan persentase total dan memperjelas badge kategori. Diagram donat iOS mendukung ketukan sektor dan legenda; diagram batang mendukung pemilihan periode/kategori. Web mendukung hover, klik, Enter, dan Space langsung pada sektor/batang. Rincian memakai kategori/periode, nominal, dan persentase; nominal tetap mengikuti pengaturan sembunyikan nominal.

Arus kas memakai font sistem Apple, label sekunder, nominal berukuran konsisten dan rata kanan; arus bersih lebih tegas. iOS beralih ke susunan vertikal pada ukuran teks aksesibilitas; web ponsel memakai satu baris per metrik.

- iPhone 13 "Rakan": 69 XCTest aplikasi dan UI pemilihan bulan lulus (`/tmp/danarapi-ios-report-interaction.xcresult`). Uji ketukan sektor serta persentase list/detail juga lulus (`/tmp/danarapi-ios-report-tap.xcresult`). Regresi kontribusi target pada alokasi lulus (`/tmp/danarapi-ios-report-goal-regression.xcresult`). Screenshot: `/tmp/danarapi-ios-report-evidence/`.
- Web: 17 pemeriksaan layout/dashboard lulus; tiga pemeriksaan interaksi langsung, keyboard, nominal tersembunyi, Axe, persentase, dan keselarasan arus kas lulus setelah memperbaiki posisi pointer pengujian (`/tmp/danarapi-report-web-e2e.log`, `/tmp/danarapi-report-web-interaction-final.log`).
- Typecheck, lint, build web, dan `git diff --check` lulus. Build masih memberi peringatan ukuran chunk yang sudah ada.

## Verifikasi iPhone fisik, 5 Oktober 2026

Perangkat: iPhone 13 "Rakan", iOS 27.0 (`24A437`), UDID `00008110-000504112EBA201E`. Pengujian melalui Xcode langsung pada perangkat.

| Pemeriksaan | Hasil | Bukti |
| --- | --- | --- |
| XCTest aplikasi terbaru | 69/69 lulus | `/tmp/danarapi-ios-demo-verified.log`, `/tmp/danarapi-ios-demo-verified.xcresult` |
| UI terbaru | 3/3 lulus | Navigasi inti; navbar dari detail dan Scan; saldo/pemasukan/pengeluaran membuka halaman sesuai. Bundle yang sama, `TEST SUCCEEDED` |
| Data Demo | Lulus | Awal bulan/tahun, Februari kabisat, pergantian hari Jakarta, pagination, tidak ada transaksi masa depan, progres dari kontribusi, status pelunasan, dan rekonsiliasi posisi bersih. Nominal Oktober cocok dengan skenario web |
| Revamp sebelum pembaruan data | 66 XCTest + 20 UI lulus | `/tmp/danarapi-ios-revamp-device-final.xcresult`; navbar, onboarding, keyboard, forms, scanner, tema terang/gelap |
| Ikon Apple dan gear | 67 XCTest + 3 UI lulus | `/tmp/danarapi-ios-apple-icons-final.xcresult`; katalog simbol tersedia pada perangkat |
| Web terbaru | 100 tes data + 11 UI Chromium lulus | `/tmp/danarapi-demo-web-tests-final.log`, `/tmp/danarapi-demo-web-e2e-final.log`; seluruh halaman, viewport 320/390/834/1440, teks 200%, tema terang/gelap, Axe |
| Build/typecheck/lint web | Lulus | `/tmp/danarapi-demo-web-build-final.log`, `/tmp/danarapi-demo-web-lint-final.log`; Vite tetap memberi peringatan ukuran chunk |

Skenario Demo menggunakan bulan perangkat saat masuk/reset. Tiga akun, tiga target, tujuh anggaran per bulan, transaksi/transfer tiga bulan, tiga status split bill, tiga draft tinjauan, dan enam aturan merchant memakai rencana bersama `scripts/demo-showcase.mjs`. Fixture bertanggal tetap disimpan untuk regresi. Draft belum memengaruhi saldo. Pemindaian kamera/AI akun nyata, biometrik, VoiceOver manual, integrasi Supabase nyata, dan Data Protection tetap memerlukan QA tersendiri.

Artefak `/tmp` bersifat sementara. Perintah verifikasi terbaru memakai `-destination 'platform=iOS,id=00008110-000504112EBA201E'`, signing perangkat, dan `-parallel-testing-enabled NO`.

## Arsip pembaruan goals dan split per menu, 1 Oktober 2026

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

## Share bukti transaksi - 5 Oktober 2026

Verifikasi akhir pada iPhone 13 Rakan (`00008110-000504112EBA201E`), iOS 27.0: **89 XCTest aplikasi dan 3 UI test Share lulus**, tanpa Simulator. Result bundle: `/tmp/danarapi-ios-share-final-verified.xcresult`; log: `/tmp/danarapi-ios-share-final-verified.log`. Build web (`vue-tsc --noEmit` dan Vite) juga lulus setelah persentase kategori disamakan dengan teks tebal Anggaran.

- Share Sheet iOS benar-benar menjalankan extension Danarapi untuk teks, PNG dan PDF sintetis. Draft lokal tetap tersedia setelah app ditutup dan dibuka ulang; OCR/text PDF membaca nominal 150000, bukan biaya admin 2500 atau saldo 9000000.
- Akun Demo menampilkan bukti lokal tetapi tidak dapat mengunggah bukti pribadi. Preview bukti teks diuji. Ketiga bukti sintetis dibersihkan melalui aksi Hapus lokal setelah pengujian.
- Tes aplikasi memeriksa batch atomik, restart, penulisan bersamaan, deduplikasi, kuota/batas ukuran, path traversal, kerusakan payload, akun tujuan, parser konservatif, dan saldo yang tetap sama setelah draft masuk.
- Transport stub memverifikasi pergantian akun menghentikan permintaan berikutnya, upload timeout tidak menggandakan lampiran, draft selesai tidak dibuka ulang, konfirmasi pemasukan mempertahankan jenisnya, serta retry transfer mempertahankan UUID dan rincian yang tersimpan.
- Bukti visual alur perangkat sebelumnya: `/tmp/danarapi-ios-share-evidence/`. Share extension dan draft lokal diperiksa secara visual; font Apple, tombol teal dan navbar tetap tersedia.

Tidak ada transaksi bank nyata, login BSI, atau unggahan bukti pribadi selama pengujian. Alur share langsung dari aplikasi BSI dan konfirmasi ledger ke Supabase akun nyata belum diuji end-to-end; transport jaringan diuji dengan respons sintetis. Panduan penggunaan dan batas: `docs/ios-share-receipts.md`.

## Perbaikan kiriman Share bank - 5 Oktober 2026

Screenshot `IMG_4643.PNG` menunjukkan extension tersedia di Share BSI tetapi persiapan lampiran ditolak. Screenshot tidak mengungkap jenis UTI atau isi lampiran sebenarnya; penyebab persis di aplikasi BSI belum dapat disimpulkan dari gambar tersebut. Pembaca sebelumnya hanya mencoba satu representasi berkas sementara dan menolak provider pendamping yang tidak dikenal.

Perbaikan `SharedIntake/ShareItemReader.swift` mencoba semua representasi gambar/PDF, data langsung, objek `UIImage`, item legacy, serta file URL/objek `NSURL`. Gambar yang dapat dibaca ImageIO tetapi belum didukung penyimpanan disalin ke JPEG. URL pendamping tidak diambil melalui jaringan; keterangan kosong tidak membuang gambar yang valid. Satu lampiran rusak tetap menggagalkan batch secara jelas. Timeout, pembatalan, batas ukuran dan perlindungan callback ganda diuji.

UI kegagalan sekarang menyatakan bahwa belum ada draft tersimpan, menyediakan **Coba baca ulang**, serta **Detail format kiriman** yang hanya menampilkan identifier UTI. Tombol Simpan tidak ditampilkan ketika tidak ada bukti yang berhasil dibaca. Bukti masih memakai alur draft dan konfirmasi akun yang sama.

Pada iPhone 13 Rakan, 14 tes pembaca provider dan dua UI test tambahan (gambar native serta gambar dengan tautan pendamping) lulus: `/tmp/danarapi-ios-bsi-provider-final.xcresult`. Bukti sintetis berhasil dibaca menjadi nominal 150000, tersimpan setelah relaunch, lalu dibersihkan. Screenshot diperiksa di `/tmp/danarapi-ios-bsi-share-evidence/`.

Regresi seluruh 103 tes aplikasi dan tiga UI test teks/foto/PDF lulus dalam `/tmp/danarapi-ios-bsi-share-regression.xcresult`. Total lima alur Share perangkat lulus bersama dua UI test tambahan di atas. Alur BSI sebenarnya perlu dibagikan ulang dari perangkat pengguna setelah versi perbaikan terpasang; pengujian otomatis memakai payload sintetis, tanpa membuka rekening atau membuat pembayaran bank.
