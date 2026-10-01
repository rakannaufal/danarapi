# Scan struk dan split bill

Implementasi melanjutkan Vue, SwiftUI, Supabase Edge Functions, dan ledger yang sudah ada. Tidak ada backend Express atau database kedua.

## Menjalankan

1. Buat API key pada Google AI Studio melalui `https://aistudio.google.com/apikey`. Periksa akses model dan kuota pada proyek sendiri. Jangan memasukkan key ke frontend, konfigurasi iOS, atau Git. Jika key pernah dibagikan di chat atau tempat publik, rotasi sebelum produksi.
2. Salin `supabase/.env.example` menjadi `supabase/.env` jika file belum ada. Isi `GEMINI_API_KEY`; `GEMINI_MODEL=gemini-3.5-flash-lite` menjadi default. `GEMINI_FALLBACK_MODEL` opsional dan kosong secara default supaya tidak otomatis beralih ke model lebih mahal. Tanpa key, input manual tetap berjalan. `supabase/.env` diabaikan Git dan harus memiliki permission 0600. Hapus secrets `OPENAI_API_KEY`, `OPENAI_MODEL`, dan `OPENAI_FALLBACK_MODEL` lama setelah migrasi; kode tidak membacanya lagi.
3. Jalankan migrasi database dengan `supabase db push` setelah memeriksa target proyek. Migrasi `202610010011_receipt_shared_split.sql` dan `202610010012_receipt_scan_cache.sql` menambahkan kalkulator serta cache scan. Pada pengembangan lokal gunakan `supabase start` dan `supabase db reset` hanya pada database pengembangan yang boleh dihapus.
4. Pengembangan akun nyata: `supabase functions serve --env-file supabase/.env`. Produksi: `supabase secrets set --env-file supabase/.env`, lalu deploy `receipt-scan` dan `ios-data` dengan `supabase functions deploy <nama-fungsi>`. Keduanya diperlukan untuk scan serta penyimpanan/baca ulang rincian review. Gunakan URL aplikasi pada `ALLOWED_ORIGIN`. Jangan mengunggah secrets ke Git.
5. Web: `npm install --prefix apps/web`, lalu `npm run web:dev`. Gunakan konfigurasi Supabase web yang sudah tersedia. iOS memakai konfigurasi Supabase aplikasi yang sudah ada; tidak memerlukan Gemini key.
6. Masuk dengan akun nyata, buka Split bill → Foto struk/Pilih dari galeri → Periksa hasil scan → Lanjut pilih pemesan. Demo sengaja tidak mengirim foto ke penyedia AI; demo tetap mendukung input manual dan pembagian.

Endpoint mengikuti gateway proyek: `POST /functions/v1/receipt-scan`, bukan server `/api/scan` terpisah. JWT diverifikasi dengan Supabase Auth sebelum foto diproses. Header: `Authorization: Bearer <access_token>`, `apikey: <Supabase anon key>`, `Content-Type: application/json`.

```json
{"images":[{"mimeType":"image/jpeg","data":"base64-tanpa-prefix-data-url"}]}
```

Respons: `{status, data?, validasi?, cached?, message}`. Nominal scan memakai angka sesuai kontrak ekstraksi; nominal yang masuk ledger tetap string desimal. Status kegagalan menyediakan jalur manual. Nama toko/menu ditampilkan sebagai teks, tidak menggunakan HTML hasil model.

## Keputusan dan batasan

