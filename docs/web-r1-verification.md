# Danarapi Web R1 — bukti dan batas verifikasi

**Status terbaru:** lihat `web-r1-continuation.md`. Laporan ini menyimpan hasil run awal; paritas CSV, retensi lokal, lampiran posted, WebKit, performa dan keputusan palet diperbarui pada lanjutan.

## Keputusan rilis

Implementasi web R1 tersedia di `apps/web`, dengan UI Vue 3/TypeScript/Vite yang terpisah dari SwiftUI. Alur Demo dan gerbang otomatis lokal lulus. **R1 akun nyata dan gerbang desain §6.8 belum dinyatakan selesai.** Auth/Storage Supabase sesungguhnya, interoperabilitas dua aplikasi berjalan, pengujian manusia, serta keputusan palet masih memerlukan verifikasi.

Acuan: `docs/PRD Danarapi v3.3.md`, kontrak v1, token desain bersama, implementasi RPC/iOS, `tests/fixtures/demo-seed-v1.json`, fixture nominal/pembagian/impor. Nama PRD dalam repo memakai spasi, bukan `PRD-Danarapi-v3.3.md`. Timestamp pengambilan bukti dicatat dalam manifest UTC; tanggal contoh Demo tetap 30 September 2026, bukan tanggal transaksi pengguna.

## Hasil yang diamati

| Gerbang | Hasil lokal | Batas interpretasi |
| --- | --- | --- |
| `npm run check:web` | ESLint, vue-tsc, 33 tes kontrak/domain, build Vite lulus | Termasuk tes item-split bersama yang sudah tersedia; bukan klaim UI R2 |
| `npm run web:e2e` | 18/18 lulus, Chromium | Demo; bukan E2E akun Supabase nyata |
| `npm run test:edge` | 7/7 lulus | HTTP upstream Auth/REST/Storage dimock |
| `deno check` tiga gateway | Lulus | Pemeriksaan source/types, bukan penerapan produksi |
| `npm run test:swift` | 4/4 lulus | Kontrak SwiftPM, bukan keseluruhan aplikasi iOS |
| `npm run test:swift:fixture` | Lulus | Nominal dan pembulatan fixture Swift |
| `npm run test:swift:typecheck` | Lulus | Source aplikasi, XCTest, UI test; bukan eksekusi perangkat |
| `sh tests/database/plain-postgres.sh` | Sembilan migrasi, seed 200 transaksi, smoke/domain/RLS dan konkurensi lulus | Bootstrap PostgreSQL 15, bukan seluruh stack Supabase/pgTAP |
| JSON dan secret scan lokal | Lulus | Tidak menggantikan gitleaks riwayat Git/CI |
| `npm audit --prefix apps/web` | 0 advisori ditemukan | Hasil saat run; bukan jaminan keamanan seluruh aplikasi |

Output terakhir disalin ke `apps/web/artifacts/verification`. Playwright HTML/trace berada di `apps/web/playwright-report` dan `apps/web/test-results`, diabaikan Git. Run CI yang ditambahkan belum dieksekusi di GitHub dalam pekerjaan ini.

## Cakupan implementasi

| Area R1 | Tersedia | Bukti/batas |
| --- | --- | --- |
| Autentikasi | Daftar, kode verifikasi/kirim ulang, masuk, kode pemulihan, kata sandi baru, refresh/logout | Adapter Supabase JS; SMTP, pembatasan 429, kedaluwarsa dan refresh nyata belum diuji |
| Onboarding dan Demo | Tunai untuk akun baru; Demo satu langkah, 200 transaksi/3 bulan, anggaran, piutang/utang, reset/keluar, contoh QR/PDF/teks | Demo memori; mutasi manual tetap bekerja setelah browser offline; tanpa API Supabase |
| Akun/kategori | Buat, ubah, arsip, kategori berurutan, aturan merchant | Domain/E2E; akun terakhir, nama ganda, kategori arsip ditolak |
| Transaksi/transfer | Buat, ubah, detail, hapus, Urungkan 10 detik; transfer dua kaki | Versi/retry dan saldo/laporan diuji; peringatan saldo negatif tidak memblokir |
| Split/pelunasan | 2–20 peserta, sama rata/nominal/persentase, pembayar Saya/teman, pelunasan sebagian, pembatalan, penghapusan kewajiban/reversal beralasan, salin ringkasan | Fixture §3.5; overpay dan perubahan struktur setelah pelunasan ditolak; konversi transaksi/review atomik |
| Impor/lampiran | JPEG/PNG QR, PDF teks, tempel teks, metadata gambar dibersihkan, pratinjau privat dan retry upload | MIME/5 MB/30 halaman; lampiran diperoleh melalui alur impor/review, bukan picker tambahan pada form manual |
| Perlu Ditinjau/duplikat | Confidence/evidence, koreksi wajib, konfirmasi transaksi atau split, Tolak/Urungkan, fingerprint, kandidat, Bukan duplikat, Gabung | Tidak ada posting sebelum Simpan; target Gabung dapat transaksi maupun bill, tanpa perubahan ledger |
| Anggaran/laporan | Bulan/tahun, kategori, arus kas per akun, tren 3 bulan, posisi bersih, status 80%/100%, zona waktu | Pelunasan bukan income/expense; write-off piutang nonkas dan porsi Saya dihitung pada tanggal kejadian |
| Filter/ekspor | Filter gabungan, halaman 30, CSV tampilan, enam CSV periode, ZIP lengkap JSON/manifest/checksum/lampiran | CSV periode cocok dengan laporan/arus kas dalam tes; kesetaraan seluruh nilai CSV native/remote belum terbukti end-to-end |
| Pengaturan/hapus | Tema sistem/terang/gelap, zona waktu, sembunyikan nominal, privasi, ekspor sensitif, autentikasi ulang dan konfirmasi HAPUS | Demo hanya reset; server gagal tertutup bila inventaris/removal Storage gagal; penyelesaian harus diverifikasi server |

