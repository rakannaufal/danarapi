# Riwayat transaksi, pembuka iOS, dan laporan web

## Transaksi tanggal lampau

Migration `202610020017_allow_backdated_entries.sql` menghapus batas tanggal pembukaan akun dari validator bersama. Pemasukan, pengeluaran, progres target, transfer, split bill, dan pelunasan boleh memakai tanggal sebelum akun dicatat di Danarapi. Tanggal kosong/tidak valid, akun orang lain, akun tidak tersedia, dan akun arsip tetap ditolak.

Tanggal pembukaan serta saldo awal tidak diubah otomatis. Transaksi lama tetap menambah atau mengurangi saldo berdasarkan ledger; jangan memasukkan aktivitas yang sudah dihitung dalam saldo awal dua kali. Kebijakan ini sama pada web dan iOS karena diterapkan di database, bukan dilewati oleh klien.

Regresi SQL mereproduksi penolakan sebelum perbaikan, kemudian memeriksa create/update, idempotensi, pemasukan, transfer, target, split bill, pelunasan, saldo akhir, metadata saldo awal, dan akun arsip. Seluruh data uji lokal dibatalkan melalui rollback.

## Pembuka iOS

Launch screen sistem memakai aset logo dan latar adaptif. Saat sesi/data dimuat, RootView menampilkan logo dengan indikator kecil, bukan pesan jaringan gagal di belakang spinner. Error dan tindakan coba lagi hanya tampil setelah pemuatan awal benar-benar gagal. Pergantian aplikasi ke foreground tidak menjalankan refresh kedua selama inisialisasi.

Logo yang sama tersedia untuk ikon aplikasi. Tidak ada penundaan logo buatan pada build produksi. Fixture khusus DEBUG hanya aktif dengan argumen UI test `--ui-testing-startup` untuk mempertahankan keadaan pemuatan secara deterministik, tanpa timer atau penundaan. Uji model memeriksa penyelesaian startup normal; uji antarmuka memeriksa logo dan layar login secara terpisah.

## Beranda dan laporan web

- Kartu ringkas, ukuran angka bertingkat, ruang antarbagian konsisten, dan tata letak responsif.
- Pintasan saldo membuka pengelolaan akun; pemasukan/pengeluaran membuka transaksi dengan filter bulan dan jenis terkait.
- Laporan memakai grafik batang tiga bulan, diagram alokasi, diagram pemasukan/pengeluaran, kategori, anggaran, dan arus kas akun.
- Pemasukan selalu hijau; pengeluaran merah. Seri nol tetap tampil di legenda tanpa menciptakan segmen/batang palsu.
- Legenda diagram dapat dipilih dengan mouse atau keyboard untuk melihat rincian. Jumlah rupiah tetap memakai integer, bukan float keuangan.
- Sumbu dan nominal grafik mengikuti penyembunyian saldo. Periode kosong menampilkan keadaan kosong, bukan data contoh.
- Anggaran melewati limit tetap merah; mulai 70% tetap kuning. Ekspor CSV mengikuti periode terpilih.

Perubahan tampilan web memerlukan deployment Vercel tersendiri. Migration cloud tidak memublikasikan bundle web secara otomatis.

## Formulir nominal dan peserta

Label nominal iOS berada di dalam kartu dengan padding yang sama dengan input, sehingga tidak terpotong oleh sudut baris Form. Input rupiah memakai warna teks dan placeholder adaptif tanpa mengubah nilai uang yang disimpan.

Split bill baru pada web dan iOS dimulai hanya dengan peserta Saya, baik pembagian berdasarkan menu maupun total. Peserta lain ditambahkan secara manual melalui tombol ikon + berukuran minimal 44 pt/px dengan label aksesibilitas. Enter/Done pada kolom nama tetap menambahkan peserta. Peserta pada tagihan tersimpan tidak diganti. Menghapus peserta juga membersihkan pemesan menu dan pembayar terkait; menyimpan tetap memerlukan minimal dua peserta.
