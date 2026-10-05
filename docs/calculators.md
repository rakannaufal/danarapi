# Kalkulator Danarapi

38 kalkulator tersedia pada iOS dan web. Pada iOS, tab Kalkulator menggantikan
posisi Pengaturan; pengaturan dibuka melalui gear kanan atas. Header iOS memakai
logo dan wordmark Danarapi. Web menempatkan logo di sidebar, bersama menu
Pengaturan; halaman aktif ditandai dengan warna latar tanpa garis kiri.

## Katalog

| Kategori | Kalkulator |
| --- | --- |
| Belanja dan promo | Diskon, diskon bertingkat, pajak/service/tip, harga satuan, perbandingan promo |
| Biaya sehari-hari | Langganan, perjalanan, kendaraan, listrik, kos/kontrakan |
| Keuangan pribadi | Dana darurat, gaji per jam/hari, bunga majemuk, inflasi, mata uang |
| Cicilan dan utang | Pinjaman, margin tetap, pelunasan utang, rasio cicilan |
| Usaha dan penjualan | Modal/harga jual, margin/markup, titik impas |
| Zakat | Maal gabungan, penghasilan, uang/tabungan, emas, perak, perdagangan, investasi, pertanian, peternakan, rikaz, fitrah |
| Fidyah dan kafarat | Fidyah, kafarat sumpah, kafarat puasa Ramadan |
| Warisan dan wasiat | Wasiat/harta bersih, faraid |

Hitung cepat dan split bill tidak ditambahkan. Perjalanan dapat dipakai untuk
merencanakan biaya haji/umrah dengan rincian transportasi, penginapan, dan makan.

## Kontrak perhitungan

- `scripts/generate-calculator-catalog.py` menghasilkan formulir, kategori,
  metode, batas input, dan rujukan pada `contracts/calculators/catalog.json`.
- `contracts/calculators/engine.js` dipakai langsung oleh web dan JavaScriptCore
  iOS. Tidak ada implementasi rumus kedua atau panggilan AI.
- Rupiah berupa integer BigInt; desimal input memakai fixed point enam digit.
  Pembulatan biasa memakai nearest, setengah menjauh dari nol. Zakat dan harga
  minimum tertentu dibulatkan ke atas; rincian menyebut metode masing-masing.
- Anuitas memakai pangkat rasional BigInt. Jadwal menyesuaikan sisa pokok;
  angsuran tetap dengan saldo sangat kecil dapat selesai sebelum tenor penuh.
- Hasil nominal dibatasi Rp999.999.999.999. Tenor pinjaman, pelunasan, dan
  pertumbuhan dibatasi 600 bulan. Input tidak valid menghasilkan pesan tanpa
  hasil lama atau fallback angka nol.
- Harga logam, konversi sha/wasaq, tarif, kurs, serta tanggal acuan diisi pengguna.
  Aplikasi tidak menyajikan angka manual sebagai harga atau kurs langsung.

## Dalil dan batas fikih

Setiap kalkulator Islam memiliki tombol **Dalil dan metode**, berisi ringkasan
makna, nomor ayat/hadis, penilaian riwayat, tautan sumber, metode, dan asumsi.
Ringkasan tidak ditampilkan sebagai kutipan terjemahan lengkap.

Rujukan utama: Al-Qur'an 9:103, 2:267, 2:184, 5:89, 4:11, 4:12, 4:176;
Shahih al-Bukhari 1454, 1483, 1405, 1499, 1503, 4505, 1936, 2742, 6732,
6736; Sunan Abu Dawud 1573, 1576, 2870. Riwayat Abu Dawud menampilkan nama
penilai; penilaian sahih/hasan sahih tersebut tidak dinyatakan sebagai kesepakatan
seluruh ahli hadis.

Zakat penghasilan dan investasi merupakan penerapan fikih atas dalil umum,
bukan klaim ada hadis yang menyebut gaji atau saham modern secara khusus.
Penghasilan memakai metode Indonesia yang merujuk Fatwa MUI 3/2003. Pilihan
nisab, perhiasan, kewajiban pengurang, pembayaran uang, dan pengairan campuran
menyatakan adanya metode/rujukan yang perlu dipilih.

Kalkulator tidak menetapkan fidyah dari diagnosis medis, menyamakan setiap
pembatal puasa dengan kafarat Ramadan, atau membolehkan memilih puasa kafarat
hanya karena lebih murah. Konfirmasi dasar kewajiban diperlukan sebelum hasil
kewajiban muncul.

Faraid memakai simulasi Sunni Hanafi untuk ahli waris yang tersedia pada form:
pasangan, orang tua, kakek ayah, dua nenek, anak, cucu satu tingkat dari anak
laki-laki, serta saudara kandung/seayah/seibu. Menghitung hajb, bagian tetap,
asabah, umariyyatain, aul, radd selain pasangan, dan pembulatan sisa terbesar.
Total Rupiah mencakup semua bagian dan sisa yang belum dialokasikan.

Ahli waris lebih jauh, kehamilan, orang hilang, penghalang pribadi, sengketa,
atau persetujuan wasiat hanya oleh sebagian ahli waris memerlukan perhitungan
khusus. Persetujuan wasiat tidak mewakili anak atau pihak yang tidak cakap;
persetujuan harus sukarela setelah pewaris wafat. Sisa pada kasus hanya pasangan
ditampilkan untuk penetapan lebih lanjut.

## Penyimpanan dan draft

- Pencarian, kategori, favorit, reset, salin, dan bagikan tersedia.
- Maksimal 20 riwayat per akun. iOS menyimpan file terlindungi, nama berdasarkan
  hash ID pemilik, tidak masuk backup. Web memakai sessionStorage per pemilik;
  localStorage hanya untuk ID favorit.
- Pergantian akun menutup kalkulator/riwayat. iOS menutup hasil saat aplikasi
  terkunci; pembukaan riwayat tertunda memeriksa pemilik sebelum tampil.
- Simpan ke draft adalah tindakan eksplisit. UI menyebut label dan nominal yang
  dipakai; zakat investasi memakai sisa setelah pembayaran, bukan total yang
  sudah dibayar. Hasil nonmoneter atau belum memenuhi syarat tidak menawarkan
  draft pembayaran.
- Draft pending melalui API tinjauan yang sudah tersedia. Akun, jenis transaksi,
  dan nominal tetap harus dikonfirmasi; kalkulator tidak memposting ledger.

## Verifikasi perubahan

Build produksi web (vue-tsc dan Vite) serta build iPhone fisik berhasil.
Suite pengujian dan pengujian interaksi pengguna belum dijalankan pada perubahan
kalkulator ini. Build tidak membuktikan ketepatan seluruh kasus fikih.
