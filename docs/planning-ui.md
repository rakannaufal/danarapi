# Anggaran dan target — 1 Oktober 2026

## Alur

- Modal cepat: Pengeluaran, Pemasukan, Anggaran, Target, Split bill, Impor bukti. iOS mempertahankan pemindai QRIS native. Transfer dipindahkan ke halaman Transaksi, bukan dihapus dari sistem keuangan.
- Anggaran: pilih bulan dan kategori, isi limit. Sepuluh pilihan: Makan, Transportasi, Rumah, Belanja, Tagihan, Kesehatan, Pendidikan, Hiburan, Keluarga, Lainnya. Pilihan yang belum ada dibuat saat menyimpan; kategori yang sudah ada dipakai kembali. Kategori khusus dapat dibuat dengan nama sendiri. Satu kategori memiliki satu limit per bulan; penyimpanan berikutnya memperbarui limit tersebut.
- Target: nama bebas, total target, tanggal. Target baru mulai dari nol. Tambah progres membuka pengeluaran dengan kategori Target dan target terpilih; Catat baru → Pengeluaran → Target menyediakan alur yang sama. Perubahan nominal, akun, target, hapus/pulihkan transaksi ikut memperbarui saldo dan progres. Tenggat memakai hari kalender, bukan periode laporan atau tanggal seed Demo.

## Beranda dan tampilan

- Ringkasan piutang/utang/posisi bersih diganti panel Target dan Anggaran. Data kewajiban tetap ada di detail split bill dan laporan.
- Target menampilkan total terkumpul, total tujuan, progres dan countdown per target. Anggaran menampilkan seluruh kategori pada bulan terpilih di web / bulan berjalan di iOS, terpakai, limit, sisa dan kondisi melebihi batas. Tidak lagi dipotong tiga kategori.
- Web: modal pilihan dua kolom di desktop, satu kolom di ponsel; panel perencanaan dua kolom / satu kolom; judul dan keterangan dipersingkat. Fokus otomatis menuju input/pilihan pertama, termasuk saat pilihan cepat berubah menjadi formulir. Tema terang/gelap, penyembunyian nominal, fokus keyboard, sentuhan 44 px, reduced motion dan reflow mengikuti desain existing.
- iOS: label Target menggantikan Goals; formulir bertenggat, pemilihan bulan, sepuluh preset dan kategori khusus, progres dan countdown, edit target langsung dari kartu beranda. Anggaran/target akun nyata memerlukan koneksi; Demo tetap lokal.

## Penyimpanan

- Target web memakai RPC existing `api_save_goal` / `api_delete_goal`, idempotensi dan expected version. Native iOS tetap memakai repository existing. Nominal JSON berupa string desimal; penjumlahan web memakai BigInt.
- Kategori memakai `api_create_category`, anggaran memakai operasi `upsert_budget`. Pembuatan kategori dan anggaran adalah dua mutasi: jika penyimpanan limit gagal, kategori yang sudah dibuat dapat dipakai ulang tanpa duplikasi.
- Metadata target dan limit anggaran tidak memindahkan uang. Kontribusi target dan QRIS adalah pengeluaran nyata, memotong akun terpilih serta saldo agregat. Anggaran menghitung pengeluaran kategori, bukan memotong saldo kedua kali.
- Migrasi `202610010014_goal_transactions.sql` menambahkan hubungan transaksi-target, kategori fitur, view progres yang mengikuti RLS pemilik, serta konfirmasi QRIS yang tidak boleh diposting dua kali. Migrasi lama tidak diubah. Deployment produksi dan panggilan AI tidak dilakukan untuk pekerjaan ini.

## Verifikasi

- Hasil akhir: 65 tes Node dan 60 E2E Chromium/WebKit lulus. Type-check, lint dan build web lulus; source aplikasi iOS, XCTest dan UI test juga lolos pemeriksaan tipe. Tidak ada pengujian AI berbayar atau deployment produksi.

- Tes Node mencakup preset, countdown, konflik versi, replay, edit/hapus target dan anggaran lintas bulan, tanpa perubahan saldo.
- E2E Chromium/WebKit mencakup enam pilihan cepat, sepuluh kategori, kategori khusus, empat anggaran tampil sekaligus, filter bulan, target/progres/countdown, edit/hapus, aksesibilitas, tema terang/gelap dan lebar ponsel 375 px. Tes struk dan alur manual memakai endpoint scan tiruan agar tidak mengirim berkas ke Gemini.
- Source aplikasi iOS, XCTest dan UI test diperiksa tipenya. Tes countdown/preset serta nama elemen UI diperbarui. Simulator iOS lokal tidak memiliki runtime tersedia pada pemeriksaan ini, sehingga XCTest aplikasi dan UI test native belum dijalankan ulang; jangan menganggap pemeriksaan tipe sebagai verifikasi visual perangkat.
