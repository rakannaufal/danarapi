# Input nominal rupiah

Web dan iOS menampilkan pemisah ribuan saat mengetik: `5000` menjadi `5.000`.
Penyimpanan, API, dan perhitungan tetap menggunakan angka tanpa titik.

- Berlaku untuk transaksi, transfer, akun, anggaran, target, split bill, pelunasan, harga menu, dan koreksi struk.
- Diskon dan biaya struk menggunakan format yang sama; pembulatan mendukung nilai negatif.
- Kolom kosong tetap dapat diedit; nilai nol ditampilkan `0`. Maksimal 12 digit nominal.
- Tempelan `Rp 5.000` dinormalisasi menjadi nilai `5000`.
- Kursor mengikuti posisi digit. Menghapus pemisah ribuan turut menghapus digit terdekat sesuai arah penghapusan.
- Persentase, jumlah menu, tanggal, urutan kategori, dan kode autentikasi tidak diubah.
- Hasil ekstraksi yang belum terbaca tetap kosong, bukan diubah menjadi nol.