- Maksimal tiga foto; total byte gambar terkompres maksimal 4 MiB. Klien mengecilkan sisi terpanjang ke 1600 px dan setiap JPEG ke maksimal 1,3 MB. Server memeriksa ukuran request, jumlah gambar, base64, MIME dan signature file. Foto sangat panjang dapat dipecah menjadi tiga gambar.
- Gemini REST `generateContent`, gambar melalui `inlineData`, instruksi melalui `systemInstruction`, dan skema Gemini melalui `generationConfig.responseSchema` dengan `responseMimeType=application/json`. Field diwajibkan, angka tidak terbaca boleh null. Uji nyata menunjukkan constraint `maxItems` pada skema ditolak HTTP 400; batas 100 menu tetap diterapkan kode normalisasi, bukan parameter penyedia. Hasil tetap dinormalisasi dan divalidasi oleh kode; output kosong, diblokir, atau terpotong menyediakan jalur manual. Bagian `thought` tidak dibaca sebagai hasil. Hanya kandidat dengan `finishReason=STOP` yang diterima. Timeout penyedia 30 detik per panggilan; batas klien tetap 110 detik.
- Batas keras **dua request HTTP ke Gemini untuk hash foto yang sama per pengguna selama cache 24 jam**, termasuk retry, timeout, 429, dan model fallback. Hanya satu retry dengan backoff minimal 2 detik untuk 429/5xx; fallback opsional memakai slot kedua, bukan slot tambahan. Hasil koreksi yang gagal tidak menghapus ekstraksi awal yang masih dapat diedit.
- Cache persisten berbasis SHA-256 byte foto beserta panjang tiap foto, terisolasi per pengguna. Reservasi call atomik sebelum jaringan; scan paralel untuk hash sama mendapat `busy`. Proses terputus tidak mengulang budget; setelah lima menit hasil menjadi `service_error`. Unggah ulang foto yang identik menggunakan cache, tidak memanggil Gemini lagi dalam masa cache. Cache lama penyedia lain yang masih valid tetap dapat digunakan hingga kedaluwarsa, mempertahankan batas dua panggilan tanpa biaya migrasi ulang; ganti model tidak membatalkan cache.
- Antrean waktu panggilan terpusat di PostgreSQL membatasi jarak mulai request lintas worker. `SCAN_INTERVAL_MS=4000` default. Antrean terlalu panjang ditolak dengan fallback manual. `SCAN_DAILY_LIMIT=50` default; hari dihitung UTC. Kedua nilai dapat dikonfigurasi, bukan kuota Gemini yang dihardcode.
- Jalur scan AI memakai preview di memori/object URL klien, dilepas ketika review selesai, dibatalkan, atau komponen ditutup. Endpoint AI tidak menyimpan foto ke Storage/cache server atau log. Impor Perlu Ditinjau tetap menyimpan lampiran bukti melalui fitur attachment akun; dalam demo, lampiran hanya di memori browser. Cache AI menyimpan hash dan hasil JSON selama 24 jam; kedaluwarsa dibersihkan pada scan berikutnya. Penghapusan akun menghapus cache lewat foreign key cascade. Backup database mengikuti kebijakan retensi backup tersendiri.
- Pengguna tetap wajib memeriksa struk. Toleransi validasi OCR Rp 100 tidak berarti boleh ada selisih pembagian akhir. Tarif awal mengikuti biaya/subtotal struk, dibulatkan dua desimal. Service/pajak dihitung setelah diskon; taxIncluded menghapus penambahan ulang keduanya.
- Struk tertentu menghitung biaya sebelum diskon, memakai tarif berbeda, atau harga satuan yang tidak bisa merepresentasikan total baris tepat. Selisih terhadap total struk ditampilkan. Pengguna bisa mengoreksi tarif/menu, secara eksplisit menyesuaikan pembulatan struk, atau mengonfirmasi total hasil koreksi. Sistem tidak diam-diam mengganti angka agar terlihat cocok.
- Pemesan bisa dipilih per menu atau per orang. Centang bersama membagi kuantitas sebagai satu kesatuan. Mode nominal/sama rata lama tetap tersedia. Pecah porsi, riwayat teman, dan ekspor khusus struk merupakan pengembangan opsional, bukan syarat inti scan.
- iOS mempertahankan OCR Vision lokal sebagai alternatif tanpa AI cloud. Kamera/galeri/performa/VoiceOver perlu diuji pada perangkat nyata. Mode manual tidak memerlukan model, key, atau kuota AI; penyimpanan akun nyata tetap mengikuti koneksi yang diperlukan ledger.

## Model dan biaya

Default `gemini-3.5-flash-lite`: model stabil untuk beban cepat/hemat, mendukung input gambar dan Structured Outputs. Google mencantumkan free tier, dengan ketersediaan dan kuota mengikuti proyek/akun. Harga standar paid tier yang diperiksa 1 Oktober 2026: input USD 0,30 dan output USD 2,50 per satu juta token, termasuk thinking. Token gambar, panjang hasil, koreksi dan retry memengaruhi tagihan. Kompresi gambar, cache dan batas dua panggilan mengurangi biaya tanpa menghilangkan pemeriksaan hasil. Batas harian berlaku per pengguna, bukan batas dolar seluruh proyek; periksa billing/kuota Google secara terpisah. Akurasi struk nyata belum diukur; tetap periksa hasil dan koreksi jika perlu.

