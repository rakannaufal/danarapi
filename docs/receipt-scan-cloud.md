# Scan struk cloud

## Konfigurasi produksi

Pembaruan 5 Oktober 2026: endpoint menerima `purpose: "bank_proof"` untuk bukti Share iOS, dengan gambar JPEG/PNG/WebP (maksimal tiga, total 4 MB) atau teks maksimal 64 KB. Respons `proof` terpisah dari `data` struk menu. Cache memakai namespace berbeda; autentikasi, persetujuan, kuota, batas dua panggilan model, dan key server tetap digunakan. Fungsi `receipt-scan` versi ini telah dideploy pada proyek workspace; penegakan consent versi `2026-10-02` kini aktif. Hasil bank tidak memanggil ledger.

1. Siapkan proyek Supabase produksi. Jalankan seluruh migrasi di `supabase/migrations` pada proyek tersebut; fungsi scan memerlukan tabel cache, kuota, dan RPC pada migrasi `202610010012_receipt_scan_cache.sql`.
2. Atur secret server `GEMINI_API_KEY`, `GEMINI_MODEL`, `ALLOWED_ORIGIN`, `SCAN_DAILY_LIMIT`, dan `SCAN_INTERVAL_MS`. Pertahankan model yang sudah digunakan backend; jangan memindahkan key penyedia ke iOS/web. Nilai service-role hanya boleh berada di server.
3. Deploy fungsi `receipt-scan` beserta backend akun yang dipakai aplikasi. Endpoint memverifikasi sesi akun melalui Supabase Auth, membatasi kuota, memakai cache per pengguna, dan membatasi panggilan model. Jangan menonaktifkan pemeriksaan sesi untuk Demo.
4. Isi URL HTTPS proyek dan public anon key pada `apps/ios/Configuration/Local.xcconfig`, mengikuti contoh. Rebuild aplikasi. Isi `VITE_SUPABASE_URL` dan `VITE_SUPABASE_ANON_KEY` pada lingkungan build web. URL iOS menggunakan sintaks `https:/$()/...` agar `//` tidak dianggap komentar xcconfig.
5. Masuk akun, ambil foto/galeri/PDF, lalu pilih Baca struk. Uji pada seluler dengan Mac dimatikan, kemudian Wi-Fi berbeda. Cocokkan rincian dengan foto sebelum mengonfirmasi. QRIS tidak memproses pembayaran.

## Kondisi workspace

Proyek `zoccosfjulasqxczhvfm` memiliki Google aktif, callback iOS, 20 migrations, lima fungsi backend dan secret scan server. Migrasi 18–20 serta pembaruan `ios-data`, `export-data`, dan `product-info` diterapkan pada 2 Oktober 2026. CORS Vercel/localhost diperiksa. Uji cloud terautentikasi pada struk sintetis menghasilkan total Rp 23.000 dan qty 2. Pada 5 Oktober 2026, `receipt-scan` dengan pembacaan bukti bank dan penegakan consent versi `2026-10-02` sudah diterapkan. Uji AI nyata pada gambar BSI/GoPay sintetis beserta cache dan akun sementara lulus; rincian ada di `docs/ios-share-receipts.md`. Login Google akun pengguna, foto bukti nyata dan jaringan seluler tetap memerlukan pemeriksaan perangkat.

## Verifikasi pembaruan

Angka berikut merupakan bukti pengujian sebelumnya. Pengujian terbaru pada 2 Oktober 2026 mencakup 122 tes Chromium/WebKit, 90 unit web, cloud sintetis, database lokal dan iPhone. Gunakan `docs/production-readiness.md` untuk hasil terbaru, koreksi selama pengujian dan batas verifikasi keyboard/perangkat.

- 71 tes logika web/backend dan 19 tes kontrak Swift lolos.
- 70 tes browser Chromium/WebKit lolos, mencakup impor foto/PDF, koreksi, split bill, offline, aksesibilitas, serta tampilan terang/gelap pada ponsel dan desktop. Respons AI memakai mock, bukan foto pengguna.
- Typecheck seluruh sumber iOS, XCTest/UI test, lint web, typecheck web, dan build web lolos. Build Debug iOS perangkat berhasil; warning orientasi iPad yang sudah ada tetap muncul.
- Pengujian pada iPhone 13 Rakan tanggal 1 Oktober 2026: 43 tes unit dan 3 tes UI lolos pada build terbaru. Cakupan mencakup rincian struk/PDF, pembulatan, penyimpanan draft, transport HTTPS dengan mock, navigasi tab, pilihan Struk/QRIS, dan pergantian bulan laporan. Screenshot diperiksa; tombol tambah dan navbar tidak lagi bertumpuk. Tes UI juga memastikan bingkai tombol tambah tidak beririsan dengan lima tombol navbar. Aplikasi dibuka kembali tanpa argumen tes atau debugger.
- Tes perangkat menemukan identifier navbar tertimpa oleh identifier kontainer dan tombol tambah menimpa navbar. Identifier kontainer dihapus; navbar kini memiliki ruang tersendiri di layout, tombol tambah ditempatkan di area konten. Ekspektasi tes token desain diselaraskan dengan kontrak desain yang sudah digunakan aplikasi.
- Satu percobaan startup UI sempat berhenti di layar masuk; pengulangan ketiga tes UI pada build yang sama lolos. Firefox tidak berhasil membuat profil tes; hasil Chromium/WebKit bukan bukti kelulusan Firefox.
- Backend scan sudah terdeploy dan ekstraksi struk sintetis melalui cloud lolos. Bug RPC `finish_receipt_scan` yang mengembalikan HTTP 204 tanpa JSON diperbaiki; respons kosong tidak lagi dilaporkan sebagai gambar tidak valid. Foto struk pengguna pada seluler belum menjadi bagian dari pengujian ini.

## Pengembangan lokal

Bridge Mac tetap tersedia hanya untuk pengujian eksplisit: `--local-receipt-scan` pada Run iOS Debug atau `VITE_LOCAL_RECEIPT_SCAN=true` saat Vite development. Tanpa opt-in ini, aplikasi tidak mencoba Mac/LAN. Release tidak memakai kredensial bridge. Jangan memakai tunnel publik dengan API key atau capability token yang ditanam dalam aplikasi.
