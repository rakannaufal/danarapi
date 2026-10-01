# Scan struk cloud

## Konfigurasi produksi

1. Siapkan proyek Supabase produksi. Jalankan seluruh migrasi di `supabase/migrations` pada proyek tersebut; fungsi scan memerlukan tabel cache, kuota, dan RPC pada migrasi `202610010012_receipt_scan_cache.sql`.
2. Atur secret server `GEMINI_API_KEY`, `GEMINI_MODEL`, `ALLOWED_ORIGIN`, `SCAN_DAILY_LIMIT`, dan `SCAN_INTERVAL_MS`. Pertahankan model yang sudah digunakan backend; jangan memindahkan key penyedia ke iOS/web. Nilai service-role hanya boleh berada di server.
3. Deploy fungsi `receipt-scan` beserta backend akun yang dipakai aplikasi. Endpoint memverifikasi sesi akun melalui Supabase Auth, membatasi kuota, memakai cache per pengguna, dan membatasi panggilan model. Jangan menonaktifkan pemeriksaan sesi untuk Demo.
4. Isi URL HTTPS proyek dan public anon key pada `apps/ios/Configuration/Local.xcconfig`, mengikuti contoh. Rebuild aplikasi. Isi `VITE_SUPABASE_URL` dan `VITE_SUPABASE_ANON_KEY` pada lingkungan build web. URL iOS menggunakan sintaks `https:/$()/...` agar `//` tidak dianggap komentar xcconfig.
5. Masuk akun, ambil foto/galeri/PDF, lalu pilih Baca struk. Uji pada seluler dengan Mac dimatikan, kemudian Wi-Fi berbeda. Cocokkan rincian dengan foto sebelum mengonfirmasi. QRIS tidak memproses pembayaran.

## Kondisi workspace

Pada 1 Oktober 2026, URL proyek `zoccosfjulasqxczhvfm` dan publishable key sudah dikonfigurasi pada web/iOS. Pemeriksaan awal menemukan Google belum aktif, schema aplikasi belum tersedia, dan fungsi backend belum terdeploy (404). Model scan yang dipilih tersedia dengan key server existing; ekstraksi cloud nyata belum diuji. Ikuti `docs/supabase-cloud-setup.md` untuk migrations, deployment, provider dan pengujian. Implementasi client saja tidak membuat layanan cloud siap.

## Verifikasi pembaruan

- 71 tes logika web/backend dan 19 tes kontrak Swift lolos.
- 70 tes browser Chromium/WebKit lolos, mencakup impor foto/PDF, koreksi, split bill, offline, aksesibilitas, serta tampilan terang/gelap pada ponsel dan desktop. Respons AI memakai mock, bukan foto pengguna.
- Typecheck seluruh sumber iOS, XCTest/UI test, lint web, typecheck web, dan build web lolos. Build Debug iOS perangkat berhasil; warning orientasi iPad yang sudah ada tetap muncul.
- Pengujian pada iPhone 13 Rakan tanggal 1 Oktober 2026: 43 tes unit dan 3 tes UI lolos pada build terbaru. Cakupan mencakup rincian struk/PDF, pembulatan, penyimpanan draft, transport HTTPS dengan mock, navigasi tab, pilihan Struk/QRIS, dan pergantian bulan laporan. Screenshot diperiksa; tombol tambah dan navbar tidak lagi bertumpuk. Tes UI juga memastikan bingkai tombol tambah tidak beririsan dengan lima tombol navbar. Aplikasi dibuka kembali tanpa argumen tes atau debugger.
- Tes perangkat menemukan identifier navbar tertimpa oleh identifier kontainer dan tombol tambah menimpa navbar. Identifier kontainer dihapus; navbar kini memiliki ruang tersendiri di layout, tombol tambah ditempatkan di area konten. Ekspektasi tes token desain diselaraskan dengan kontrak desain yang sudah digunakan aplikasi.
- Satu percobaan startup UI sempat berhenti di layar masuk; pengulangan ketiga tes UI pada build yang sama lolos. Firefox tidak berhasil membuat profil tes; hasil Chromium/WebKit bukan bukti kelulusan Firefox.
- Scan seluler nyata masih menunggu konfigurasi/deploy backend produksi dan pengujian perangkat. Belum ada klaim bahwa seluruh alur produksi bebas error.

## Pengembangan lokal

Bridge Mac tetap tersedia hanya untuk pengujian eksplisit: `--local-receipt-scan` pada Run iOS Debug atau `VITE_LOCAL_RECEIPT_SCAN=true` saat Vite development. Tanpa opt-in ini, aplikasi tidak mencoba Mac/LAN. Release tidak memakai kredensial bridge. Jangan memakai tunnel publik dengan API key atau capability token yang ditanam dalam aplikasi.