Dokumentasi resmi: `https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite`, `https://ai.google.dev/gemini-api/docs/pricing`, `https://ai.google.dev/api/generate-content`. Model dapat diganti melalui `GEMINI_MODEL` setelah menguji struk nyata; tidak ada peningkatan otomatis ke model mahal.

## Privasi

Google menyatakan input/output layanan Gemini tidak berbayar dapat digunakan untuk memperbaiki produk dan ditinjau manusia; perlakuan dapat berbeda menurut wilayah serta status billing proyek. Baca ketentuan yang berlaku untuk akun sendiri: `https://ai.google.dev/gemini-api/terms`. Foto tidak disimpan di server aplikasi; penyedia AI memiliki kebijakan retensi sendiri. Jangan unggah struk yang memuat data sensitif. Peringatan tampil sebelum tombol unggah pada iOS dan web. Memilih foto merupakan tindakan eksplisit untuk mengirimnya; membatalkan request klien tidak menjamin request yang sudah diterima penyedia AI ditarik kembali.

## Pengujian

```sh
npm run web:test
npm run web:typecheck
npm run web:lint
npm run web:build
npm run web:e2e -- --project=chromium --project=webkit
swift test --package-path apps/ios
sh tests/swift/typecheck.sh
deno check supabase/functions/receipt-scan/index.ts
sh tests/database/plain-postgres.sh
```

Tes mock menguji ekstraksi satu/dua request, kontrak Gemini generateContent dan JSON Schema, thought/non-STOP/blocked output, JSON tidak valid, hasil tetap tidak cocok, 429/fallback, 5xx/timeout, cache, batas harian, validasi dan tipe/ukuran gambar. Fixture `receipt-split-v2.json` dipakai bersama TypeScript, Swift dan PostgreSQL untuk nominal besar, diskon, pajak inklusif, serta pembulatan bertanda. PostgreSQL sementara juga menguji penolakan panggilan ketiga dan pembatasan akses fungsi cache. E2E memakai gambar sintetis, review sintetis, dan demo; bukan bukti akurasi Gemini pada struk nyata.

Key Gemini sudah dimasukkan ke environment backend lokal yang diabaikan Git. Setelah persetujuan pengguna, satu struk Karis Jaya Shop berhasil diuji pada Gemini dan alur browser localhost: merchant, tanggal 2023-08-02, tiga produk, dan total Rp 70.000 terbaca; validasi nominal lulus. Satu contoh ini bukan tolok ukur akurasi umum. Tidak ada deploy produksi dalam pekerjaan ini. Auth gateway deployed, foto perangkat nyata dan sampel 15–20 struk tetap perlu diuji dengan persetujuan pemilik struk. Catat jumlah struk, jenis, jumlah lolos otomatis dan koreksi; jangan mengarang persentase akurasi.

## Unggah review dan demo localhost

- Pada halaman Perlu Ditinjau, opsi Gemini tampil sebelum unggah. Gambar non-QRIS dibaca AI; PDF tanpa lapisan teks dirender lokal lalu dikirim sebagai maksimal tiga gambar. QRIS dan PDF berlapis teks tetap dibaca lokal tanpa panggilan AI. Matikan opsi Gemini agar gambar hanya masuk jalur manual.
- Hasil menampilkan toko, tanggal tercetak, total, menu/qty/harga satuan/total baris, catatan kemasan, biaya tambahan dan validasi. Data asal ekstraksi diberi label sebagai data hasil Gemini, bukan transkripsi mentah. Nominal yang disimpan dalam review tetap string desimal. Saldo belum berubah sampai pengguna mengonfirmasi.
- Baca ulang memakai lampiran review yang sudah ada dan memperbarui baris pending yang sama; tidak membuat review atau transaksi duplikat. Hasil lama tidak ditimpa jika layanan gagal. Split bill menerima menu dari review dan tetap meminta pemilihan pemesan.
- Untuk demo localhost, set `LOCAL_RECEIPT_SCAN=1` dalam `supabase/.env`, lalu jalankan/restart `npm run web:dev`. Konfigurasi lokal saat ini sudah aktif. Hanya Vite dev server yang menyediakan `/__local/receipt-scan`; tidak tersedia pada build/preview produksi. Jangan membuka server pengembangan ke jaringan publik.
- Endpoint lokal hanya menerima alamat loopback, Host localhost/127.0.0.1/IPv6 loopback, Origin identik serta token acak untuk POST. Token tidak mengandung key API. Key dimuat di proses server, tidak pernah di bundle frontend. Cache/antrean/budget demo lokal berada di memori proses, sehingga reset saat restart; produksi tetap memakai cache/budget PostgreSQL persisten. Harian default 50 scan baru, maksimal dua panggilan per hash dalam sesi cache, cache 24 jam, interval awal 4 detik.

