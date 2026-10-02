# Antarmuka web dan konten bantuan

## Tata letak

- Web memakai font sistem, palet teal/mint/peach dan kanvas putih/navy, radius konsisten, serta ruang antarkartu yang seragam. Token dasar tetap berasal dari `contracts/design-tokens.json`; pemetaan aset terdapat pada `docs/brand-assets.md`.
- `apps/web/src/interface.css` menjadi lapisan antarmuka akhir. CSS grafik dan komponen khusus mempertahankan perhitungan, label aksesibilitas, serta perilaku formulir.
- Beranda menggunakan empat kartu ringkasan berukuran sama. Target/anggaran dan catatan/akun berpasangan dengan kolom dan tinggi yang seimbang.
- Grid menyesuaikan desktop, tablet, dan ponsel. Angka tetap memakai digit tabular; formulir dan halaman bantuan mendukung pembesaran teks.
- Tema terang/gelap, keadaan kosong, indikator pemuatan, pesan kesalahan, fokus keyboard, dan preferensi pengurangan gerakan tetap tersedia.

## Akses fitur

| Fitur | Akses pada web |
| --- | --- |
| Akun dan saldo | Navigasi Akun keuangan atau kartu saldo beranda |
| Transfer antar akun | Halaman Akun keuangan; memerlukan dua akun aktif |
| Pemasukan dan pengeluaran | Catat baru, kartu ringkasan, atau Transaksi |
| Target dan kontribusi | Navigasi Target, kartu beranda, dan aksi progres |
| Anggaran bulanan | Navigasi Anggaran, 10 kategori siap pakai atau kategori sendiri |
| Struk dan QRIS | Scan/tinjauan; pilihan kamera, galeri, dan PDF khusus struk |
| Split bill | Catat baru; perincian menu, pemesan, service, pajak, dan pembulatan |
| Laporan | Tren, diagram alokasi, pemasukan/pengeluaran, arus kas, dan ekspor periode |
| Data dan bantuan | Pengaturan, Tentang, FAQ, kontak, kebijakan, dan status layanan |

Tombol foto web menggunakan pemilih kamera perangkat melalui `capture="environment"`. Perilaku kamera bergantung browser/perangkat; pada desktop pemilih berkas dapat tampil. Galeri tetap menjadi alternatif. Dalam mode QRIS, hasil bukan QRIS ditolak sebelum pengiriman ke AI.

## Satu sumber konten

`contracts/product-content.json` menyimpan halaman, fitur, FAQ, panduan awal, tautan, dan topik laporan masalah. Web mengimpor kontrak yang sama dengan sumber resource `product-content.json` pada proyek iOS.

- Tentang menjelaskan fitur aktual, data Demo, login Google, dan batas aplikasi sebagai pencatat, bukan layanan pembayaran.
- Bantuan menyediakan pencarian, filter topik, panduan awal, dan keadaan tanpa hasil.
- Kontak menggunakan topik laporan dan pesan keamanan yang sama. Alamat dukungan hanya ditampilkan apabila tersedia dari konfigurasi layanan; alamat tidak dibuat-buat.
- Nama layanan teknis digeneralisasi menjadi layanan cloud, hosting, dan AI eksternal. Google tetap disebut untuk login. Penjelasan persetujuan AI, penggunaan data, dan retensi tetap tersedia; versi persetujuan tidak berubah.

## Batas kesetaraan platform

Fitur pencatatan utama memakai model dan layanan cloud yang sama. Mekanisme perangkat tidak dipaksakan menjadi identik: iOS memiliki Keychain, penguncian perangkat, cache, dan antrean offline; web memiliki sesi per tab dan preferensi/draft browser. Scan AI tetap memerlukan internet. Bantuan menjelaskan perbedaan tersebut.

## Verifikasi

Suite web mencakup simetri kartu, navigasi, scan Struk/QRIS, konten bantuan, berbagai lebar viewport, tema, pembesaran teks, dan aksesibilitas. Pengujian browser memakai server terpisah agar konfigurasi server pengembangan pengguna tidak memengaruhi mock scan.

Hasil verifikasi lokal pada 2 Oktober 2026:

- Lint, pemeriksaan TypeScript, 93 unit test, validasi JSON, dan build web berhasil.
- 146 skenario browser Chromium/WebKit berhasil dalam dua kelompok tanpa tumpang tindih: 44 pemeriksaan antarmuka/bantuan dan 102 regresi fitur.
- Viewport 320, 390, 834, dan 1440 piksel, tema terang/gelap, serta pembesaran teks 200% diperiksa. Kartu ringkasan dan pasangan panel beranda memiliki dimensi serta posisi angka yang sejajar.
- Tombol scan ponsel diperiksa pada keadaan aktif: 56 piksel, menonjol di atas navbar, warna utama tetap tampil, dan tidak terpotong.
- Pemeriksaan pola rahasia serta `git diff --check` berhasil. Build masih memberikan peringatan ukuran bundle utama di atas 500 kB; bukan kegagalan build.

Pengujian browser memakai Demo, fixture, dan mock layanan; bukan verifikasi login Google nyata atau ekstraksi AI pada akun produksi. Percobaan sebelumnya terhambat ruang disk sementara. Verifikasi akhir menonaktifkan trace browser untuk membatasi penulisan disk dan seluruh skenario berhasil.

Sesuai permintaan, tidak dilakukan build, pengujian, instalasi, atau pengoperasian aplikasi iOS untuk perubahan ini. Pembaruan resource bantuan iOS berlaku pada build berikutnya. Tidak ada migrasi database atau deployment otomatis dalam pekerjaan antarmuka ini.