HEIC perlu dikonversi pengguna ke JPEG/PNG. Gambar tanpa QR, QR tidak didukung/CRC salah, PDF scan/terkunci/tidak terbaca tetap bisa ditinjau manual dengan lampiran; batas ukuran/halaman tetap ditolak. Tidak ada kamera langsung, OCR, AI, pembayaran atau outbox offline web R1. Aset `public/demo` berasal dari fixture impor bersama, dapat diregenerasi dengan `node apps/web/scripts/generate-import-samples.mjs`; bukan bukti pembayaran nyata.

## QA visual §6.8

Folder: `apps/web/artifacts/visual`. `manifest.json` mencatat 38 PNG beserta ukuran dan SHA-256. Enam contact sheet JPG memudahkan peninjauan; versi teks 200% memperlihatkan viewport pertama, PNG penuh tetap tersedia.

Lima nama layar: `beranda`, `input`, `split-bill`, `perlu-ditinjau`, `laporan`.

| Matriks | Nama berkas | Jumlah |
| --- | --- | --- |
| Ponsel 390×844, terang/gelap | `<layar>-390-<light atau dark>.png` | 10 |
| Desktop 1440×1000, terang/gelap | `<layar>-1440-<light atau dark>.png` | 10 |
| Ponsel kecil 375×812, teks 200%, terang/gelap | `<layar>-375-text200-<light atau dark>.png` | 10 |
| Input/split 200%, viewport awal dan setelah scroll ke tombol Simpan | `<input atau split-bill>-375-text200-<tema>-<viewport atau bottom>.png` | 8 |

Peninjauan mencakup seluruh lima layar pada kedua ukuran/tema, reflow teks besar, serta close/Simpan pada dialog. Temuan/perbaikan:

- Root 15 px dan beberapa target 36 px tidak sesuai token. Body menjadi 16 px, token radius/tipografi/gerak dipetakan, tombol minimal 44×44. Plus Jakarta Sans di-host lokal dengan OFL; ikon Lucide dengan ISC.
- Pada teks 200%, kolom pemasukan/pengeluaran dan kata panjang pada tren laporan meluap. Grid adaptif dan pemenggalan teks memperbaiki reflow; pemilih periode laporan memperoleh satu baris penuh. Tidak diperbaiki dengan menyembunyikan overflow dokumen.
- Pemeriksaan lebar dokumen saja sempat melewatkan dialog yang meluap internal. Batas bawaan browser dalam `em` mengecilkan dialog; header, segmented dan nominal terpotong. Max-width eksplisit, header adaptif, segmented bertumpuk, label Rp terpisah memperbaikinya. Tes tambahan mengukur `scrollWidth/clientWidth` dialog serta lebar teks 12 digit maksimum.
- Label Pengaturan terbelah pada navigasi ponsel. Label visual menjadi **Setelan**, nama aksesibel **Setelan, Pengaturan** memuat label visual dan terminologi lengkap; desktop tetap Pengaturan. Pada teks 200%, navigasi boleh bergulir secara internal, bukan membuat dokumen melebar.
- Modal panjang dapat digulir; screenshot tambahan membuktikan tombol Simpan tidak terpotong. Header/close tetap tersedia. Screenshot full-page pada dialog bukan representasi seluruh backdrop viewport: lihat berkas `viewport`/`bottom` untuk keadaan dialog yang sebenarnya.
- Axe WCAG A/AA tidak menemukan pelanggaran pada lima layar terang/gelap 375 px ukuran teks normal. Reflow 200% diuji terpisah pada kelima layar. Focus trap, Escape, pengembalian fokus, outline 3 px, target dialog 44 px dan reduced motion diuji dengan keyboard.
- Pengukuran warna menemukan focus-ring awal hanya 2,99:1 pada primary-soft terang dan border kontrol awal terlalu samar. Warna fokus diturunkan dari token dengan campuran ink; border kontrol memakai campuran muted/surface. Uji browser mengukur pasangan fokus pada enam surface (≥3:1), muted pada surface yang sama (≥4,5:1), serta border select/textarea (≥3:1). Batas kontrol lebih jelas tanpa mengubah palet bersama.
- Tata letak desktop, jarak kartu, angka tabular, hierarki saldo vs posisi bersih, asal ekstraksi dan pesan ketidakpastian konsisten pada matriks yang diperiksa. Tidak ada nominal maksimum yang terpotong pada kasus uji dialog 200%.