### Hasil lokal sebelum migrasi OpenAI — 1 Oktober 2026

- 50 tes TypeScript/domain/backend mock lulus.
- Delapan XCTest kontrak Swift lulus, termasuk fixture nominal besar dan validasi scan.
- Type-check source aplikasi iOS, unit test dan UI test lulus; bukan uji kamera/perangkat nyata.
- 12 E2E terpilih Chromium/WebKit lulus: manual, koreksi review, fallback scan, mode pemesan, simpan/edit rincian, aksesibilitas dialog, mode terang/gelap, serta regresi 20 catatan/10 split dan pelunasan lama.
- Lint, type-check dan build web lulus; pemeriksaan Deno Edge Function lulus.
- Semua migrasi pada PostgreSQL 15 sementara, fixture lintas tiga platform, penolakan call ketiga, cache/limit per pengguna, konkurensi ledger serta backup/restore sintetis lulus. Database aplikasi/produksi tidak diubah.
- Screenshot sintetis: `apps/web/artifacts/visual/{chromium,webkit}/receipt-scan/`. Header scan dan bagian hasil diperiksa pada ponsel/desktop terang/gelap.

Hasil ini tidak menggantikan seluruh suite browser proyek atau pengujian penyedia AI live, serta tidak mengklaim seluruh checklist perangkat/produksi selesai.

### Verifikasi migrasi OpenAI — 1 Oktober 2026

- 52 tes TypeScript/domain/backend mock lulus, termasuk kontrak Responses API, refusal/incomplete, fallback dan pelestarian hasil awal ketika koreksi gagal.
- Delapan E2E scan/formulir Chromium dan WebKit lulus, termasuk pemberitahuan privasi OpenAI, mode manual, review dan layout terang/gelap.
- Lint, type-check dan build web lulus; Deno Edge Function serta source aplikasi iOS/XCTest/UI test berhasil diperiksa tipenya.
- Tidak ada panggilan OpenAI berbayar atau deployment produksi. Akurasi struk nyata dan biaya per scan belum diukur.

### Kembali ke Gemini — 1 Oktober 2026

- Default backend dan contoh environment memakai `gemini-3.5-flash-lite`. Key hanya disimpan di `supabase/.env` yang diabaikan Git dengan permission 0600; pemeriksaan source tidak menemukan key tersebut.
- Verifikasi metadata model dengan key pengguna menghasilkan HTTP 200 dan dukungan generateContent. Tidak ada generasi atau foto yang dikirim dalam verifikasi ini. Key yang dibagikan di chat harus dirotasi sebelum produksi.
- 52 tes TypeScript/domain/backend mock dan delapan E2E Chromium/WebKit lulus. Lint, type-check, build web, Deno Edge Function dan pemeriksaan tipe source iOS/XCTest/UI test lulus.
- Batas dua panggilan, cache 24 jam, koreksi manual dan fallback manual tetap berlaku. Tidak ada deployment produksi atau pengukuran akurasi struk nyata.

### Perbaikan hasil ekstraksi review — 1 Oktober 2026

