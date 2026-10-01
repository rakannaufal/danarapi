# Transaksi, target, QRIS, laporan — 1 Oktober 2026

## Perilaku keuangan

- Merchant menampilkan `opsional` pada baris label, bukan baris terpisah.
- Target baru mulai dari nol. Formulir target hanya mengatur nama, nominal tujuan, tenggat. Tombol Tambah progres atau Catat baru → Pengeluaran → kategori Target → pilih target mencatat kontribusi pada akun sumber.
- Progres adalah nilai awal historis ditambah seluruh pengeluaran aktif yang terhubung ke target. Edit, hapus dan pemulihan transaksi mengubah progres serta saldo. Penghapusan metadata target melepaskan hubungan, tidak mengembalikan uang yang sudah dikeluarkan.
- Limit anggaran merupakan rencana, bukan pengeluaran. Transaksi kategori tersebut memperbarui anggaran bulan transaksi. Bar normal di bawah 70%, kuning mulai 70% termasuk tepat 100%, merah hanya ketika melebihi limit. Status tetap dapat dibaca tanpa mengandalkan warna.
- QRIS selalu pengeluaran dengan kategori QRIS. Pemindaian menghasilkan draft; pengguna tetap memeriksa nominal dan akun lalu mengonfirmasi pencatatan. Aplikasi tidak memproses pembayaran QRIS. Satu draft tidak dapat dikonfirmasi dua kali, termasuk dengan ID mutasi baru.
- Saldo akun sumber dan total saldo mengikuti ledger yang sama. Transfer serta pelunasan split bill mempertahankan aturan existing tanpa pengeluaran ganda.

## Laporan

- Diagram alokasi memakai pengeluaran aktual pada periode terpilih, bukan jumlah limit atau jumlah tujuan.
- Kontribusi target dipisahkan per nama target. Sisa pengeluaran kategori yang memiliki anggaran pada periode tersebut ditandai Anggaran; QRIS dan kategori lain tetap muncul sendiri.
- Kontribusi target dikurangkan dari total kategori sebelum membuat segmen kategori/anggaran. Jumlah segmen tepat sama dengan pengeluaran pribadi. Split bill memakai porsi pribadi; penghapusan/pembalikan tidak ikut dihitung.
- Diagram pemasukan/pengeluaran dan grafik perbandingan tiga bulan melengkapi rincian angka. Keadaan kosong, tema gelap, penyembunyian nominal dan tata letak ponsel tetap didukung.

## Navigasi beranda iOS

- Kartu Saldo akun membuka halaman Akun, dengan rincian saldo setiap akun dan pengelolaannya.
- Kartu Pemasukan/Pengeluaran membuka halaman Transaksi dengan jenis terkait dan periode Bulan ini. Detail pengeluaran split bill memakai porsi pribadi ketika dilihat pada filter Pengeluaran.
- Halaman memakai navigation stack beranda yang sama, sehingga tombol kembali tetap membawa pengguna ke beranda. Kategori, akun dan periode tetap bisa diubah melalui filter.
- Transaksi bulan berjalan dimuat melewati halaman awal apabila diperlukan; angka beranda dan daftar tidak bergantung hanya pada 30 transaksi pertama.

## Login dan prasyarat cloud

- UI login hanya Google. iOS menggunakan browser sistem, PKCE S256, token disimpan di Keychain; web menggunakan PKCE dan sesi per tab.
- Penghapusan akun meminta konfirmasi OAuth baru maksimal lima menit dan tetap memerlukan persetujuan tindakan permanen. Identitas konfirmasi harus sama dengan pemilik sesi sebelumnya. Password tidak diminta di UI.
- Aktifkan Google pada Supabase Auth. Masukkan kredensial provider hanya di konfigurasi server; jangan tanam client secret atau private key di aplikasi. Nonaktifkan login email/password pada dashboard provider jika kebijakan produksi memang hanya OAuth.
- Daftarkan URL web produksi dan `id.danarapi.app://auth/callback` dalam allowlist redirect. Konfigurasi Apple Service ID/domain/key dan Google client sesuai proyek masing-masing.
- Pasang konfigurasi Supabase publik untuk web/iOS, terapkan migrasi sampai `202610010014_goal_transactions.sql`, lalu deploy fungsi ledger dan ios-data.
- Konfigurasi cloud belum tersedia pada workspace ini. Login provider nyata, deployment backend dan ekstraksi AI produksi belum terverifikasi. Demo serta tes lokal tidak membuktikan integrasi provider produksi.

## Validasi

Tes mencakup ledger target, replay, edit akun, hapus/pulihkan, metadata target, kategori QRIS, pencegahan pencatatan ulang, ambang anggaran, rekonsiliasi alokasi, batas periode, PKCE dan isolasi identitas. Database sementara dipakai untuk migrasi, RLS, konkurensi serta backup/restore. Pengujian perangkat memakai data demo terisolasi.

Hasil akhir 1 Oktober 2026:

- Web: 76 tes unit, 80 E2E Chromium/WebKit, type-check, lint dan production build lulus. E2E mencakup tema terang/gelap, aksesibilitas, format rupiah dan tata letak ponsel.
- iPhone Rakan: 47 XCTest aplikasi dan 6 tes UI lulus tanpa kegagalan. Alur akun/pemasukan/pengeluaran dari beranda, tambah target, progres target, kategori anggaran, pengeluaran, pemindai/navbar diuji. Result bundle: `/tmp/danarapi-features-final-20261001.xcresult`.
- Backend: Deno check ios-data, ledger dan export-data lulus; 17 tes transport, OAuth dan retention lulus.
- PostgreSQL 15: seluruh migrasi sampai 014, ledger, RLS, QRIS tanpa duplikasi, progres target, konkurensi dan backup/restore lulus pada database sementara. Log: `/tmp/danarapi-planning-database3.log`.
- JSON dan pemeriksaan pola secret lulus. Artefak `/tmp` sementara, bukan bukti deployment produksi.
