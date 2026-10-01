# Pembaruan produk: goals, anggaran, laporan bulanan, split per menu

Permintaan pengguna 30 September 2026 memperbarui cakupan iOS dan backend sebelumnya. Dokumen ini melengkapi PRD v3.3; perubahan warna dan OCR di sini menggantikan pembatasan lama yang terkait.

## Goals

- Tujuan yang ingin dicapai/dibeli, nama, target Rupiah, nominal sudah terkumpul, tanggal target opsional.
- Progres baru dicatat sebagai transaksi pengeluaran dengan target terkait dan akun sumber. Membuat atau mengubah metadata target tidak mengubah saldo. Progres lama dipertahankan sebagai nilai awal; kontribusi baru dijumlahkan dari transaksi aktif, tidak menjadi saldo akun tambahan.
- CRUD akun nyata melalui RPC server, RLS pemilik, version check dan mutation UUID. Perubahan goals memerlukan koneksi; cache hanya untuk membaca. Demo berjalan lokal.
- Penghapusan akun menghapus goals melalui foreign key cascade. Ekspor JSON mencakup goals.

## Anggaran dan laporan

- Limit pengeluaran per kategori per bulan, memakai kategori yang ada atau membuat kategori pengeluaran baru langsung di editor.
- Backend menolak kategori pemasukan, kategori akun lain dan kategori yang diarsipkan untuk anggaran baru/perubahan limit.
- Dashboard hanya menjumlahkan limit anggaran pada bulan kalender sekarang di Asia/Jakarta, bukan semua periode.
- Laporan memilih bulan sebelumnya/berikutnya. Rentang `[awal bulan, awal bulan berikutnya)`; bukan laporan "sejak bulan itu sampai sekarang". Porsi Saya dan penghapusan piutang tetap mengikuti ledger sebelumnya; pelunasan tidak menjadi pengeluaran baru.
- Ringkasan laporan membedakan selisih pemasukan–pengeluaran periode dari saldo rekening saat ini. Riwayat bulan tidak ditampilkan sebagai saldo penutupan tanpa data ledger penutupan.

## Split bill per menu

- 2–20 peserta, 1–100 menu. Setiap menu memiliki nama, jumlah unit bulat 1–999, harga satuan Rupiah positif, dan jumlah unit yang dimakan tiap peserta.
- Semua unit harus dibagikan tepat sekali. Menu yang belum dibagikan/berlebih, ID ganda, peserta tidak dikenal, nominal nonkanonik atau total melebihi batas ditolak.
- Contoh: nasi 4 × Rp25.000 dan minum 2 × Rp15.000. A: 1 nasi + 1 minum = Rp40.000; B: 2 nasi + 1 minum = Rp65.000; C: 1 nasi = Rp25.000. Total Rp130.000.
- Pajak, layanan dan diskon nominal dibagi proporsional terhadap subtotal menu. Hitung `floor(total_final × subtotal_peserta / subtotal_menu)`; sisa Rupiah menurut sisa terbesar, seri menurut urutan peserta. Ini aturan baru yang eksplisit, bukan asumsi tersembunyi iOS.
- PostgreSQL memvalidasi seluruh hasil sebelum posting, membungkus RPC ledger lama secara atomik. UUID peserta dinormalisasi ke representasi PostgreSQL agar UUID huruf besar iOS tidak merusak relasi alokasi. Constraint deferred melindungi konsistensi item/porsi meskipun RPC lama dipakai. Metadata item dikunci setelah pelunasan/penghapusan aktif.
- Calculator dan trigger validasi berjalan dengan `SECURITY DEFINER` dan search path tetap, tanpa memberikan akses schema `private` kepada akun aplikasi. Migration `008` memperbaiki konteks trigger deferred split sebelumnya. Smoke test menggunakan role `authenticated`, termasuk commit constraint, UUID iOS huruf besar dan penolakan kategori anggaran yang tidak valid.
- Detail menu disimpan bersama tagihan dan diekspor dalam JSON. Pembayaran, piutang/utang, pelunasan, reversal tetap memakai ledger sebelumnya. Dashboard mengganti kartu piutang/utang dengan goals dan total anggaran; data kewajiban tidak dihapus dari sistem.
- Pembagian total saja/sama rata/manual tetap tersedia. Unit pecahan atau satu item dibagi setengah belum didukung; pengguna dapat membuat baris porsi terpisah dengan nominal yang ditinjau.

## Struk dan keamanan draft

- OCR Apple Vision lokal pada foto/kamera; PDF berlapis teks dan teks tempelan menghasilkan draft menu. Pemindai tidak menentukan peserta otomatis, tidak menyimpan pengeluaran atau memproses pembayaran.
- Parser mendukung baris seperti `Nasi 4 x 25000 100000`, `Nasi 4 25000 100000`, atau `Nasi 4 100000` (angka terakhir total baris). Format ambigu/angka tidak konsisten bisa tidak dikenali. Seluruh jumlah/harga wajib ditinjau pengguna; hasil OCR bukan bukti pembayaran.
- Pajak/layanan/diskon tetap diisi/diperiksa manual. Foto langsung di formulir split dipakai lokal untuk ekstraksi; gambar asli tidak otomatis diunggah/disimpan. Jalur impor Perlu Ditinjau tetap menyimpan lampiran privat saat pengguna menyimpan draft.
- Foto/teks hasil OCR tidak dipakai melatih model atau dikirim ke layanan OCR eksternal. Kamera fisik, struk nyata multi-kolom/buram dan berbagai bahasa tetap perlu pengujian perangkat.

## Desain

Putih/navy untuk permukaan dan teks, biru sebagai primary, aksen biru lembut terbatas. Merah hanya untuk kesalahan/limit/status pengeluaran ketika diperlukan. Token bersama diperbarui; font sistem Apple dengan judul/nominal rounded, kartu continuous radius 26, kontrol 18, angka satu baris dengan skala minimum, header compact, Dynamic Type, VoiceOver dan native navigation dipertahankan.

## Artefak kontrak

`contracts/v1/planning.schema.json`, `tests/fixtures/item-split-v1.json`, migration `202609300008_goals_item_split.sql`. Fixture sama dijalankan oleh PostgreSQL, Swift dan TypeScript. Status eksekusi ada pada `docs/ios-r1-testing.md`; type-check tidak menggantikan pengujian runtime atau integrasi Supabase.
