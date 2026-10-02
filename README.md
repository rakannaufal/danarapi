# Danarapi

Repository GitHub: [rakannaufal/danarapi](https://github.com/rakannaufal/danarapi). Hosting web Vercel memakai Root Directory `./`; konfigurasi tersedia di `vercel.json`. Langkah import, environment publik, OAuth dan CORS: [panduan Vercel](docs/vercel-deployment.md).

Monorepo Danarapi v3.3: backend Supabase/PostgreSQL, kontrak data v1, fixture emas lintas platform, aplikasi iOS native SwiftUI R1, seed Demo sintetis, dan token desain bersama. Build/perangkat iOS tetap harus diverifikasi pada toolchain Xcode yang sehat dan iPhone nyata sebelum R1 dinyatakan selesai.

## Struktur

Konfigurasi cloud web/iOS sudah menunjuk proyek Supabase pengguna. Setup migrations, login Google, secret scan dan deployment: `docs/supabase-cloud-setup.md`. Gunakan `npm run cloud:check` untuk membedakan konfigurasi klien dari kesiapan layanan server. Jangan menjalankan seed atau tes database pada produksi.

Status implementasi, bukti pengujian terbaru, rollout yang belum dilakukan dan gerbang rilis: [kesiapan produksi](docs/production-readiness.md). Pengujian dilanjutkan atas izin pengguna; hasil otomatis tidak menggantikan verifikasi akun nyata dan belum menyatakan rilis siap produksi.

```text
apps/ios/                 aplikasi SwiftUI iOS 17, Xcode project, XCTest/UI test
apps/web/                 Vue 3, TypeScript, Vite; UI responsif dan adapter web R1
contracts/                JSON Schema, OpenAPI, error stabil, design tokens
supabase/migrations/      skema, RLS, Storage privat, RPC ledger
supabase/functions/       gateway Edge Function tanpa service-role di klien
supabase/tests/           pgTAP migrasi, constraint, RLS, ledger
tests/fixtures/           fixture emas dan seed demo lintas platform
tests/database/           harness migrasi dan konkurensi dua koneksi
docs/                     PRD, ADR, arsitektur, threat model, wireframe
```

## Prasyarat

- Node.js 22+
- Swift 6/Xcode untuk uji kontrak iOS
- Docker Desktop dan Supabase CLI untuk database lokal
- PostgreSQL client (`psql`) untuk uji konkurensi
- Deno 2 untuk memeriksa Edge Function

## Setup lokal

```sh
cp .env.example .env.local
supabase start
supabase db reset --local
npm run check:json
npm run test:contracts
swift test --package-path apps/ios
supabase test db
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres sh tests/database/concurrency.sh
deno check supabase/functions/ledger/index.ts supabase/functions/ios-data/index.ts supabase/functions/export-data/index.ts
```

Ambil URL dan anon key lokal dari keluaran `supabase status`, lalu isi `.env.local`. Jangan menaruh service-role key pada `VITE_*`, aplikasi iOS, browser, fixture, atau Git.

## Menjalankan komponen

- Semua pemeriksaan non-database: `npm run check`
- Kontrak web saja: `npm run test:contracts`
- Kontrak Swift saja: `npm run test:swift`
- Fixture Swift tanpa SwiftPM: `npm run test:swift:fixture` (berguna saat lisensi Xcode host belum disetujui)
- Type-check source/XCTest tanpa SwiftPM: `npm run test:swift:typecheck`
- Database lengkap: `sh tests/database/migrations.sh`
- Regenerasi seed demo: `node scripts/generate-demo-fixture.mjs`
- Edge Function lokal: jalankan `ledger`, `ios-data`, dan `export-data` dengan `supabase functions serve`
- iOS Demo: buka `apps/ios/Danarapi.xcodeproj`, jalankan scheme `Danarapi`, pilih **Coba Demo**
- Setup iOS lengkap: lihat `apps/ios/README.md`
- Web: `npm ci --prefix apps/web`, kemudian `npm run web:dev`; pilih **Coba Demo** untuk mencoba tanpa backend.
- Gerbang web: `npm run check:web`, `npm run web:e2e`, dan `npm run test:edge`.
- Setup serta batas verifikasi web: lihat `apps/web/README.md` dan `docs/web-r1-verification.md`.

`apps/ios` berisi alur R1 native. `apps/web` menyediakan UI responsif, Demo lokal, adapter Supabase JS, transaksi/transfer/split, review impor, anggaran, target tabungan, laporan, dan ekspor. Modal cepat mengutamakan anggaran dan target; transfer tersedia di Transaksi. Beranda menampilkan seluruh anggaran bulan terpilih serta target, nominal terkumpul dan countdown. Sepuluh kategori anggaran siap dipilih, kategori khusus tetap tersedia. Progres target dicatat manual tanpa mengubah saldo. Detail: `docs/planning-ui.md`. UI kedua klien terpisah; keputusan finansial akun nyata tetap berada di PostgreSQL/RPC. Kamera langsung bukan fitur web R1. Hasil ekstraksi tidak menjadi transaksi tanpa konfirmasi pengguna.

Tampilan web dan iOS memakai font sistem, palet netral, aksen biru, dan penjelasan yang dapat dibuka sesuai kebutuhan. Detail desain: `docs/interface-redesign.md`.

## Aturan uang dan ledger

- Input nominal web dan iOS otomatis memakai titik ribuan (`5000` menjadi `5.000`); nilai API tetap tanpa titik. Detail: `docs/money-input.md`.
- PostgreSQL/RPC memutuskan dampak finansial. Klien hanya melakukan validasi cepat.
- Database menyimpan Rupiah sebagai `bigint`; JSON selalu memakai string desimal, misalnya `"120000"`.
- Batas satu operasi: Rp999.999.999.999. Nol hanya diizinkan untuk porsi split bill.
- Semua RPC tulis menerima UUID `client_mutation_id`. Replay payload sama mengembalikan respons tersimpan; payload berbeda menghasilkan `DUPLICATE_MUTATION`.
- Pelunasan dan penghapusan kewajiban mengunci baris bill. Trigger database juga menjaga total aktif tidak melebihi kewajiban.
- Transfer memakai dua kaki kas bernilai sama. Pelunasan tidak menjadi pemasukan/pengeluaran. Write-off piutang menjadi expense nonkas; pembebasan utang menjadi income nonkas.
- Semua relasi milik pengguna memakai FK `(user_id, id)` dan RLS. Bucket `attachments` privat; folder pertama harus UUID pemilik.

## Data demo

`tests/fixtures/demo-seed-v1.json` berisi tepat 200 transaksi sintetis selama tiga bulan, anggaran, serta split bill belum/sebagian lunas. `supabase/seed.sql` membuat akun lokal sintetis terpisah. Tidak ada bukti bayar atau data keuangan nyata.

## Status verifikasi

Hasil verifikasi lokal; status terbaru di `docs/web-r1-continuation.md`:

- JSON/seed: lulus; fixture valid dan tepat 200 transaksi Demo sintetis.
- Web: lint, typecheck, build dan 33 tes kontrak/domain lulus. Lanjutan mencakup Chromium/WebKit, lampiran posted, fokus keyboard dan DOM daftar 50.000 transaksi yang tetap 30 baris. Hasil E2E akhir dicatat pada laporan lanjutan; Firefox gagal meluncurkan profil, bukan diklaim lulus.
- Swift iOS: 4/4 kontrak SwiftPM, fixture serta typecheck source/XCTest/UI test lulus pada run web ini. Status build/Simulator native yang dikerjakan terpisah ada di `docs/ios-r1-testing.md`; tidak disimpulkan dari tes web.
- Edge Function: empat gateway mencakup `review-retention`; 15 tes transport/retensi mock. Enam CSV web/server/Swift dibandingkan pada 12 periode/timezone melalui `npm run test:export:parity`.
- PostgreSQL 15: sepuluh migrasi, seed, ledger/RLS/domain, retensi, konkurensi serta backup/restore data sintetis lulus melalui `tests/database/plain-postgres.sh`. Smoke dua klien memakai RPC bersama, bukan E2E dua aplikasi hidup; restore ini tidak mencakup Storage nyata.
- Secret scan serta sintaks shell/YAML: lulus.
- Supabase CLI, Docker CLI dan Colima dipasang. Percobaan stack nyata gagal karena disk penuh; VM/disk khusus percobaan dibersihkan tanpa menghapus data pengguna. pgTAP, Auth/SMTP dan HTTP Storage nyata memerlukan ruang tambahan atau staging yang diizinkan.

G1 tetap memerlukan iPhone nyata. Kamera, Foto, biometrik, Data Protection/WAL, VoiceOver, reduced motion, dan performa belum terverifikasi pada perangkat.

Web menyimpan matriks screenshot Chromium/WebKit sintetis dengan manifest SHA-256: lima layar ponsel/desktop terang/gelap, teks 200%, serta scroll dialog. Palet v1.1 mengikuti keputusan pada `docs/product-update-planning.md`. Axe, fokus dan reduced motion diuji; 20 input/10 split otomatis bukan uji kegunaan manusia. Auth/Storage Supabase nyata, dua aplikasi hidup, Safari asli/Firefox, screen reader/perangkat/manusia, aktivasi retensi, backup Storage/retensi cadangan, SMTP dan kanal dukungan produksi masih gerbang rilis. Tidak mengklaim R1 seluruhnya selesai.

Lihat [arsitektur](docs/architecture.md), [strategi uji](docs/testing.md), dan [threat model](docs/threat-model.md).

## Scan struk split bill

Split bill iOS/web mendukung scan Google Gemini lewat backend (`gemini-3.5-flash-lite` default), review dan koreksi lokal, diskon proporsional, pajak inklusif, pembulatan struk, serta input manual. Unggah pada Perlu Ditinjau juga membaca foto/PDF scan dan menampilkan rincian menu; hasil bisa dibaca ulang dan digunakan untuk split bill. Key dan model hanya di environment backend. Konfigurasi, batas dua panggilan, biaya API, privasi dan pengujian tersedia di [panduan scan struk](docs/receipt-scan.md). Demo produksi tidak mengirim foto ke Gemini; localhost dapat memakai backend pengembangan dengan `LOCAL_RECEIPT_SCAN=1`. Migrasi dan Edge Function perlu diterapkan ke backend sebelum scan akun nyata aktif.