- Akar masalah: unggah Perlu Ditinjau hanya membaca QR/lapisan teks sehingga gambar struk menjadi review kosong; demo selalu mengembalikan config_error. Konfigurasi skema Gemini juga ditolak HTTP 400. Pengujian teks sintetis mengisolasi constraint maxItems sebagai parameter yang ditolak.
- Jalur unggah foto/PDF scan kini terhubung ke scan AI dengan pemberitahuan privasi, opsi manual, status proses, pembatalan, rincian menu/biaya/validasi, baca ulang pada review yang sama, dan prefill menu split bill. Nominal disimpan sebagai string desimal. Tidak ada perubahan saldo otomatis.
- Setelah persetujuan eksplisit pengguna, foto Karis Jaya Shop berhasil diekstrak lewat Gemini: tanggal 2023-08-02; Indomie Goreng 1 kemasan lusin Rp 36.000, Fruit Tea Apple 1 botol 500 ml Rp 7.000, Belfood Sosis Bakar Rp 27.000; total Rp 70.000. Satu panggilan pada konfigurasi yang diperbaiki menghasilkan HTTP 200/STOP dan validasi lulus.
- Uji browser langsung tanpa mock juga menampilkan tiga baris dan total Rp 70.000 pada halaman Perlu Ditinjau localhost. Bukti visual: `apps/web/artifacts/visual/chromium/receipt-import/live-karis.png`.
- 61 tes TypeScript/domain/backend dan 16 E2E Chromium/WebKit lulus, termasuk keamanan endpoint lokal, fallback, baca ulang, aksesibilitas, prefill split bill dan PDF tanpa lapisan teks. Lint, type-check, build web serta Deno receipt-scan/ios-data lulus.
- Tidak ada deployment produksi. Sampel tunggal bukan jaminan akurasi untuk semua foto/struk; pengujian perangkat iOS dan sampel tambahan tetap diperlukan.

### Struk grosir dan jumlah besar — 1 Oktober 2026

- Jumlah barang mendukung 1–999.999 (0 untuk draft kosong). Normalisasi tidak lagi memotong 4.000/8.000 menjadi 999. Web, iOS dan PostgreSQL memakai batas yang sama; batas nominal tetap Rp999.999.999.999. Jumlah tidak valid ditandai, bukan diam-diam dibetulkan.
- Prompt mempertahankan satuan pada catatan, jumlah ribuan, tanggal tercetak dan semua nominal asli. Pada struk tanpa label Total, Subtotal hanya dipakai sebagai total belanja jika tidak ada biaya tambahan. Bayar/Kembali bukan total belanja.
- Rincian struk memakai lebar penuh di desktop, tabel yang dapat digeser di ponsel, angka berkelompok, penanda baris bermasalah, jumlah baris tercetak dan jumlah × harga. Koreksi manual memperbarui review yang sama tanpa saldo atau panggilan AI tambahan; ketidaksesuaian tetap memerlukan konfirmasi eksplisit.
- Fixture TOKO ABANG menyalin delapan produk: Kardus Packing 800 × Rp9.000 = Rp7.200.000, tetapi cetakan Rp7.800.000. Jumlah baris tercetak Rp200.600.000; subtotal/hasil perkalian Rp200.000.000. Dua masalah asli ditandai, bukan tujuh masalah akibat pemotongan jumlah. Fixture dipakai untuk tes lokal; bukan hasil pengujian Gemini langsung pada foto tersebut.
- Hash cache memakai versi ekstraksi baru agar hasil lama yang terpotong tidak muncul saat Baca ulang. Cache 24 jam, dua panggilan per hash versi dan kuota harian tetap berlaku. Review yang sudah tersimpan tidak dimutasi otomatis: gunakan Koreksi rincian struk atau Baca ulang dengan Gemini.
- Migrasi baru `202610010013_receipt_wholesale_quantity.sql` memperbarui kalkulator shared/legacy tanpa mengubah migrasi lama. Jalankan migrasi serta deploy ulang receipt-scan untuk produksi. Tidak ada deployment produksi pada pekerjaan ini.
- Verifikasi: 62 tes Node, 18 E2E Chromium/WebKit dan sembilan XCTest lulus. Kasus grosir mencakup jumlah asli, selisih baris/subtotal, koreksi tanpa scan tambahan, prefill, aksesibilitas dan lebar ponsel 375 px. Lint, type-check/build web, pemeriksaan tipe aplikasi iOS lengkap, Deno receipt-scan, migrasi PostgreSQL sementara serta backup/restore juga lulus. Foto grosir tidak dikirim ke Gemini dalam pengujian ini.
