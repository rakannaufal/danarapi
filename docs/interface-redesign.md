# Antarmuka minimalis

## Arah desain

Identitas Danarapi dipertahankan. Antarmuka memakai font sistem, permukaan netral, aksen biru, garis halus, dan radius konsisten. Prinsip yang sama berlaku pada web dan SwiftUI, tanpa mengubah perhitungan atau format API.

## Perubahan

- Beranda: saldo utama, ringkasan periode, target, dan anggaran menjadi fokus.
- Transaksi: pencarian langsung, filter tambahan dapat dibuka sesuai kebutuhan.
- Tinjauan: impor ringkas; rincian, selisih angka, dan koreksi tetap tersedia.
- Anggaran web: ringkasan dan daftar muncul sebelum formulir. Tambah dan ubah membuka editor dengan 10 kategori bawaan serta kategori khusus.
- Target: progres, nominal, tanggal, dan countdown tetap terlihat.
- Laporan: angka dan grafik didahulukan, penjelasan dipindahkan ke detail yang dapat dibuka.
- Pengaturan, autentikasi, privasi, split bill, dan modal memakai sistem tampilan yang sama.
- Nama penyedia AI tidak ditampilkan pada antarmuka. Pemberitahuan layanan eksternal serta risiko data sensitif tetap terlihat sebelum pemilihan foto; keterangan lebih lengkap tersedia pada Privasi foto.
- Konfirmasi penghapusan, penguncian, masalah validasi, dan status offline tidak disembunyikan.

## Batas verifikasi

Pengujian browser memeriksa halaman utama, formulir, mode terang/gelap, layar kecil, aksesibilitas, dan alur transaksi. Pemeriksaan sumber iOS tidak menggantikan pengujian visual pada simulator atau perangkat. Perubahan antarmuka bukan verifikasi kesiapan operasional backend produksi.