**Masih terbuka:** token bersama v1.1 diubah paralel menjadi palet biru; nilai mint/peach/sun awal §6.2 berbeda. Perubahan bersama dipertahankan, bukan ditimpa. Memerlukan keputusan pemilik sebelum menyatakan kepatuhan desain final. Axe bukan audit lengkap screen reader/kontras grafis semua keadaan. Safari/Firefox, zoom browser sesungguhnya, high contrast, VoiceOver/TalkBack dan perangkat fisik belum diuji. Screenshot iOS tidak diregenerasi dalam pekerjaan web ini; status native lihat `docs/ios-r1-testing.md`.

Berkas `input-before-reflow.png` dan `split-bill-before-reflow.png` menyimpan contoh temuan sebelum perbaikan, tidak termasuk 38 screenshot akhir pada manifest. Contact sheet bukan pengganti pemeriksaan nominal/close/Simpan pada PNG viewport/bottom.

20 input cepat dan 10 split telah diulang **oleh otomasi**, bukan pengguna tanpa bantuan. Gerbang uji kegunaan manusia §6.8 belum lulus.

## Integrasi dua klien dan perbaikan backend

`tests/database/web-r1-smoke.sql` memakai RPC yang dikonsumsi kedua adapter: mutasi berlabel web dibaca dari proyeksi yang sama, koreksi berlabel iOS terlihat pada baca berikutnya, versi lama ditolak, transfer hapus/pulihkan/replay tidak menggandakan kas. Ini **simulasi kontrak dua klien di DB**, bukan peluncuran kedua aplikasi terhadap Supabase nyata.

Perbaikan yang diuji:

- FK kandidat duplikat semula hanya menunjuk transaksi. `duplicate_bill_id` memakai FK owner dan constraint satu jenis target; RPC merge bill memindahkan lampiran, mempertahankan ledger/kas, mendukung replay. Smoke memverifikasi FK target asing/tidak ada ditolak.
- Trigger validasi split tertunda gagal ketika transaksi berjalan sebagai `authenticated`, setelah RPC security-definer berakhir. Wrapper trigger sekarang security-definer dengan search_path terkunci, akses langsung publik dicabut; schema private tidak dibuka ke klien. Harness authenticated dan konkurensi lulus.
- Restore transfer tersedia melalui gateway bersama. Fingerprint sumber unik per pengguna, pagination koleksi gateway, dan batas bulan menurut timezone profil diperbaiki.
- Ekspor ZIP tidak lagi memakai spread besar yang menyebabkan stack overflow; inventaris lampiran dipaginasi, semua file harus berhasil, batas total lampiran 50 MB eksplisit. CSV numerik negatif tetap angka; teks formula di-escape.
- Hapus akun memverifikasi kata sandi, menginventaris/menghapus semua objek, memeriksa Storage kosong dan identitas Auth benar-benar hilang. Tes transport memverifikasi kegagalan fail-closed dan respons sukses yang diverifikasi, dengan upstream mock.
- PDF.js diperbarui setelah audit awal menemukan advisori; audit akhir tidak menemukan advisori npm.

## Gerbang sebelum akun nyata/rilis

1. Sediakan Supabase lokal/staging. Supabase CLI dan Docker tidak tersedia pada host run ini; pgTAP, SMTP/code, refresh, sessionStorage/tab-close, Storage HTTP/RLS dan penghapusan akun nyata belum dijalankan.
2. Jalankan web dan iOS dengan akun uji sama: create/edit/undo di masing-masing klien, polling/read klien lain, konflik bersamaan, dua pembayar, pelunasan/reversal, impor/merge bill, ekspor dan hapus dengan lampiran. SQL/mocked HTTP tidak menggantikannya.
3. Verifikasi akun kedua tidak dapat membaca/mengunduh/menghapus objek/row pertama melalui HTTP, bukan hanya constraint/RLS bootstrap.
4. Bandingkan keenam CSV/ZIP web, server dan iOS untuk semua fixture dan batas bulan/zona waktu. Header web mengikuti fixture bersama; kesamaan seluruh nilai/status antar ekspor belum dibuktikan.
5. Jalankan QA lintas browser/perangkat, screen reader, matriks native, dan 20/10 uji kegunaan manusia. G0/G1 iPhone bukan hasil tes Chromium/SwiftPM.
6. Putuskan palet bersama; implementasikan/verifikasi retensi review 30/90 hari, backup/restore, retensi cadangan, kanal dukungan, kuota SMTP/anti-abuse sebelum publikasi. Halaman privasi menyatakan yang belum tersedia.
7. Evaluasi dataset besar: backend dan daftar memakai keyset 30, tetapi filter gabungan/CSV/arus kas web memprefetch snapshot lengkap. Belum ada benchmark skala besar/delta sync.

Tidak ada deployment, commit atau branch baru yang dibuat. R2 yang dikerjakan paralel tidak menjadi klaim penyelesaian R1 web.
