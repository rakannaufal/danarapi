# PRD Danarapi v3.3 — Pencatat Keuangan Pribadi

**Tanggal:** 30 September 2026  
**Status:** Spesifikasi produk terpadu untuk implementasi; target portofolio  
**Pemilik produk:** Rakan Naufal  
**Platform:** iOS native (Swift + SwiftUI) sebagai aplikasi utama; web (Vue 3 + TypeScript) sebagai aplikasi pendamping; backend bersama; Android diputuskan kemudian  
**Bahasa awal:** Indonesia · **Mata uang awal:** Rupiah · **Zona waktu awal:** Asia/Jakarta

> Revisi ini menggantikan v3.2. Danarapi memakai dua aplikasi native/web dalam **satu repositori** dengan satu backend dan kontrak data; seluruh ketentuan split bill R1 dipertahankan. PRD Mapan v3.0 dan keputusan Mapan v2.2 adalah asal historis, bukan dokumen yang perlu dibaca untuk mengimplementasikan v3.3. Ketersediaan `danarapi.com`, hak merek, dan pembelian domain belum terverifikasi. Target waktu/performa adalah sasaran perencanaan, bukan hasil pengukuran.

### Perubahan arsitektur v3.2 dan desain v3.3

| Area yang sebelumnya kurang jelas | Keputusan yang berlaku |
| --- | --- |
| Framework iOS masih berupa pembungkus web | UI iOS dibangun native dengan SwiftUI; web tetap Vue 3. Tidak ada UI bersama yang dipaksakan. |
| Aturan uang bisa berbeda di dua bahasa | PostgreSQL/RPC memegang keputusan finansial; kontrak versi dan fixture emas menguji Swift, TypeScript, dan server. |
| Offline menyebut enkripsi tanpa mekanisme native | SwiftData + Data Protection pada seluruh store/sidecar, Keychain untuk sesi, dengan gerbang uji perangkat dan fallback aman. |
| Logout bertentangan dengan antrean offline pending | Sinkronkan atau buang dengan konfirmasi sebelum logout; sesi kedaluwarsa hanya dapat dilanjutkan oleh akun yang sama. |
| Pembaruan backend dapat memutus iOS versi lama | Migrasi additive, uji kompatibilitas, staging, flag, dan urutan rilis server→klien. |
| Demo dan parser bisa menghasilkan angka berbeda | Seed dan fixture lintas platform yang sama, dites di kedua klien dan server. |
| Urutan kerja masih web dahulu walau iOS prioritas | Fondasi backend dahulu, kemudian iOS native inti, web inti, impor pada keduanya, dan pengerasan R1. |
| Arah visual masih umum dan berisiko terasa kaku | Sistem desain v3.3 menetapkan palet cerah yang terukur, tipografi ramah, contoh layar, komponen, gerak, dan gerbang QA visual untuk web serta iOS. |

## 1. Ringkasan keputusan dan batas produk

Danarapi membantu seseorang **mencatat dan memahami** uang masuk, uang keluar, serta perpindahan antar akun miliknya. Input bisa manual atau dibantu pembacaan QRIS, bukti pembayaran, teks, dan PDF. Semua hasil pembacaan harus ditinjau sebelum menjadi transaksi. Danarapi **bukan aplikasi pembayaran, bank, penyedia jasa pembayaran, penghubung rekening, atau alat verifikasi pembayaran**. Saldo adalah catatan pengguna, bukan saldo terverifikasi dari lembaga keuangan.

| Topik | Keputusan yang dipakai |
| --- | --- |
| Tujuan awal | Proyek portofolio yang benar-benar dapat dicoba; tidak menjanjikan kesiapan operasional publik. |
| Rilis | R1 terdiri dari iOS native dan web responsif. Backend/domain server dibuat dahulu, iOS inti dikerjakan sebelum web inti; masing-masing punya kriteria selesai sendiri. Distribusi publik iOS mengikuti gerbang akun/perangkat. |
| Web | Vue 3 + TypeScript + Vite; input manual, unggah gambar/PDF, tempel teks, tinjau, kelola, split bill, laporan, ekspor. **Tidak menggunakan kamera langsung** pada R1. |
| iOS | Aplikasi **Swift + SwiftUI native**; alur R1 mandiri dengan kamera QRIS/foto, pemilih Foto, pengunci aplikasi, haptics, cache baca dan antrean perubahan transaksi. Tidak memakai Capacitor atau WKWebView sebagai UI utama. |
| AI | Tidak menggunakan AI generatif. OCR klasik/Apple Vision opsional pada R2 dan mati secara default. Pemindaian QR klasik bukan fitur AI generatif. |
| Penyimpanan | Supabase Auth, PostgreSQL dengan RLS, Storage privat dan fungsi ledger atomik; adapter repository terpisah di Swift dan TypeScript; Demo mandiri per platform dari fixture bersama tanpa akun/server. |
| Distribusi | Tidak memasukkan TestFlight, App Store, domain sendiri, Share Extension, push server, atau email masuk sebagai syarat R1. |
| Lisensi dan hosting | Periksa ketentuan layanan dan batas kuota sebelum membuat demo publik; demo tanpa akun tetap berjalan tanpa backend. |
| Nama dan domain | Gunakan Danarapi untuk UI, README, dan paket aplikasi. Domain `danarapi.com` hanya kandidat sampai pengecekan registrar dan pembelian; URL `*.vercel.app` tetap cadangan. |
| Arah desain | Minimalis dan cerah, dengan permukaan netral hangat, aksen pastel, tombol hijau kontras, sudut lembut, angka mudah dipindai, dan tema gelap. Web memakai Plus Jakarta Sans; iOS memakai font sistem Apple dengan judul `.rounded`. Token, layar rujukan, dan gerbang QA ada di §6. |

### 1.1 Masalah, pengguna, dan nilai

Masalah utama: catatan transaksi tercecer, memasukkan ulang bukti bayar terasa lambat, pengeluaran per kategori sulit dipantau, dan saldo sering salah karena transfer, tagihan bersama, atau duplikat. Pengguna awal ialah individu di Indonesia yang mengelola keuangan pribadi dalam Rupiah. Peninjau portofolio adalah pengguna sekunder yang ingin mencoba alur tanpa memberi data atau membuat akun. Tidak ada peran admin yang dapat melihat isi data keuangan pengguna melalui aplikasi.

**Nilai inti:** pengguna dapat mencatat transaksi secara cepat, membagi tagihan dan memantau pelunasannya, meninjau hasil ekstraksi yang belum pasti, melihat saldo serta anggaran yang konsisten, lalu mengekspor atau menghapus datanya.

### 1.2 Sasaran terukur

| Ukuran | Target R1 | Cara ukur |
| --- | --- | --- |
| Keberhasilan transaksi manual | ≥ 95% dari 20 percobaan uji tanpa bantuan | Uji kegunaan pada beberapa ukuran layar. |
| Waktu catat cepat | Median ≤ 10 detik untuk nominal, akun dan kategori bawaan yang sesuai; ambisi 5 detik | Dari tombol `+` hingga konfirmasi simpan pada perangkat uji, tanpa jaringan lambat. |
| Integritas saldo | 100% skenario uji properti dan rekonsiliasi deterministik lulus | Pengujian domain, split bill, migrasi, dan sinkronisasi. |
| Ketepatan split bill | 0 selisih pembagian dan 0 pembayaran ganda pada fixture wajib | Uji pembulatan, pelunasan sebagian, edit, hapus, retry, dan dua tipe pembayar. |
| Isolasi data | 0 akses silang dalam matriks uji RLS dua pengguna | pgTAP dan uji Storage/RPC. |
| Impor tanpa salah simpan | 0 hasil parser langsung menjadi transaksi tanpa tinjauan | E2E semua sumber impor. |
| Kesiapan demo | Alur contoh bekerja tanpa login/server | E2E dengan koneksi diblokir. |
| Performa awal | JS web rute awal ≤170 KB gzip; cold start iOS native target <2,5 detik | Bundle analyzer web CI dan pengukuran pada iPhone uji; target iOS tidak diklaim lulus tanpa perangkat. |

## 2. Cakupan rilis dan prasyarat

**R1 wajib:** akun email+katasandi dengan verifikasi kode, mode demo, onboarding, akun keuangan, kategori, aturan merchant sederhana, tambah/ubah/hapus transaksi, transfer, split bill dan pelunasan manual, lampiran privat, pencarian/filter, QRIS iOS dari kamera dan gambar, gambar/PDF/teks impor, kotak Perlu Ditinjau, peringatan duplikat, anggaran, laporan dasar, CSV, ekspor data lengkap, hapus akun, tema terang/gelap, sistem desain §6, privasi layar iOS, cache baca dan antrean transaksi iOS, pengujian keamanan dan QA visual.

**R2:** OCR opsional, impor CSV mutasi, target tabungan dan kalkulator, transaksi berulang, peringatan anggaran lokal, MFA, daftar perangkat/cabut sesi, favorit, pembagian kategori/item struk dalam satu bill, edit massal web, XLSX/PDF/cetak, bahasa Inggris, sinkron delta lengkap. Setiap fitur R2 memiliki spesifikasi ringkas pada §11.

**Bergantung prasyarat:** TestFlight/App Store, Share Extension, push server dan Universal Links memerlukan kesiapan distribusi/akun/konfigurasi yang relevan; email invoice masuk dan domain bermerek perlu domain serta layanan penerimaan email. Implementasi dan kebijakan platform diverifikasi lagi menjelang pengerjaan.

**Di luar cakupan:** pembayaran QRIS dalam aplikasi, cek saldo bank otomatis, akses akun bank/e-wallet, validasi bukti bayar terhadap bank, kolaborasi real-time dan undangan akun peserta split bill, multi mata uang, rekomendasi investasi/kredit, penangkap notifikasi Android, iklan, marketplace, AI generatif, pembacaan SMS pribadi.

| Gerbang | Keputusan operasional |
| --- | --- |
| G0 Mac + Xcode | Wajib sejak awal pembuatan aplikasi SwiftUI dan untuk CI/build iOS; backend dan web dapat dikerjakan terpisah. |
| G1 iPhone uji | Kamera QR, izin Foto, Face ID/Touch ID nyata, dan performa harus diuji di perangkat; Simulator memakai file contoh. |
| G2 akun distribusi Apple | Syarat tahapan distribusi dan kemampuan tertentu; cek kebutuhan capability aktual sebelum menjadwalkan fitur. |
| G3 domain + email transaksional | Syarat alamat bermerek/email masuk/Universal Links; verifikasi email R1 memakai kode. |
| G4 akun distribusi Android | Hanya diperlukan bila Android dipublikasikan melalui Play Store. |

**Kriteria gerbang:** fase iOS tidak dinyatakan selesai sebelum G0 dan G1 tersedia dan pengujian perangkat lulus. Jika G0/G1 tertunda, backend serta web dapat dikerjakan, tetapi status iOS tetap belum terverifikasi. Demo pada kedua aplikasi tidak bergantung pada Supabase; web demo tidak bergantung G0–G4.

### 2.1 Cakupan dua aplikasi pada R1

| Fitur | Web Vue | iOS SwiftUI | Catatan sumber kebenaran |
| --- | --- | --- | --- |
| Auth email/OTP, akun, kategori, transaksi, transfer | Ya | Ya | Supabase Auth dan ledger/RLS sama. |
| Split bill, pelunasan, penghapusan kewajiban, anggaran/laporan | Ya | Ya | RPC atomik dan fixture §3.5 sama; UI terpisah. |
| Mode Demo tanpa akun/server | Ya | Ya | Seed dan kasus hitung sama, implementasi lokal berbeda. |
| QRIS dari gambar, teks/PDF dan review | Ya | Ya | Parser tiap bahasa lulus fixture sama; tidak otomatis posted. |
| Kamera QRIS/foto langsung | Tidak R1 | Ya, izin saat digunakan | Pembayaran tetap dikonfirmasi manual. |
| Ekspor CSV/ZIP, hapus akun | Ya | Ya | Job server sama; cara berbagi/unduh sesuai platform. |
| Cache dan outbox akun nyata | Tidak R1 | Terbatas transaksi/transfer R1 | Server tetap sumber akhir; split bill akun nyata online. |
| Face ID/Touch ID dan privasi app switcher | Tidak berlaku | Ya | Hanya pengunci lokal, bukan MFA server. |

Kedua aplikasi memiliki layar yang secara fungsi setara tetapi tidak harus identik secara visual. Kriteria penerimaan §5 berlaku pada keduanya kecuali ditandai iOS/web. Dokumentasi dan video demo menyebut keterbatasan masing-masing secara jujur.

## 3. Model keuangan yang wajib konsisten

### 3.1 Definisi

- **Akun keuangan:** wadah catatan, misalnya Tunai, Bank, E-wallet. Satu pengguna memiliki ≥ 1 akun; onboarding membuat **Tunai** saja. Pengguna boleh menambah akun lain. Saldo awal opsional, default Rp0. Jenis akun hanya label; tidak membuat integrasi bank.
- **Transaksi tercatat:** pemasukan, pengeluaran, transfer, dan kejadian kas dari split bill dengan status `posted`. Hanya kejadian posted dihitung. Draft dan item tinjauan tidak dihitung; aturan split bill khusus ada pada §3.5.
- **Transfer:** satu operasi atomik dengan akun asal ≠ tujuan dan nominal positif; mengurangi asal dan menambah tujuan dengan nominal sama, serta tidak mengubah kekayaan total atau laporan pemasukan/pengeluaran. Transfer tidak punya kategori anggaran.
- **Penyesuaian saldo:** koreksi oleh pengguna yang dibuat sebagai transaksi khusus `adjustment` dengan alasan wajib dan efek saldo eksplisit. Tidak diklasifikasikan sebagai pemasukan/pengeluaran; muncul di riwayat dan ekspor. R1 memungkinkan mengubah saldo awal sebelum ada transaksi; setelahnya gunakan penyesuaian.
- **Nominal:** integer Rupiah positif, disimpan sebagai `bigint` di basis data dan sebagai string desimal pada batas JSON. Dilarang float, nominal nol, pecahan, NaN, overflow, atau nilai melebihi batas produk Rp999.999.999.999 per operasi. Tampilan negatif saldo diperbolehkan dan diberi penanda.
- **Waktu:** simpan `occurred_at` dan `created_at` sebagai UTC, serta `timezone` pengguna IANA (awal `Asia/Jakarta`). Kelompok hari/bulan laporan memakai zona waktu pengguna ketika laporan dijalankan. Perubahan zona waktu dapat mengubah kelompok periode, tidak mengubah instant transaksi. R1 tidak mendukung mata uang selain IDR.

### 3.2 Rumus dan aturan

`saldo_akun = saldo_awal + Σ pemasukan_kas_posted − Σ pengeluaran_kas_posted + Σ transfer_masuk − Σ transfer_keluar + Σ penyesuaian_kas − Σ split_dibayar_pengguna + Σ pelunasan_split_diterima − Σ pelunasan_split_dibayar`. Kejadian nonkas (porsi pribadi split, piutang/utang, penghapusan kewajiban) tidak masuk rumus saldo akun. `saldo_total_akun = Σ saldo_akun_aktif_dan_arsip`. Akun yang diarsip tetap termasuk bila saldonya tidak nol. `posisi_bersih = saldo_total_akun + piutang_split_tersisa − utang_split_tersisa`. Saldo akun adalah **uang yang tercatat pada akun**, sedangkan posisi bersih adalah estimasi kekayaan setelah hak/tagihan split bill; keduanya diberi label berbeda di UI. Laporan pemasukan/pengeluaran pribadi mengecualikan transfer, penyesuaian kas, pelunasan split, draft, item ditolak, dan transaksi terhapus; laporan tersebut memasukkan porsi Saya saat bill diposting serta penghapusan piutang sebagai expense nonkas atau pembebasan utang sebagai income nonkas. Pengeluaran pribadi dari split bill dihitung sebesar porsi pengguna pada tanggal tagihan, sekali saja.

Saldo awal merepresentasikan keadaan pada tanggal pembuatan akun. Transaksi lebih lama dari tanggal tersebut tidak diizinkan untuk akun itu sampai pengguna mengganti tanggal pembukaan; jika perlu impor riwayat lama, buat akun dengan tanggal pembukaan lebih awal. Koreksi transaksi posted memperbarui seluruh agregat secara atomik. Semua laporan menggunakan data terotorisasi yang sama dengan riwayat; cache agregat boleh dipakai hanya bila invalidasi akurat.

Kategori berjenis `income` atau `expense`, milik pengguna atau bawaan yang disalin ke ruang pengguna. Pengeluaran wajib punya kategori, dengan fallback “Lainnya”; pemasukan fallback “Pemasukan lain”. Kategori yang pernah dipakai hanya boleh diarsip atau digabung secara eksplisit; transaksi lama tetap memiliki rujukan kategori yang valid. Penghapusan akun dengan transaksi berarti arsip, bukan cascade tersembunyi; penghapusan permanen hanya melalui hapus akun keseluruhan.

### 3.3 Anggaran

Anggaran per kategori pengeluaran dan periode kalender bulanan, satu anggaran aktif per kategori/periode, dengan limit integer positif. Pengeluaran posted dihitung berdasarkan `occurred_at`; refund berupa koreksi/pemasukan tidak otomatis mengurangi belanja kategori pada R1. Pengguna mengoreksi pengeluaran asal bila ingin membatalkannya. Perubahan limit berlaku segera; bar 100%+ boleh melampaui panjang visual dengan label angka sesungguhnya. Pada batas 80% dan 100%, R1 menampilkan status dalam aplikasi tanpa menjanjikan notifikasi sistem. Anggaran agregat seluruh kategori adalah jumlah pengeluaran posted biasa ditambah **porsi pengguna pada split bill posted** pada tanggal tagihan dan piutang yang dihapuskan pada tanggal keputusan, sesuai kategori masing-masing; pembayaran awal dan pelunasan tidak dihitung lagi. Piutang/utang tidak memengaruhi batas anggaran.

### 3.4 Contoh yang harus lulus

Saldo awal Tunai Rp100.000, Bank Rp200.000; pengeluaran Tunai Rp25.000; transfer Bank→Tunai Rp50.000; pemasukan Bank Rp10.000: saldo Tunai Rp125.000, Bank Rp160.000, total Rp285.000, pengeluaran Rp25.000, pemasukan Rp10.000. Tinjauan impor duplikat Rp25.000 tidak mengubah angka apa pun. Hapus dengan Urungkan memulihkan angka awal tanpa menciptakan dua operasi. Contoh split bill yang menguji angka lengkap ada pada §3.5.

### 3.5 Split bill: tagihan bersama dan pelunasan (R1)

**Tujuan:** mencatat satu tagihan yang dibagi beberapa orang tanpa menganggap tagihan penuh sebagai pengeluaran pribadi pengguna. R1 adalah pembukuan satu pemilik akun: peserta lain cukup berupa nama lokal. Mereka tidak perlu membuat akun, tidak melihat data Danarapi, dan pelunasan dicatat **manual oleh pengguna**. Aplikasi tidak mengirim permintaan uang atau memverifikasi transfer.

**Formulir:** `+` → Split bill, atau pilih “Jadikan split bill” dari review struk/QRIS yang sudah diperiksa. Isi total tagihan IDR, judul/merchant, tanggal, satu kategori pengeluaran, peserta (2–20 termasuk “Saya”), siapa yang membayar (“Saya” atau tepat satu peserta lain), dan akun pembayar **hanya bila Saya**. Nama peserta lain unik setelah normalisasi per tagihan; payer yang tidak ikut makan boleh ber-porsi Rp0. Pilih metode sama rata, nominal manual, atau persentase; boleh mengubah hasil sama rata sebelum simpan. Porsi masing-masing ≥ Rp0, setidaknya satu positif, jumlah porsi **tepat** sama dengan total; jumlah total per bill mengikuti batas nominal §3.1. Porsi Saya boleh Rp0. Satu bill mempunyai satu pembayar di R1; pembayaran gabungan dari beberapa orang pada saat awal dijadwalkan untuk R2.

| Metode | Perhitungan dan validasi |
| --- | --- |
| Sama rata | Bagi `total div jumlah peserta yang ikut` dalam Rupiah bulat; sisa `total mod jumlah` dibagikan Rp1 menurut urutan peserta yang terlihat, dimulai dari Saya bila ikut, agar deterministik. Peserta yang ditandai “Tidak ikut pembagian” mendapat Rp0 dan dikecualikan dari pembagi; tanpa pilihan ini semua peserta dibagi. |
| Nominal | Pengguna mengisi semua porsi; tombol Simpan aktif hanya jika jumlahnya tepat total. Tidak ada pembulatan tersembunyi. |
| Persentase | Persentase tiap peserta 0–100, maksimal dua desimal, total tepat 100%; hitung nilai pecahan dalam integer basis point, floor setiap porsi, lalu alokasikan sisa Rupiah berdasarkan pecahan terbesar dan urutan peserta tetap sebagai pemutus seri. Jumlah akhir wajib sama dengan total. |

**Saat tagihan diposting:** bila Saya membayar, akun Saya berkurang sebesar **total tagihan**; pengeluaran pribadi dan anggaran bertambah sebesar **porsi Saya**; porsi peserta lain menjadi piutang terhadap masing-masing orang. Bila peserta lain membayar, akun Saya **belum berubah**; pengeluaran pribadi dan anggaran bertambah sebesar porsi Saya; porsi Saya menjadi utang kepada peserta pembayar. Porsi peserta lain yang juga berutang kepada pembayar **bukan** piutang/utang Saya dan tidak memengaruhi posisi bersih Saya. Nominal tagihan dan porsi Saya diperlihatkan berdampingan agar tidak tertukar.

**Pelunasan:** pengguna dapat mencatat satu atau beberapa pembayaran sebagian, dengan tanggal, nominal, akun, peserta terkait, dan catatan opsional. Jika Saya pembayar, uang yang **diterima** dari peserta menaikkan saldo akun dan menurunkan piutang peserta itu. Jika peserta lain pembayar, uang yang **Saya bayarkan** menurunkan saldo akun dan utang Saya. Pelunasan tidak menambah pemasukan/pengeluaran pribadi, tidak mengubah anggaran, dan tidak boleh melebihi sisa kewajiban. Status bill diturunkan dari sisa kewajiban setelah pelunasan dan penghapusan kewajiban: `belum lunas`, `lunas sebagian`, `lunas`; bila semua sisa Rp0, status lunas. Label “Lunas” tidak otomatis menyatakan semua uang benar-benar diterima bila sebagian dihapuskan; detail harus menunjukkan jumlah dibayar dan dihapuskan terpisah. Tombol “Ingatkan” R1 hanya membuka teks ringkasan yang bisa disalin/dibagikan manual tanpa mengirim pesan otomatis, nama, email, nomor telepon, lampiran, atau tautan akun.

**Contoh wajib A — Saya membayar:** total Rp120.000 dibagi Saya, Ani, Budi masing-masing Rp40.000. Tunai awal Rp200.000. Setelah posting: Tunai Rp80.000, piutang Ani Rp40.000 + Budi Rp40.000, utang Rp0, posisi bersih Rp160.000, pengeluaran pribadi/anggaran Rp40.000. Ani melunasi Rp15.000 ke Tunai: Tunai Rp95.000, piutang Rp65.000, posisi bersih tetap Rp160.000, pengeluaran tetap Rp40.000. Saat keduanya lunas, Tunai Rp160.000 dan piutang Rp0.

**Contoh wajib B — teman membayar:** total Rp120.000 dengan porsi sama; Ani pembayar. Tunai awal Rp200.000. Setelah posting: Tunai tetap Rp200.000, utang Saya ke Ani Rp40.000, posisi bersih Rp160.000, pengeluaran pribadi/anggaran Rp40.000. Saat Saya melunasi Rp40.000 dari Tunai: Tunai Rp160.000, utang Rp0, posisi bersih tetap Rp160.000; pelunasan tidak masuk laporan pengeluaran lagi.

**Kewajiban yang tidak ditagih lagi:** R1 menyediakan “Hapuskan sisa” dengan alasan wajib dan konfirmasi. Jika Saya pembayar, piutang peserta berkurang, **pengeluaran pribadi nonkas** bertambah sebesar nilai yang dihapuskan pada tanggal keputusan, menggunakan kategori bill; anggaran periode itu ikut bertambah, saldo akun tetap. Jika teman membayar dan membebaskan porsi Saya, utang turun dan dicatat sebagai **pemasukan nonkas kategori Hadiah/Pembebasan utang** pada tanggal keputusan, saldo akun tetap. Tindakan ini tidak dapat melebihi sisa, dapat dibalik dengan reversal yang tercatat, dan tidak boleh dilabeli “pelunasan”. Ringkasan bill memisahkan dibayar, dihapuskan, dan sisa.

**Perubahan dan pembatalan:** bila belum ada pelunasan atau penghapusan kewajiban aktif, total, porsi, pembayar, kategori, tanggal, dan akun pembayar dapat diedit secara atomik dengan `expectedVersion`, menyesuaikan saldo/piutang/utang. Setelah ada pelunasan atau penghapusan kewajiban aktif, struktur tersebut dikunci; pengguna boleh mengedit metadata non-keuangan (judul/catatan) atau membatalkan pelunasan satu per satu dengan alasan, lalu mengubah bill. Hapus bill hanya saat tidak ada pelunasan dan penghapusan kewajiban aktif; lakukan soft delete atomik yang membalikkan kejadian kas, porsi pengeluaran, dan kewajiban, dengan Urungkan 10 detik. Penghapusan peserta dengan kejadian historis memerlukan pembatalan bill dan pembuatan bill pengganti; jejak kejadian lama tetap pada audit. Pembayaran yang salah dibatalkan/diedit melalui reversal yang terlacak, bukan menulis ulang saldo diam-diam. Peserta tidak digabung otomatis berdasarkan nama lintas bill.

**Tampilan dan pelaporan:** pengeluaran pribadi memuat porsi Saya saat bill dibuat serta piutang yang kemudian dihapuskan; pemasukan pribadi memuat pembebasan utang sebagai nonkas dengan label tersendiri. Pelunasan tidak masuk keduanya. Kartu Beranda menampilkan `Saldo akun`, `Piutang`, `Utang`, dan `Posisi bersih` secara terpisah. Daftar transaksi memiliki satu baris bill utama dan baris pelunasan terkait; detail menunjukkan total, porsi, payer, sisa setiap peserta, riwayat pelunasan, dan status. Laporan kategori/bulanan menghitung porsi Saya pada tanggal bill dan piutang yang dihapuskan pada tanggal keputusan; pembebasan utang tampil sebagai pemasukan nonkas terpisah. Laporan arus kas akun menghitung total yang Saya bayar serta pelunasan masuk/keluar pada tanggal kas. Filter akun pada laporan **arus kas** memilih akun kejadian kas; laporan **pengeluaran pribadi** tidak memakai filter akun untuk bill yang dibayar peserta lain, dan menjelaskan perbedaannya. CSV memisahkan pengeluaran pribadi, arus kas, bill, dan pelunasan (§5, §7). Bukti struk privat milik pengguna; ringkasan berbagi tidak menyertakan struk.

**Duplikat dan konversi:** receipt/QRIS hasil review bisa diarahkan ke split bill sebelum posted. Bila transaksi biasa sudah posted, konversi ke bill adalah satu mutasi atomik yang mengganti perhitungan transaksi lama dan membuat bill; jangan menyimpan keduanya. Kandidat duplikat dibandingkan dengan total bill dan bukti, bukan porsi Saya. QRIS tetap tidak membuktikan pembayaran. Split bill R1 pada akun nyata memerlukan internet; Mode Demo mendukung seluruh alur secara lokal. Dukungan outbox offline split bill di iOS ditunda ke R2 karena ketergantungan pelunasan/versi.

## 4. Arsitektur pengalaman dan layar

| Layar | Isi dan tindakan utama | Keadaan wajib |
| --- | --- | --- |
| Masuk/daftar | Email, kata sandi, kode verifikasi, lupa sandi, Coba Demo | Loading, salah kode, kedaluwarsa, 429, email tidak masuk. |
| Onboarding | Tunai dibuat, saldo awal opsional, transaksi pertama, izin biometrik setelah penjelasan | Lewati, kembali, gagal jaringan. |
| Beranda | Saldo akun, piutang, utang, posisi bersih, pemasukan/pengeluaran periode, anggaran, tagihan belum lunas, transaksi terbaru, tombol `+` | Baru, kosong, offline, data tertunda sinkron. |
| Transaksi | Kelompok tanggal, cari, filter akun/kategori/jenis/periode, detail, ubah, hapus/Urungkan | Hasil kosong, pemuatan berikutnya, konflik. |
| Input cepat | Jenis, nominal, akun, kategori, tanggal, merchant/catatan opsional, lampiran opsional | Validasi per field, simpan gagal, simpan offline. |
| Transfer | Dari, ke, nominal, tanggal, catatan | Akun sama ditolak, saldo negatif diperingatkan namun tidak diblokir. |
| Split bill | Total, peserta/porsi, metode pembagian, pembayar, akun bila Saya pembayar, kategori, ringkasan hitung | Sisa pembulatan, porsi tidak cocok, offline, konflik, bill telah dibayar sebagian. |
| Detail split bill | Total vs porsi Saya, piutang/utang, status per peserta, riwayat pelunasan, catat/batalkan pelunasan, salin ringkasan | Tanpa pelunasan, pelunasan sebagian, lunas, pembatalan, duplikat. |
| Pindai QRIS iOS | Kamera, pilih gambar, hasil merchant/nominal, tautan ke draft pengeluaran | Izin ditolak, QR bukan QRIS, CRC gagal, nominal tidak ada. |
| Impor | Unggah/pilih foto/PDF, tempel teks, pratinjau | File besar, jenis salah, parser gagal, offline. |
| Perlu Ditinjau | Kartu berisi nilai hasil ekstraksi, sumber, tanda ketidakpastian, kemungkinan duplikat; Simpan/Edit/Tolak/Gabung | Nol item, banyak item, sinkron tertunda. |
| Anggaran | Daftar kategori, sisa, indikator teks dan bar, ubah limit | Tidak ada anggaran, limit terlampaui. |
| Laporan | Ringkasan bulan/tahun, pengeluaran pribadi per kategori, arus kas per akun, piutang/utang dan tren, CSV | Tanpa data, ekspor gagal, perbedaan porsi vs kas dijelaskan. |
| Akun & kategori | Tambah, ubah nama, urut, arsip, aturan merchant | Nama ganda, akun/kategori dipakai. |
| Pengaturan | Profil, tema, zona waktu, pengunci iOS, privasi layar, ekspor penuh, hapus akun, kebijakan privasi | Verifikasi ulang untuk tindakan sensitif. |

Navigasi iOS memakai `TabView` SwiftUI: **Beranda, Transaksi, Perlu Ditinjau, Laporan, Pengaturan**, dengan aksi `+` yang mudah dijangkau; Split bill dari `+` dan kartu “Tagihan bersama”. Web memakai navigasi bawah pada layar kecil dan sidebar desktop. Detail anggaran dari Beranda/Laporan, akun/kategori dari Pengaturan. Back gesture native iOS dan browser back web menjaga input belum tersimpan dengan dialog jika ada perubahan. Setiap daftar memiliki loading, empty state dengan tindakan, error dengan Coba lagi, dan status offline. Hindari mengandalkan swipe saja: tombol Simpan/Tolak/Urungkan selalu tersedia dan terbaca screen reader.

## 5. Kebutuhan fungsional R1 dan kriteria penerimaan

**Prioritas:** P0 = rilis diblokir bila gagal; P1 = wajib sebelum portofolio dipublikasikan. Semua ID berikut harus masuk backlog dan pengujian.

| ID | Prioritas | Kebutuhan dan kriteria penerimaan |
| --- | --- | --- |
| AUTH-01 | P0 | Daftar email+katasandi; kirim kode verifikasi 6 digit via template kode; akun tidak diberi akses data sebelum verifikasi. Kode salah/kedaluwarsa dapat diminta ulang dengan batas laju. Email generik untuk permintaan pemulihan mencegah enumerasi. |
| AUTH-02 | P0 | Masuk, keluar, reset kata sandi via kode/email, penyegaran sesi. Bila outbox iOS berisi perubahan, logout menawarkan “Sinkronkan dulu” saat online atau “Buang perubahan di perangkat” dengan konfirmasi; tidak boleh diam-diam hilang atau tersinkron ke akun lain. Setelah logout selesai, cache sensitif, outbox, dan token perangkat dihapus. Sesi kedaluwarsa mempertahankan outbox sementara untuk login ulang **akun yang sama**, tanpa mengirim hingga identitas cocok. |
| AUTH-03 | P0 | iOS: sesi Supabase Swift disimpan melalui adapter Keychain yang diuji, pengunci aplikasi `LocalAuthentication` biometrik/kode perangkat bila tersedia, fallback kata sandi akun; kunci tampilan dan otorisasi server terpisah. Web: sesi browser mengikuti kebijakan §7.4 dan tidak diklaim setara Keychain. |
| ONB-01 | P1 | Demo dapat dibuka satu langkah; onboarding akun nyata membuat Tunai saja, saldo awal opsional, bisa melewati tur. Pengguna tidak harus memberi izin kamera/Foto sampai fitur dipakai. |
| ACC-01 | P0 | Buat/ubah/arsip akun, saldo awal dan tanggal pembukaan, nama unik per pengguna (case insensitive); tidak boleh mengarsip akun terakhir bila transaksi baru masih dapat dibuat tanpa memilih akun aktif. |
| CAT-01 | P0 | Kategori bawaan dapat diganti, ditambah, diurut, diarsip; jenis kategori tetap sesuai transaksi. Aturan merchant hanya memberi saran kategori, pengguna dapat mengubah sebelum simpan. |
| TRX-01 | P0 | CRUD pemasukan/pengeluaran; nominal valid, akun dan kategori milik pengguna, waktu valid. Setelah sukses, detail, saldo dan laporan konsisten. Penghapusan lunak dengan Urungkan selama 10 detik; setelah itu dapat dipulihkan hanya lewat cadangan/dukungan jika tersedia, bukan janji UI. |
| TRX-02 | P0 | Transfer dua akun dibuat/diubah/dihapus sebagai satu operasi. Tidak terlihat sebagai pemasukan atau pengeluaran dan tidak memicu anggaran. |
| TRX-03 | P0 | Cari catatan/merchant dan filter akun, kategori, jenis termasuk split bill, tanggal; halaman memakai keyset stabil `(occurred_at,id)`, 30 item per halaman. Penggabungan filter konsisten dengan CSV tampilan yang sama. |
| SPLIT-01 | P0 | Buat split bill 2–20 peserta termasuk Saya, total integer positif, satu pembayar Saya/teman, satu kategori, porsi sama rata/nominal/persentase. Simpan ditolak bila jumlah porsi ≠ total, nama peserta duplikat dalam bill, atau versi konflik. |
| SPLIT-02 | P0 | Bila Saya membayar, debit akun = total, pengeluaran pribadi = porsi Saya, piutang = porsi orang lain. Bila teman membayar, tidak ada debit akun awal, pengeluaran pribadi = utang Saya. Saldo akun, posisi bersih, laporan dan anggaran mengikuti contoh §3.5. |
| SPLIT-03 | P0 | Catat beberapa pelunasan sebagian per peserta dan akun; terima hanya hingga sisa kewajiban, tolak jumlah ≤0 atau overpay. Pelunasan mengubah akun dan piutang/utang, bukan laporan pemasukan/pengeluaran atau anggaran. |
| SPLIT-04 | P0 | Detail menampilkan total, porsi Saya, pembayar, sisa per orang, status dan riwayat. Salin/bagikan ringkasan teks dilakukan oleh pengguna; peserta tidak diwajibkan memiliki akun Danarapi atau menyerahkan nomor kontak. |
| SPLIT-05 | P0 | Edit struktur hanya sebelum pelunasan atau penghapusan kewajiban aktif; reversal tercatat dengan alasan. Hapus bill hanya bila tidak ada kejadian turunan aktif, secara atomik dengan Urungkan 10 detik; retry tidak mengubah saldo dua kali. |
| SPLIT-06 | P1 | Review bukti/QRIS dapat diarahkan ke split bill. Konversi transaksi posted ke split bill mengganti dampak ledger secara atomik; fingerprint duplikat memakai total tagihan, bukan porsi Saya. Split bill akun nyata memerlukan jaringan pada R1. |
| SPLIT-07 | P0 | Hapuskan sebagian/seluruh piutang atau utang dengan alasan dan konfirmasi; saldo akun tidak berubah. Piutang yang dihapus menambah expense nonkas pada tanggal keputusan; utang yang dibebaskan menambah income nonkas. Reversal terlacak dan tidak boleh menyebabkan nilai sisa negatif. |
| ATT-01 | P1 | Maks 5 MB/file, gambar JPEG/PNG/HEIC yang dikonversi bila diperlukan, PDF; simpan privat, hanya pemilik dapat akses. Validasi MIME nyata dan batas ukuran di sisi server; pratinjau gagal tidak menghapus transaksi. |
| QR-01 | P0 iOS | Kamera atau gambar memindai QRIS merchant-presented, memeriksa struktur dan CRC, menampilkan merchant/kota jika ada, mengambil nominal hanya bila tersedia. Kode statis meminta nominal. QR yang valid tidak otomatis berarti pembayaran. |
| QR-02 | P0 iOS | Hasil pindai menjadi **draft** terpisah; aksi “Catat sebagai sudah dibayar” memerlukan konfirmasi pengguna dan memilih akun. Beri teks “Danarapi tidak memproses atau memverifikasi pembayaran.” Bukti opsional; bila hanya ingin menyimpan calon pembelian, tetap draft dan tidak masuk saldo. |
| IMP-01 | P0 | Web dan iOS dapat membaca gambar yang mengandung QR, PDF yang mempunyai lapisan teks, serta teks ditempel; iOS juga dapat mengambil foto. OCR gambar/scan teks non-QR tidak dijanjikan di R1. Ekstraksi menandai asal dan nilai yang tidak yakin. |
| IMP-02 | P0 | Semua hasil ekstraksi disimpan sebagai `review_item`, bukan transaksi atau bill posted; pengguna memilih transaksi biasa atau split bill, melengkapi field wajib, lalu menekan Simpan. Kesalahan ekstraksi/format tidak menciptakan transaksi. Tolak dapat diurungkan 10 detik. |
| IMP-03 | P0 | Deteksi duplikat dua tahap: exact fingerprint untuk sumber yang sama dan kandidat berdasarkan tanggal ± 2 hari, nominal, merchant ternormalisasi, serta akun. Tampilkan alasan dan transaksi kandidat; jangan gabung otomatis. Pengguna bisa “Bukan duplikat”; gabung menambah lampiran/sumber tanpa mengubah nominal kecuali dikonfirmasi. |
| BUD-01 | P1 | Limit bulanan per kategori, angka terpakai/sisa/persen, status 80%/100% dengan teks dan warna; menghitung expense posted biasa, porsi Saya pada tanggal split bill, dan piutang yang dihapuskan pada tanggal keputusan; pelunasan tidak dihitung. |
| RPT-01 | P0 | Tampilkan saldo akun, piutang, utang, posisi bersih; pemasukan/pengeluaran pribadi bulanan dan tahunan (termasuk pos nonkas yang diberi label) serta arus kas terpisah. Gunakan rumus §3; laporan kategori menghitung porsi Saya, laporan akun menghitung arus kas; layar dan CSV yang sejenis harus sama. |
| EXP-01 | P0 | Sediakan CSV `personal_expenses.csv` (termasuk porsi Saya), `cash_flow.csv` (termasuk uang muka/pelunasan), `split_bills.csv` (satu baris/bill: total, pembayar, porsi Saya, status, sisa agregat), dan `split_members.csv` (satu baris/peserta, porsi/sisa), `split_settlements.csv` (arah, akun, jumlah, tanggal), dan `split_resolutions.csv` (hapus kewajiban/reversal dan alasan) sesuai hak akses. Pelunasan dan penghapusan kewajiban nonkas diberi `event_id`/`source_bill_id` agar setiap baris dapat ditelusuri tanpa dihitung dua kali. UTF-8 BOM, header tetap, nominal integer desimal, timestamp ISO-8601; escape formula (`=`, `+`, `-`, `@`, tab, CR) pada teks. Label jenis baris jelas agar tidak dijumlah silang. |
| EXP-02 | P0 | Ekspor data penuh milik pengguna sebagai ZIP berisi JSON versi skema, CSV, lampiran bila ada, manifest jumlah/ukuran/checksum. Beri tanda “berisi informasi sensitif” sebelum berbagi; kegagalan sebagian tidak ditandai berhasil. |
| SET-01 | P0 | Penghapusan akun tersedia dari iOS dan web dengan autentikasi ulang, ringkasan konsekuensi, status permintaan dan penyelesaian terverifikasi. Hapus data aplikasi, berkas dan sesi; detail retensi cadangan dijelaskan dalam kebijakan privasi sesuai konfigurasi sebenarnya. |
| DEMO-01 | P0 | Demo tanpa akun dan tanpa koneksi Supabase; data contoh sintetis deterministik 3 bulan/±200 transaksi, anggaran, split bill belum/sebagian lunas, contoh QRIS, PDF teks dan bukti teks. Semua perubahan hanya berlaku selama sesi dan diberi banner “Mode Demo — data contoh”. Reset Demo mengembalikan seed; ekspor/hapus akun tidak mengaku mengelola data server. |
| PRIV-01 | P1 | iOS menutupi pratinjau app switcher, opsi sembunyikan nominal; iOS tidak mengklaim dapat mencegah screenshot. Izin diminta saat dipakai dan penolakan punya jalur pilih file/manual. |
| THEME-01 | P1 | Tema terang/gelap/sistem, bahasa Indonesia, format Rupiah dan tanggal lokal. Pilihan dipertahankan antar sesi tanpa memuat data sensitif dalam preferensi publik. |

### 5.1 Aturan QRIS dan bukti

R1 hanya mendukung QRIS **Merchant Presented Mode** yang dikenali. Kode lain diberi pesan “QR tidak didukung” dan opsi input manual. Merchant hasil QR adalah petunjuk, bukan identitas yang diverifikasi oleh Danarapi. Jangan menampilkan tombol “Bayar”; tombolnya “Catat pembayaran” setelah pengguna melakukan pembayaran di aplikasi resmi miliknya. QR dinamis mungkin memuat nominal; QR statis biasanya mengharuskan pengguna memasukkan nominal. QR gambar dapat diimpor di web, tetapi kamera langsung hanya pada iOS R1. Buka gambar/PDF dari sumber tak tepercaya dalam parser lokal yang dibatasi; hapus metadata lokasi bila tidak diperlukan.

### 5.2 Alur rinci

1. **Manual:** `+` → Pengeluaran/Pemasukan → nominal → pilih akun/kategori bila default tidak cocok → Simpan → saldo dan daftar diperbarui. Default akun terakhir dipakai hanya bila masih aktif; kategori terakhir dipakai hanya bila jenis cocok. Tanggal default sekarang. Jika offline iOS, tampil “Tersimpan di perangkat, menunggu sinkronisasi” sampai server mengakui.
2. **QRIS:** `+` → Pindai/Pilih gambar → validasi → pratinjau merchant dan nominal → Simpan draft atau Catat sebagai sudah dibayar → konfirmasi → posted. Tidak ada konfirmasi otomatis dari jaringan pembayaran.
3. **Struk/PDF/teks:** pilih berkas/tempel → validasi ukuran/jenis → ekstraksi → Perlu Ditinjau → periksa kandidat duplikat → ubah field → Simpan. Bila gagal ekstraksi, buka input manual dengan lampiran yang tetap terhubung.
4. **Transfer:** `+` → Transfer → pilih dua akun → nominal → Simpan; daftar menunjukkan satu transfer dan detail menunjukkan kedua sisi.
5. **Split bill:** `+` → Split bill → total/peserta/pembayar/metode → lihat porsi yang jumlahnya tepat total → Simpan → lihat sisa piutang/utang → catat pelunasan sebagian atau penuh. Ketika offline pada akun nyata, tombol simpan memberi pesan perlu internet; Demo tetap berfungsi.
6. **Hapus:** konfirmasi singkat untuk akun/aksi berisiko; transaksi biasa menampilkan Urungkan 10 detik. Hapus offline juga membuat tombstone di outbox dan tidak hilang pada restart.

## 6. Sistem desain dan aksesibilitas — “rapi terasa ringan”

### 6.1 Arah visual dan prinsip

Danarapi tampil **minimalis, cerah, hangat, dan modern**. Hindari kesan dashboard korporat yang kaku, tetapi jangan membuat informasi uang seperti permainan. Dasar layar netral hangat, permukaan putih, kartu berwarna pastel yang segar, judul sedikit membulat, ruang kosong cukup, dan angka paling mudah dipindai. Aksen terang digunakan untuk menuntun perhatian; tombol penting dan teks memakai warna yang kontras. Ilustrasi sederhana dari bentuk geometri/lembut boleh dipakai pada onboarding dan empty state, bukan foto stok atau dekorasi yang mengganggu angka. Hindari gradien pada setiap kartu, bayangan tebal, neon, glassmorphism, dan animasi panjang.

Prinsip: satu aksi utama per layar; hierarki jelas pada 3 detik pertama; fokus pada saldo, porsi pribadi, dan tindakan berikutnya; bahasa Indonesia natural; ramah dijangkau satu tangan; data sensitif dapat disembunyikan. Komposisi indikatif **70% netral, 20% pastel, 10% warna tegas** per layar. Angka adalah informasi, bukan ornamen. Angka penting tidak bergantung hanya pada warna untuk menunjukkan naik/turun atau status utang/piutang.

### 6.2 Palet terang dan fungsi warna

Pembaruan warna setelah baseline v3.3: `product-update-planning.md` menetapkan putih/navy/biru dan menyatakan perubahan warna menggantikan ketentuan lama yang terkait. Kedua klien memakai token bersama v1.1; nilai awal di bawah dan §6.3 dipertahankan sebagai sejarah baseline. Ketentuan kontras, tema, fokus, tipografi, hierarki, aksesibilitas dan QA §6 tetap berlaku.

| Token | Nilai awal | Penggunaan |
| --- | --- | --- |
| `canvas` | `#F7FAF8` | Latar aplikasi, sedikit hangat; tidak putih total. |
| `surface` | `#FFFFFF` | Kartu, sheet, formulir, bar navigasi. |
| `ink` | `#17303A` | Judul, nominal, teks utama. |
| `muted` | `#53646B` | Label sekunder, waktu, penjelasan. |
| `border` | `#E3ECE8` | Pembatas tipis dan garis input; jangan mengandalkan border saja untuk fokus. |
| `primary` | `#0D7568` | Tombol utama, tautan penting, status aktif; teks putih. |
| `primary-soft` | `#C6F5DF` | Kartu saldo, latar ikon, sorotan positif. |
| `sky-soft` | `#D9F0FF` | Informasi akun dan ringkasan netral. |
| `peach-soft` | `#FFE2D2` | Split bill/porsi teman, aksen hangat. |
| `sun-soft` | `#FFF1BD` | Sorotan anggaran/perlu ditinjau. |
| `lavender-soft` | `#EAE4FF` | Variasi kategori/empty state secara hemat. |
| `income-ink` | `#0B7652` | Nominal masuk dan piutang, selalu dengan tanda/label. |
| `expense-ink` | `#A53F4D` | Pengeluaran dan utang, selalu dengan tanda/label. |
| `focus-ring` | `#2F8BE6` | Outline keyboard/fokus di luar komponen, tidak tertutup border. |

Pasangan yang sudah dihitung untuk titik awal: putih di `primary` **5,58:1**, `ink` di `canvas` **13,15:1**, `muted` di putih **6,17:1**, `expense-ink` di `peach-soft` **4,99:1**, dan `income-ink` di `primary-soft` **4,70:1**. Periksa lagi hasil render nyata, transparansi, disabled state, grafik, dan semua kombinasi sebelum dikunci. Jangan menaruh teks putih kecil pada pastel. Warna grafik memakai teks/ikon/legenda sehingga tetap terbaca pada buta warna.

Status memakai ikon dan teks: sukses `Tersimpan`, peringatan `Perlu Ditinjau`, gagal `Belum tersimpan`, dan antrean `Belum tersinkron`. Error form memakai `expense-ink` dengan pesan di bawah field; sukses tidak mengandalkan warna hijau. Tombol disabled tetap menampilkan label dan alasan ketika tidak dapat digunakan. `focus-ring` dihitung **3,53:1** pada putih; gunakan outline yang terlihat, bukan sekadar perubahan warna border. Warna hover tombol utama boleh lebih gelap `#075E54`, tetapi target sentuh tetap sama.

### 6.3 Mode gelap

Mode gelap tidak membalik warna terang secara otomatis. Token awal: `canvas #101C24`, `surface #182A34`, `ink #F2FAF7`, `muted #B3C8CC`, `primary #72E3C2`, `on-primary #0C2823`, `focus-ring #94C7FF`, `mint-surface #1F4C43`, `sky-surface #203A4F`, `peach-surface #493832`, `sun-surface #514626`, `income-ink #8EE6B6`, `expense-ink #FFABB2`. Pakai teks gelap pada tombol primary cerah. Simpan preferensi **Sistem/Terang/Gelap**, dengan transisi lembut tanpa flash warna saat aplikasi dibuka. Mode sembunyikan nominal tetap bekerja pada kedua tema.

### 6.4 Tipografi dan angka

- **Web:** gunakan **Plus Jakarta Sans variable** untuk seluruh UI agar bersih tetapi tidak kaku; host berkas WOFF2 sendiri dengan subset Latin yang diperlukan, `font-display: swap`, fallback `system-ui, sans-serif`. Simpan teks lisensi font di repositori. Tidak memuat font dari CDN runtime. Berat 400/500/600/700; hindari semua teks bold.
- **iOS:** gunakan **font sistem Apple** untuk body/form dengan Dynamic Type; gunakan varian `.rounded` terutama untuk judul besar, angka hero, dan pesan empty state, sementara daftar transaksi tetap font sistem yang jelas. Tidak menyematkan SF Pro ke web. Angka uang memakai digit tabular/`monospacedDigit()` agar tidak bergeser saat berubah.
- **Skala dasar:** hero saldo 32–36, judul layar 26–30, judul seksi 20–22, card title 16–18, isi 15–16, label 13–14 pt/px sesuai platform; teks penting tidak di bawah 13. Line height body sekitar 1,45–1,55 dan judul 1,15–1,25. Ikuti pembesaran teks sistem hingga setidaknya 200% tanpa memotong nominal/tombol.
- Format uang `Rp1.250.000`, spasi/rentang mengikuti locale ID; nominal utama tebal sedang 600–700, keterangan ringan. Gunakan `−`/`+`, teks “Pengeluaran/Pemasukan”, dan label “Belum tersinkron”, bukan warna semata.

### 6.5 Bentuk, spasi, ikon, dan gerak

Spasi berdasarkan kelipatan 4: 4/8/12/16/20/24/32/40. Margin horizontal layar ponsel 20–24, jarak antarseksi 24–32, isi kartu 16–20. Radius tombol/input 14–16, kartu 20, sheet 24, pill penuh. Shadow halus hanya pada kartu prioritas/floating action (`0 8px 24px` warna tinta opacity sekitar 6% di web); daftar biasa memakai border lembut. Satu layar mempunyai maksimal satu tombol aksi primer yang dominan; aksi destruktif tidak memakai warna primary.

Ikon bergaris konsisten, stroke sedang; iOS memakai SF Symbols yang sesuai, web memakai satu set SVG ringan yang lisensinya dicatat. Padankan **makna** ikon, tidak wajib bentuk identik. Kategori memakai lingkaran warna pastel dan simbol sederhana. Peserta split bill dapat memakai avatar inisial tanpa foto wajib. Animasi 160–240 ms untuk sheet, perubahan status, dan tombol; umpan balik haptic ringan saat berhasil menyimpan di iOS. Tidak ada animasi saldo yang mengaburkan angka. `prefers-reduced-motion`/Reduce Motion mematikan gerak dekoratif.

### 6.6 Tata letak layar inti

| Layar | Komposisi yang diharapkan |
| --- | --- |
| Onboarding | 2–3 layar singkat dengan bentuk abstrak cerah, satu kalimat manfaat, tombol jelas “Coba Demo” dan “Buat akun”; ilustrasi tidak menghalangi teks. |
| Beranda | Sapaan kecil dan pengaturan privasi; kartu saldo utama mint lembut berisi `Saldo akun` besar, tautan lihat detail, `Posisi bersih` berlabel; dua kartu ringkas pemasukan/pengeluaran; progres anggaran; daftar terbaru. Piutang dan utang terlihat tanpa mencampur total kas. |
| Tambah transaksi | Sheet atau layar dengan nominal besar langsung fokus, pilihan jenis jelas, akun/kategori mudah dijangkau, tanggal/catatan sekunder, tombol Simpan tetap terlihat di atas keyboard/safe area. |
| Transaksi | Baris rapi: ikon pastel, merchant/kategori, tanggal, akun, nominal dan tanda; status offline sebagai chip teks. Kelompok tanggal dan filter dapat dipindai tanpa garis tabel padat. |
| Split bill | Total tagihan dan “Bagian saya” berdampingan; kartu peserta dengan inisial, porsi dan sisa; metode pembagian sebagai segmented control; ringkasan jumlah harus selalu tepat sebelum Simpan. Detail menampilkan progres per peserta dan tombol “Catat pelunasan”. |
| Perlu Ditinjau | Bukti/pratinjau ringkas, field hasil ekstraksi yang ragu diberi tanda kuning + teks, kandidat duplikat terlihat, tombol Simpan/Tolak/Edit selalu ada tanpa mengandalkan swipe. |
| Anggaran/Laporan | Grafik batang/donat sederhana dengan angka, label, legenda, dan deskripsi teks; pastel membedakan kategori, warna expense/income untuk makna finansial. Daftar rincian dapat diakses tanpa grafik. |
| Pengaturan | Kelompok opsi dengan judul jelas; tindakan hapus akun jauh dari opsi tema, dengan dialog konfirmasi yang tenang dan rinci. |

Web memakai navigasi bawah di ponsel, sidebar pada desktop, konten utama maksimum sekitar 1200 px; form nyaman dibaca pada lebar sekitar 680–760 px. iOS memakai pola native `TabView`/`NavigationStack`, safe area dan sheet SwiftUI. Tata letak kedua platform selaras secara urutan informasi dan bahasa, namun tetap mengikuti interaksi masing-masing.

### 6.7 Konten, empty state, dan karakter merek

Bahasa singkat, hangat, tidak menggurui. Contoh: “Uangmu lebih mudah dipahami”, “Sudah rapi hari ini”, “Belum ada transaksi. Catat yang pertama, yuk.” Jangan memakai humor pada kesalahan saldo, privasi, atau hapus akun. Ikon/bentuk dekoratif boleh hadir pada keadaan kosong dan demo; layar dengan data padat lebih tenang. Semua tombol memiliki kata kerja (“Catat pengeluaran”, “Simpan tagihan”, “Catat pelunasan”) dan status sukses/gagal yang spesifik.

**Microcopy wajib:** “Perlu Ditinjau (3)”, “Jumlah belum terbaca. Isi nominal sebelum menyimpan.”, “Kode QR membantu mengisi catatan; pembayaran dilakukan di aplikasi pembayaran Anda.”, “Tersimpan di perangkat, belum tersinkron”, “Ditemukan transaksi mirip. Periksa sebelum menyimpan.”, “Saya membayar Rp120.000; bagian saya Rp40.000; Rp80.000 belum dibayar teman.”, “Pelunasan ini hanya mengurangi piutang, bukan pemasukan.”, “Data Anda akan dihapus permanen setelah proses selesai.”

### 6.8 Aksesibilitas dan gerbang QA visual

Target sentuh minimal 44×44 pt di iOS dan ukuran setara yang nyaman di web; fokus logis dan terlihat, label/VoiceOver untuk nominal serta status, sheet mengelola fokus, ikon tidak berdiri sendiri tanpa nama. Teks biasa minimal **4,5:1** dan komponen/informasi grafis **3:1** sesuai target WCAG AA; uji pasangan yang benar-benar dipakai, termasuk pastel/tema gelap. Dukung Dynamic Type/zoom 200%, keyboard web, screen reader, VoiceOver, reduced motion, dan pembesaran nominal tanpa overflow.

**R1 dianggap lolos desain hanya jika:** (1) screenshot Beranda, Input, Split bill, Perlu Ditinjau, dan Laporan tersedia di iOS dan web ponsel untuk tema terang/gelap; (2) diuji pula web desktop, iPhone kecil, dan teks besar; (3) angka serta tombol tidak terpotong dan kontras lulus; (4) peninjauan visual memastikan konsistensi token, spasi, tipografi, ikon, dan pesan; (5) uji kegunaan minimal 20 percobaan input cepat serta 10 percobaan split bill tanpa bantuan. Hasil pemeriksaan dan perbaikan dicatat, bukan dinyatakan lolos berdasarkan kode saja.

**Sumber desain:** token bersama di `contracts/design-tokens.json` memuat peran warna, radius, spasi, tipografi, dan gerak. Web membuat CSS variables, iOS membuat `Color`/style SwiftUI dari pemetaan token. Tidak ada font web yang dimuat di target iOS. Versi desain awal diuji dengan layar nyata sebelum dianggap final.

## 7. Kontrak data dan implementasi

### 7.1 Arsitektur satu repo, dua aplikasi

```text
danarapi/
├── apps/web/                 # Vue 3, TypeScript, Vite; UI dan adapter web
├── apps/ios/                 # Xcode project; Swift, SwiftUI, adapter iOS
├── supabase/migrations/      # Skema, constraint, RLS, fungsi ledger
├── supabase/functions/       # Operasi server yang perlu hak istimewa
├── contracts/                # OpenAPI/JSON Schema, kode error, fixture versi
├── tests/fixtures/           # Kasus angka, QR, impor dan keluaran yang sama
└── docs/                    # PRD, ADR, threat model, panduan operasional
```

**Batas kepemilikan:** server PostgreSQL/RPC adalah sumber kebenaran untuk uang, status bill, kuota dan izin; semua mutasi finansial atomik dan idempoten. Swift dan TypeScript mempunyai UI, state, cache dan validasi input masing-masing. Keduanya membaca kontrak versi yang sama dan memakai fixture berisi input/output numerik yang sama; **kode Swift tidak mengimpor paket TypeScript dan web tidak memakai UI SwiftUI**. Validasi lokal untuk respons cepat tidak menggantikan constraint server. Laporan online berasal dari query/view server yang sama, sementara nilai optimistis offline iOS selalu berlabel belum sinkron.

**Kontrak bersama:** definisikan DTO JSON, enum, batas nominal, skema tanggal UTC/IDR, cursor, error, dan versi API di `contracts/` dengan OpenAPI/JSON Schema. Hasilkan tipe TypeScript dan model `Codable` Swift bila generator terbukti stabil; bila tidak, petakan manual dan wajib lulus tes kontrak. Bigint Rupiah melintasi JSON sebagai string desimal, waktu RFC 3339 UTC, identitas UUID. Error standar `code`, `message`, `request_id`, `details` yang aman; kode seperti `VALIDATION`, `UNAUTHORIZED`, `CONFLICT_VERSION`, `DUPLICATE_MUTATION`, `QUOTA_EXCEEDED`, `REQUIRES_ONLINE` stabil dan UI menerjemahkan pesan. Data pribadi tidak diletakkan dalam error/log.

**Akses backend:** kedua aplikasi memakai identitas Supabase Auth yang sama tetapi sesi perangkat/browser terpisah. Aplikasi menggunakan kunci publik yang dibatasi RLS; service-role hanya dalam fungsi server. RPC ledger menerima JWT, memeriksa `auth.uid()` dan menolak pemilik dari payload klien. Web dan iOS dapat mengakses rekening pengguna yang sama; tidak ada sinkron langsung antarklien atau CloudKit R1. Saat online masing-masing memuat ulang dari server setelah mutasi dan saat kembali aktif. Kontrak basis data internal tidak menjadi API publik yang bebas ditulis klien.

**Versi dan rilis:** migrasi server dijalankan lebih dahulu di staging lalu production, baru web/iOS diperbarui. Perubahan kontrak harus additive selama masa transisi; jangan menghapus field/enum yang masih dipakai versi iOS terpasang. R1 mendukung sekurang-kurangnya versi iOS aktif sebelumnya selama satu siklus rilis; server mencatat `minimum_client_version` hanya setelah jalur pembaruan tersedia. Tetapkan `schema_version` pada fixture, ekspor JSON, dan cache lokal. Uji upgrade cache iOS dan rollback migrasi staging dengan data sintetis sebelum rilis. Fitur berisiko memakai flag di server per platform, default mati sampai tes perangkat lulus.

**Mode Demo:** dua implementasi lokal (`WebDemoRepository` dan `IOSDemoRepository`) memuat seed JSON yang sama, mengimplementasikan aturan tampilan/transaksi/split bill yang sama tanpa jaringan, dan lulus golden fixtures. Data demo tidak dipindahkan ke akun nyata secara otomatis. Perbedaan kemampuan platform (mis. kamera iOS) boleh ditunjukkan dengan contoh file pada web. Demo kedua aplikasi berjalan di memori selama sesi; keluar atau restart mengembalikan seed, dan tombol Reset mengembalikannya segera. Demo tidak menampilkan data asli.

**Desain dan navigasi:** token warna, tipografi, terminologi, ikon konseptual, format IDR dan copy disimpan sebagai spesifikasi bersama dalam `contracts/design-tokens.json` atau dokumen setara. Web mengubahnya menjadi CSS, iOS menjadi `Color`/`Font` SwiftUI. Hasil visual boleh mengikuti pola platform; screenshot tidak perlu piksel identik. Tinjau aksesibilitas pada kedua implementasi secara terpisah.

### 7.1.1 Modul khusus platform

| Kemampuan | Web Vue 3 | iOS SwiftUI native |
| --- | --- | --- |
| UI/navigasi | Vue Router + komponen web responsif | `TabView`, `NavigationStack`, sheet/form SwiftUI |
| Autentikasi | Supabase JS; kebijakan penyimpanan per tab | Supabase Swift; sesi di Keychain, kunci UI via LocalAuthentication |
| QR kamera | Tidak ada di R1 | AVFoundation metadata QR, izin saat dipakai; hasil tetap diparse dan CRC divalidasi |
| QR dari gambar | Decoder QR lokal yang dipin dan diuji | PhotosUI/Files + Vision barcode detection untuk berkas; tanpa OCR teks R1 |
| Foto/berkas | `<input type=file>` dan pemrosesan lokal | PhotosPicker, kamera native, Files/Document Picker |
| PDF berlapis teks | Parser PDF web yang dimuat malas | PDFKit lokal; PDF scan tanpa teks masuk review manual |
| OCR R2 | Tesseract.js opt-in, lazy | Apple Vision opt-in; berbeda dari deteksi QR R1 |
| Penyimpanan offline | Demo memori; akun nyata butuh online R1 | SwiftData cache/outbox dengan Data Protection; tidak memakai CloudKit |
| Ekspor/berbagi | Unduh CSV/ZIP dan Web Share jika ada | Share Sheet native setelah ekspor dan konfirmasi data sensitif |

Implementasi native memakai API Apple yang relevan dan diuji pada versi minimum iOS. Tidak ada Capacitor, bridge JavaScript, UI utama WKWebView, atau dependensi runtime web di target iOS.

### 7.2 Entitas inti

Setiap tabel pengguna memiliki `user_id`, `id` UUID, `created_at`, `updated_at`, `version` integer, serta penghapusan lunak hanya bila diperlukan. Relasi antartabel milik pengguna harus menjaga pasangan `(user_id,id)` melalui FK komposit atau mekanisme setara agar foreign key silang pengguna mustahil. `auth.users` adalah pemilik identitas.

| Entitas | Field penting | Aturan |
| --- | --- | --- |
| `profiles` | user_id, timezone, locale, theme | Hanya satu per pengguna; email tetap milik Auth. |
| `accounts` | id, user_id, name, kind, opening_balance, opened_at, archived_at | Nama aktif unik per pengguna; archive bukan hapus histori. |
| `categories` | id, user_id, name, kind, archived_at, sort_order | Kind terkunci bila dipakai; kategori bawaan disalin. |
| `transactions` | id, user_id, type, status, amount, account_id, category_id, occurred_at, merchant, note, source, deleted_at, version | Untuk income/expense; CHECK nominal/status/jenis; hanya posted dihitung. |
| `transfers` | id, user_id, from_account_id, to_account_id, amount, occurred_at, note, deleted_at, version | Satu row atomik; akun berbeda. |
| `adjustments` | id, user_id, account_id, signed_amount, reason, occurred_at | Terlihat di riwayat; alasan wajib. |
| `attachments` | id, user_id, transaction_id/review_item_id/split_bill_id (satu terisi), storage_key, mime, size, sha256 | Tepat satu pemilik tautan; path privat; metadata dibatasi. |
| `split_bills` | id, user_id, total, title, payer_kind, payer_member_id, payer_account_id, category_id, occurred_at, deleted_at, version | Payer adalah Saya atau satu anggota lain; account wajib hanya bila Saya membayar; satu kategori R1; **status dihitung** dari kewajiban, bukan diedit bebas. |
| `split_members` | id, user_id, split_bill_id, display_name, is_self, share_amount, sort_order | Tepat satu Saya, 2–20 peserta, jumlah semua share = total; nama unik ter-normalisasi dalam bill. |
| `split_settlements` | id, user_id, split_bill_id, member_id, direction, account_id, amount, occurred_at, reversed_at, reversal_reason, version | Masuk dari anggota saat Saya pembayar, keluar kepada payer saat teman pembayar; total aktif per kewajiban ≤ porsi; reversal terlacak. |
| `split_resolutions` | id, user_id, split_bill_id, member_id, kind, amount, occurred_at, reason, reversed_at, version | Penghapusan piutang/utang nonkas; total pelunasan + resolusi aktif ≤ porsi; pembalikan tercatat. |
| `review_items` | id, user_id, source, status, extracted_fields JSON tervalidasi, raw_reference, duplicate_of, version | Status pending/saved/rejected; satu review tak boleh menghasilkan dua transaksi. |
| `merchant_rules` | id, user_id, match_type, normalized_pattern, category_id, priority | Pola aman, tanpa regex pengguna R1; prioritas eksplisit. |
| `budgets` | id, user_id, category_id, month YYYY-MM, limit_amount | Unik per kategori/bulan. |
| `mutation_receipts` | user_id, client_mutation_id, payload_hash, result_id, applied_at | Idempotensi; replay sama mengembalikan hasil sama, payload beda ditolak. |

Buat `ledger_entries` atau proyeksi transaksi kas yang berasal dari bill/pelunasan dengan `source_kind`, `source_id` unik dan dua sisi efek yang tervalidasi. Jangan membuat entri pengeluaran pribadi penuh Rp120.000 untuk contoh §3.5; sumber tunggal adalah bill dan pelunasannya. Nama `transactions` dan `transfers` dapat disatukan dalam satu ledger internal bila invarian di §3 serta query dan ekspor tetap identik. Skema final dikunci dalam migrasi SQL, dan ERD/kontrak API dibuat dari migrasi yang diuji, bukan dari contoh ini saja.

### 7.3 API dan izin

- Antarmuka repository **per klien** (`Repository` protocol Swift dan `RepositoryPort` TypeScript) menyediakan `listAccounts`, `listTransactions(cursor,filters)`, `createTransaction`, `updateTransaction(expectedVersion)`, `deleteTransaction`, `createTransfer`, `createSplitBill`, `updateSplitBill`, `deleteSplitBill`, `recordSplitSettlement`, `reverseSplitSettlement`, `recordSplitResolution`, `reverseSplitResolution`, `listSplitBills`, `listReviewItems`, `confirmReviewItem`, `rejectReviewItem`, `getReports`, `exportData`, `requestAccountDeletion`. Keduanya memakai kontrak data §7.1 dan error terstruktur; implementasi remote dan demo dipisah pada masing-masing platform.
- Mutasi finansial, pembuatan/perubahan/pembatalan bill, pencatatan/reversal pelunasan atau penghapusan kewajiban, serta konfirmasi review lewat fungsi server/RPC transaksional yang mengambil `auth.uid()`; **jangan** menerima `user_id` client sebagai sumber hak akses. Terapkan constraint dan RLS untuk `SELECT/INSERT/UPDATE/DELETE`, termasuk `WITH CHECK`; audit `SECURITY DEFINER`, `search_path`, grants, dan storage policy.
- Semua operasi tulis membawa UUID `client_mutation_id` dan `expectedVersion` untuk edit. Server melakukan idempotensi atomik dan mengembalikan versi terbaru. Batas pelunasan/resolusi per peserta dijaga di transaksi database dengan penguncian baris bill atau isolasi setara; dua permintaan bersamaan tidak boleh sama-sama lolos bila totalnya melebihi porsi. Setelah 409, UI menampilkan data server dan pilihan terarah: muat ulang atau simpan sebagai salinan bila relevan; jangan timpa diam-diam.
- Berkas berada pada bucket privat dengan path berbasis pemilik/UUID, akses melalui kebijakan owner dan URL sementara bila perlu. Batas kuota ditegakkan **di server**. Tidak ada service-role key dalam aplikasi/browser.
- Ekspor dan hapus akun dilakukan di fungsi server yang diautentikasi dan meminta reautentikasi untuk tindakan sensitif. Job asynchronous mengembalikan status; hapus dianggap selesai setelah Auth, tabel aplikasi, objek Storage, dan sesi ditangani atau kegagalan parsial tercatat untuk ulang.

### 7.4 Sesi

Supabase Swift iOS memakai penyimpanan sesi yang terhubung ke **Keychain** dengan akses `ThisDeviceOnly` sesuai kebutuhan dan diuji untuk refresh token, logout, restart, pergantian pengguna, serta penghapusan akun. Periksa konfigurasi penyimpanan SDK aktual; jangan menganggap default SDK otomatis memenuhi kebijakan. `LocalAuthentication` membuka tampilan aplikasi atau akses rahasia lokal, tetapi bukan MFA pada server. Fallback adalah kode perangkat bila diizinkan konfigurasi, lalu kata sandi akun; kegagalan biometrik tidak boleh mengunci akses data secara permanen. Web memakai Supabase JS dengan adapter penyimpanan sesi per tab bila layak (`sessionStorage`) dan kebijakan keluar saat tab ditutup; tinjau perilaku refresh/reload pada versi SDK yang dipakai. Token web tetap rentan terhadap XSS sehingga CSP, sanitasi, dependency review, dan logout menjadi wajib. Jangan menyatakan sesi tidak tersimpan bila SDK masih memakai default.

## 8. Impor, parser, dan duplikat

Urutan pada masing-masing klien: decode QR bila ada → ekstrak teks PDF bila PDF berlapis teks → parser template deterministik → validasi field → review. Parser Swift dan TypeScript harus lulus **fixture masukan/keluaran yang identik** untuk QRIS, CRC, uang, tanggal, dan bukti teks; server memvalidasi ulang field finansial sebelum posted. Gambar biasa tanpa QR dan PDF hasil scan masuk ke input manual berlampiran pada R1; OCR ditawarkan hanya setelah R2 diaktifkan secara sadar. Jangan mengunggah berkas ke layanan AI pihak ketiga. Sumber berkas dan teks mentah hanya disimpan selama dibutuhkan untuk review/lampiran dan tunduk pada kuota/retensi.

Parser harus mengembalikan `value`, `confidence` terbatas pada indikator UI tinggi/sedang/rendah, `evidence_span`, dan `source_type` untuk nominal, tanggal, merchant, nomor referensi bila ada. Tidak ada klaim “akurasi 100%”. Prioritas nominal adalah total pembayaran yang eksplisit; bila ada subtotal, ongkir, diskon, pajak, atau beberapa angka yang ambigu, jangan pilih otomatis. Tanggal tanpa tahun atau zona waktu perlu dikonfirmasi. Merchant boleh kosong. Nomor referensi dapat dipakai pada fingerprint setelah normalisasi dan hash, tetapi jangan tampilkan sebagai kredensial.

Fingerprint duplikat exact: `(user, source_provider, reference_hash)` bila referensi valid tersedia, atau `sha256(file)` untuk unggahan sama. Kandidat fuzzy: nominal sama, selisih tanggal ≤2 hari, merchant mirip dan/atau akun sama. Hindari false positive dengan tidak memblokir dua pembelian sah bernominal sama; beri pilihan “Tetap simpan”. Untuk gabung, file sumber ditautkan ke transaksi target secara atomik; review ditandai saved/merged, tidak menambah saldo. Status review `pending → saved|rejected` dan tidak boleh kembali ke pending tanpa aksi Urungkan yang tercatat.

## 9. Offline, sinkronisasi, privasi, dan keamanan

### 9.1 Offline R1 iOS

**R1 terbatas:** cache baca terlindungi Data Protection untuk akun, kategori, transaksi terakhir, anggaran, dan ringkasan split bill/piutang/utang dengan label waktu sinkron terakhir; outbox terlindungi untuk buat/ubah/hapus transaksi dan transfer. Aplikasi tidak menjanjikan background sync ketika perangkat terkunci. Operasi dilakukan dengan `client_mutation_id` UUID, `base_version`, payload dan timestamp. UI menandai `pending/syncing/synced/conflict/failed`. Demo split bill bekerja di memori tanpa jaringan. Simpan draft QR lokal boleh, tetapi split bill akun nyata, unggah lampiran dan konfirmasi review memerlukan jaringan pada R1; bila offline tampilkan batasan sebelum pengguna memilih file. Web R1 membutuhkan jaringan untuk akun nyata, sementara Mode Demo selalu lokal di memori.

Pada reconnect, outbox dikirim per pengguna dan per entitas menurut urutan ketergantungan, dengan retry backoff dan hasil idempoten. Jangan memutar antrean akun A pada sesi akun B. Jika sesi habis, kunci outbox untuk akun A dan lanjutkan hanya setelah A masuk kembali; jika pengguna memilih logout eksplisit, wajib sinkronkan dulu atau buang antrean dengan konfirmasi, kemudian bersihkan cache/token. Pergantian akun tidak mewarisi cache pengguna lain. Konflik edit versi menahan entitas tersebut dan menampilkan perbandingan sederhana. Server menang untuk field yang tidak dapat digabung otomatis; pilihan “Simpan sebagai baru” tersedia untuk catatan pengeluaran bila aman. Hapus menghasilkan tombstone sehingga item tidak muncul kembali dari cache lama. Delta penuh dan kolaborasi beberapa perangkat di R2; R1 menyegarkan halaman awal setelah online, lalu melakukan reconcile untuk memastikan cache mencerminkan server.

**Batas penting:** iOS R1 memakai SwiftData untuk cache dan outbox lokal, dengan Data Protection `completeFileProtection` pada store dan file pendukung serta pengecualian cadangan iCloud untuk data sensitif. Ini perlindungan berkas iOS saat perangkat terkunci, bukan klaim enkripsi end-to-end atau jaminan plugin. Penyimpanan berjalan hanya ketika protected data tersedia; sinkronisasi R1 dipicu saat aplikasi aktif/terbuka. Verifikasi level proteksi store, WAL/SHM, file sementara, migrasi, restart dan logout pada perangkat asli. Jika tidak dapat dibuktikan, nonaktifkan cache/outbox sensitif dan nyatakan gerbang offline R1 gagal sampai solusinya diperbaiki.

### 9.2 Keamanan

- RLS semua tabel dan Storage; pengujian dua identitas untuk baca/tulis/ubah/hapus serta FK lintas pemilik. Service role hanya di fungsi server yang terbatas. Batasi kueri dan payload; log tidak mencatat email lengkap, token, OTP, struk, nomor rekening, nama peserta split bill, atau isi transaksi.
- HTTPS/ATS tanpa pengecualian pada iOS dan HTTPS di web. CSP ketat, sanitasi input dan larangan HTML mentah berlaku pada web; iOS memvalidasi URL/file dan izin kamera/Foto pada saat dipakai. Batasi dependensi dan origin, pindai secret/dependensi di CI dan rotasi bila rahasia terlanjur masuk Git.
- Izin kamera/Foto hanya saat dipakai; gambar dibersihkan dari EXIF lokasi bila tidak diperlukan. File PDF/gambar tidak dieksekusi; MIME sniff, pembatasan ukuran/halaman/waktu proses dan perlindungan dari file berbahaya.
- iOS native menutup pratinjau sensitif saat masuk background, menyediakan opsi sembunyikan nominal, Keychain untuk sesi, SwiftData store/outbox dengan Data Protection dan pengecualian cadangan sensitif. Saat perangkat terkunci, hentikan akses berkas protected dan lanjutkan ketika tersedia. Tidak menjanjikan screenshot dapat diblokir.
- CAPTCHA serta batas laju pendaftaran/verifikasi/reset; penegakan server untuk kuota: ≤200 lampiran, ≤100 MB/pengguna, ≤5 MB/file, dan batas transaksi/hari awal 500, dapat disetel tanpa migrasi. Jika kuota tercapai, data yang ada tetap bisa dibaca/ekspor/hapus.

### 9.3 Retensi dan kendali pengguna

Kebijakan privasi `/privacy` dan halaman `/hapus-akun` tersedia sebelum demo publik. Jelaskan kategori data, tujuan, penyimpanan, pihak pemroses, retensi, cara ekspor/hapus, kontak, dan keterbatasan Mode Demo berdasarkan implementasi sebenarnya. Jangan memajang data keuangan nyata pada repo, telemetry, screenshot, dan seed. Review item yang ditolak dihapus permanen bersama berkasnya setelah 30 hari; item pending setelah 90 hari hanya bila pengguna telah menerima pemberitahuan kebijakan, jika tidak R1 menyimpannya sampai dihapus pengguna. Ekspor sementara di server dihapus paling lambat 24 jam setelah dibuat. Angka retensi cadangan mengikuti konfigurasi infrastruktur aktual dan harus dicatat sebelum publikasi; jangan mengklaim langsung hilang dari semua backup.

Hapus akun: tindakan hanya saat online; jika iOS memiliki outbox pending, minta sinkronisasi atau konfirmasi membuangnya lebih dulu. Tampilkan isi yang akan hilang, minta autentikasi ulang, ekspor opsional, kirim job, tampilkan status, batalkan semua sesi dan hapus cache lokal ketika tuntas, dan pastikan tidak ada objek Storage yatim. Bila job gagal, status tetap “Sedang diproses” dengan percobaan ulang dan jalur bantuan. Mode Demo: “Reset data contoh”, bukan “Hapus akun”.

## 10. Kebutuhan nonfungsional dan operasi

| ID | Kriteria |
| --- | --- |
| NFR-01 Kinerja | JS web rute awal ≤170 KB gzip; pemindai gambar/PDF, OCR, grafik lanjutan dan XLSX web dimuat malas. iOS native cold start <2,5 detik target di iPhone uji, scrolling riwayat tetap lancar; daftar dipaginasi dan gambar diperkecil hingga 1600 px bila QR tetap terbaca. Ukur ulang setelah dependensi diperbarui. |
| NFR-02 Keandalan | Tidak ada mutasi finansial ganda karena retry dari web/iOS. Simulasi koneksi putus, respons terlambat, restart aplikasi, upgrade skema, dan dua perangkat harus memberi hasil server deterministik. |
| NFR-03 Kompatibilitas | Target minimum iOS 17 untuk SwiftUI + SwiftData, divalidasi pada Xcode dan perangkat nyata; web diuji Safari/Chrome/Edge versi yang masih didukung. Kenaikan target minimum perlu ADR, daftar perangkat terdampak, dan tes migrasi. |
| NFR-04 Observabilitas | Error terstruktur dengan request ID anonim, ukuran antrean/gagal sync, latensi kueri agregat, jumlah job hapus/ekspor gagal; opt-in bila analytics perilaku memakai data pengguna. Tanpa payload sensitif. |
| NFR-05 Pemulihan | Migrasi database diuji di staging; backup/restore server diuji sebelum akun publik nyata; migrasi store iOS dari versi lama lulus tes tanpa kehilangan outbox. Audit akses, pemulihan secret, dan insiden terdokumentasi. Jangan mengklaim PITR bila plan tidak menyediakan. |
| NFR-06 Biaya | Catat penggunaan bulanan Auth email, DB, Storage, bandwidth, hosting dan error log; pasang batas/alert bila tersedia. Mode Demo tetap berfungsi saat backend jeda. |
| NFR-07 Aksesibilitas | Kriteria §6 diuji otomatis untuk web dan manual untuk VoiceOver SwiftUI, keyboard web, Dynamic Type, kontras, dan reduced motion pada keduanya. |
| NFR-08 Paritas kontrak | Swift dan TypeScript lulus golden fixtures yang sama untuk nominal, tanggal, QRIS, split bill, status, parser, dan error; CI gagal bila satu sisi berbeda. |
| NFR-09 Rilis dua klien | CI Linux untuk web/server dan macOS untuk iOS; migrasi server lebih dahulu, tes kontrak kedua klien, smoke test staging, lalu build iOS/web. Versi klien lama tidak rusak oleh migrasi additive. |
| NFR-10 Kualitas visual | Kedua klien menerapkan token, tipografi, komponen, tata letak, tema, dan copy §6. Screenshot lima layar inti pada dua tema, pemeriksaan ponsel/desktop/teks besar, serta catatan perbaikan wajib tersedia sebelum status selesai. |

## 11. Spesifikasi fitur R2, gerbang, dan backlog

| ID | Cakupan kelak | Aturan minimum sebelum diterima |
| --- | --- | --- |
| OCR-02 | Apple Vision iOS; Tesseract.js web secara lazy; default mati | Persetujuan eksplisit, pemrosesan lokal, 30 sampel ID nyata yang telah disamarkan, hasil tetap review, kegagalan kembali ke input manual. |
| CSV-02 | Impor mutasi bank/e-wallet | Preview pemetaan kolom, encoding, format tanggal/nominal, jumlah debit/kredit; dedupe, tidak otomatis posted, batas file dan rollback batch. |
| GOAL-02 | Target tabungan | Target nominal/tanggal, kontribusi dari transaksi yang ditandai pengguna, proyeksi deterministik dengan rumus dan asumsi terlihat; bukan nasihat finansial. |
| REC-02 | Transaksi berulang | Jadwal zona waktu, akhir bulan, pengingat lokal; setiap kejadian menjadi draft sampai disetujui agar tidak menggandakan belanja. |
| MFA-02 | TOTP | Pendaftaran, recovery code sekali tampil, reautentikasi, reset aman, uji kehilangan perangkat. |
| SESS-02 | Daftar sesi dan cabut perangkat | Tampilkan waktu/perangkat sewajarnya; cabut sesi server; cache lokal di perangkat terputus dibersihkan saat konek. |
| SPLIT-CAT-02 | Pembagian satu bill ke beberapa kategori atau item struk | Jumlah bagian kategori = porsi Saya; laporan/anggaran menghitung bagian per kategori, kas tetap dihitung sekali. Berbeda dari pembagian antar peserta R1. |
| SPLIT-COLLAB-02 | Undangan peserta dan pembaruan bersama | Memerlukan identitas, izin, persetujuan, kebijakan privasi, dan penyelesaian konflik antar akun; tidak masuk R1. |
| SPLIT-OFFLINE-02 | Outbox split bill iOS | Dependensi bill/settlement/resolution, replay idempoten dan konflik multiperangkat diuji sebelum diaktifkan. |
| SPLIT-MULTIPAYER-02 | Beberapa pembayar awal pada satu bill | Seluruh alokasi kas dan klaim antarpeserta harus jelas, dengan tes rekonsiliasi sebelum diaktifkan. |
| BULK-02 | Edit massal web | Preview perubahan, batas batch, hak akses tiap item, transaksi atomik atau laporan gagal per baris, undo bila memungkinkan. |
| EXPORT-02 | XLSX/PDF/cetak | Nilai identik dengan CSV; aman dari formula injection; tata letak cetak rapi. |
| LANG-02 | Inggris | Seluruh UI, tanggal/angka dan pesan kesalahan diterjemahkan; mata uang tetap IDR kecuali kebijakan produk berubah. |
| SYNC-02 | Delta penuh | Cursor server, jendela tumpang tindih, tombstone, migrasi skema cache, uji dua perangkat dan resume berulang. |
| IOS-G2 | Share Extension, push, distribusi | App Group/izin/sertifikat dan kebijakan diuji; impor Share Extension tetap review, push hanya setelah opt-in. |
| DOMAIN-G3 | Email invoice masuk, Universal Links | Verifikasi domain/pengirim, anti-spoofing, lampiran berbahaya, izin pengguna; email tidak otomatis menjadi transaksi. |
| ANDROID-G4 | Aplikasi Android | Adaptasi UI, izin dan keamanan, tes perangkat, prosedur rilis; penangkap notifikasi tetap backlog terpisah. |

Fitur R2 tidak boleh dipakai untuk mengklaim penyelesaian R1. Semua kemampuan yang tergantung G2/G3/G4 ditulis sebagai rencana, bukan janji tanggal.

## 12. Pengujian, matriks risiko, dan definisi selesai

### 12.1 Strategi uji

- **Domain/unit lintas platform:** fixture JSON yang sama dijalankan di Swift XCTest, TypeScript unit test dan pengujian fungsi PostgreSQL untuk saldo, transfer, split bill dua tipe pembayar/metode, pembulatan, pelunasan/reversal, penghapusan kewajiban/reversal, edit/hapus/undo, anggaran lintas bulan/zona waktu, bigint, QR/CRC, teks, dan dedupe. Target cakupan domain ≥90%, tetapi kelulusan skenario wajib lebih penting daripada persentase.
- **Database/API:** migrasi kosong/upgrade/rollback staging, RLS dan FK komposit dua akun, idempotensi, konkurensi dua klien, constraint porsi dan batas pelunasan/resolusi, reversal/konversi atomik, kuota, Storage, hapus akun, DTO/enum versi lama dan baru. Gunakan fixture sintetis.
- **E2E web:** demo offline, daftar/verifikasi/reset, CRUD, review impor, duplikat, transfer, split bill, pelunasan, dan penghapusan kewajiban dua skenario §3.5, anggaran, filter, CSV, ekspor penuh, hapus akun. Uji responsive mobile/tablet/desktop dan keyboard.
- **E2E iOS SwiftUI:** XCTest/UI test untuk split bill/pelunasan online dan batasan offline, QR gambar, izin ditolak, login/Keychain, Face ID/kode perangkat, proteksi background, SwiftData/outbox offline/restart/reconnect, konflik, logout dan pergantian akun. AVFoundation kamera dan biometrik nyata wajib diuji pada iPhone; Simulator saja tidak cukup. Uji migrasi data lokal v1→v2 dengan outbox pending.
- **Keamanan:** akses silang melalui URL berkas/RPC, injection pencarian/CSV, XSS web, file rusak, token Swift di Keychain dan tidak di UserDefaults/log, file SwiftData/sidecar dengan Data Protection, isolasi akun saat logout/offline, serta job berulang. Periksa konfigurasi izin iOS dan App Privacy sebelum distribusi.
- **Aksesibilitas, visual, dan kegunaan:** VoiceOver, Dynamic Type, fokus keyboard, 44 pt, kontras, kesalahan form, label bar anggaran; tangkap layar dan periksa lima layar inti pada terang/gelap di iOS serta web ponsel, web desktop, iPhone kecil, dan teks 200%; lakukan 20 percobaan input cepat dan 10 percobaan split bill tanpa bantuan sesuai §6.8.

**Fixture tetap:** transaksi contoh §3.4 dan split bill §3.5; total Rp100.000 untuk tiga peserta (pembulatan 33.334/33.333/33.333), persentase pecahan, peserta Rp0, pelunasan Rp15.000 + Rp25.000, overpay Rp1, penghapusan piutang/utang serta reversalnya, edit setelah pelunasan ditolak, hapus/retry idempotensi, transaksi biasa dikonversi tanpa ganda, dua akun berbeda; QRIS sintetis valid dan CRC salah; QR non-QRIS; gambar tanpa QR; PDF teks dan PDF hasil scan; teks nominal ambigu; dua struk sama; dua pembelian berbeda dengan nominal sama; offline edit pada dua perangkat. Fixture tidak mengandung bukti bayar asli.

### 12.2 Risiko dan respons

| Risiko | Respons dan pemeriksaan |
| --- | --- |
| Scan QR disalahartikan sebagai pembayaran | Label catatan jelas, tidak ada tombol Bayar, persetujuan pengguna sebelum posted, uji copy. |
| Salah saldo karena transfer/duplikat/offline | Invarian ledger, review wajib, idempotensi, version check dan tes properti. |
| Split bill dihitung dua kali atau pelunasan menjadi pemasukan | Pisahkan arus kas, pengeluaran pribadi, piutang/utang; constraint dan contoh §3.5, uji seluruh ekspor dan anggaran. |
| Peserta split bill mengira aplikasi menagih/memverifikasi pembayaran | Teks UI jelas; berbagi ringkasan manual, pelunasan manual, tidak mengirim pesan otomatis. |
| Kebocoran data lintas pengguna | RLS/FK/Storage di server, uji dua identitas, audit fungsi privileged. |
| Token atau cache iOS tersimpan tidak aman | Audit Keychain Supabase Swift, Data Protection store dan sidecar, logout/restore, serta uji perangkat asli. |
| Aturan saldo berbeda antara Swift dan TypeScript | Server sebagai sumber kebenaran, kontrak versi dan fixture lintas platform di CI; operasi offline direkonsiliasi. |
| Rilis server memutus klien iOS lama | Migrasi additive, uji kompatibilitas versi sebelumnya, feature flag, dan tahapan staging. |
| OCR tidak akurat | R2 opt-in, tidak di jalur kritis, selalu review. |
| Backend gratis terjeda atau email habis | Demo lokal independen, pemantauan kuota, layanan email sesuai kebutuhan sebelum pendaftaran publik. |
| G0/G1 tidak tersedia | Serahkan R1 web, pertahankan penanda iOS belum diverifikasi; jangan menandai fase iOS selesai. |
| Kebijakan toko/layanan berubah | Tinjau dokumen resmi sebelum distribusi, bukan mengunci klaim historis. |
| Hapus akun parsial | Job idempoten, status dapat dilacak, retry dan pemeriksaan objek yatim. |

### 12.3 Definisi selesai R1

R1 dinyatakan selesai **per platform**: iOS native selesai hanya setelah semua P0/P1 iOS, golden fixtures, uji iPhone asli, Keychain, SwiftData/Data Protection, offline, privacy screen, QA visual §6.8, dan G0/G1 lulus. Web selesai setelah P0/P1 web, demo tanpa server, parser/review, split bill sesuai §3.5, ekspor/hapus, aksesibilitas, QA visual §6.8, dan E2E lulus. Backend bersama harus lulus migrasi/RLS/kontrak dan uji dua klien sebelum salah satu rilis berakun nyata. Untuk demo publik dengan akun nyata, kebijakan privasi, penghapusan akun, SMTP yang memadai, pembatasan penyalahgunaan, dan proses backup/restore juga harus siap. Hasil uji serta keterbatasan terbuka dicatat di README; tidak ada fitur berstatus “selesai” hanya karena UI tampil.

## 13. Roadmap dan hasil tiap fase

| Fase | Perkiraan satu pengembang | Hasil terukur dan gerbang |
| --- | --- | --- |
| **0 Fondasi bersama** | 2–3 minggu | Monorepo, kontrak v1 dan fixture emas, Supabase migrasi/RLS/RPC ledger, uji dua pengguna/konkurensi, token desain §6 dan sketsa lima layar inti, CI web + macOS; G0 untuk scaffold iOS. |
| **1 iOS inti native** | 4–6 minggu | SwiftUI auth/OTP, demo, akun, transaksi/transfer, split bill/pelunasan, anggaran/laporan, Keychain, komponen native dan mode terang/gelap, build Simulator; G0. Uji kamera/biometrik menunggu G1. |
| **2 Web inti** | 3–5 minggu | Vue auth/OTP, demo, akun, transaksi/transfer, split bill, anggaran, laporan/CSV, ekspor/hapus; Plus Jakarta Sans lokal, komponen responsif dan mode terang/gelap; kontrak lintas klien lulus. |
| **3 Impor pada keduanya** | 3–5 minggu | QR kamera iOS/gambar dua klien, PDF-teks, tempel teks, review, duplikat, lampiran dan konversi ke bill; uji fixture/parser identik. |
| **4 Offline dan pengerasan R1** | 2–4 minggu | SwiftData + Data Protection/outbox, konflik/reconnect, penyelesaian hapus akun, aksesibilitas, QA visual §6.8, kinerja, backup/restore, uji iPhone asli; G1 wajib untuk menyatakan R1 iOS selesai. |
| **5 R2 dan distribusi** | Sesuai pilihan; belum dijadwalkan | OCR/CSV/target/fitur lanjutan, TestFlight/App Store dan domain sesuai G2/G3. Android terpisah setelah keputusan produk. |

Total indikatif R1 **14–23 minggu kerja efektif satu pengembang** dan dapat berubah setelah spike dan tes perangkat. Durasi belum memasukkan antrean akun, perangkat, review toko, perbaikan keamanan, atau domain. Tiap fase menghasilkan build yang dapat diperiksa, hasil tes, dan keputusan arsitektur tertulis. Web boleh dikerjakan bersamaan hanya bila kapasitas pengembang memungkinkan; satu pengembang mengikuti urutan di atas.

## 14. Artefak portofolio dan operasional

Repo berisi README dengan tujuan, demo, screenshot/GIF tanpa data asli, langkah setup **web dan Xcode iOS secara terpisah**, diagram arsitektur dua klien, aturan offline, skema/kontrak data, daftar fitur R1/R2, keterbatasan; `.env.example`, lisensi font dan ikon, `contracts/design-tokens.json`, contoh layar dan hasil QA visual, migrasi, fixture emas lintas bahasa, tes, CI Linux + macOS (lint/typecheck/XCTest/unit/pgTAP/build/secret scan), ADR untuk ledger/split bill, pilihan SwiftUI + Vue, Keychain/Data Protection, RLS, bigint, dan outbox. Tambahkan studi kasus masalah→keputusan→hasil terukur serta video 60–90 detik menggunakan data demo. Jangan tampilkan klaim performa, keamanan, atau akurasi OCR tanpa hasil uji bertanggal.

## 15. Rujukan dan hal yang harus diverifikasi saat implementasi

1. Bank Indonesia, [penjelasan QRIS](https://www.bi.go.id/id/fungsi-utama/sistem-pembayaran/ritel/kanal-layanan/QRIS/default.aspx): QRIS MPM statis/dinamis dan alur pengguna. Interpretasi produk: pemindaian kode tidak menyediakan konfirmasi pembayaran untuk Danarapi.
2. [Supabase Auth rate limits](https://supabase.com/docs/guides/auth/rate-limits), [template email](https://supabase.com/docs/guides/auth/auth-email-templates), [inisialisasi JS](https://supabase.com/docs/reference/javascript/initializing), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), dan [Storage access control](https://supabase.com/docs/guides/storage/security/access-control). Periksa kuota dan opsi SDK pada versi yang dipakai; jangan salin angka batas layanan sebagai janji produk.
3. Apple, [Keychain dengan Face ID/Touch ID](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id) dan [persyaratan penghapusan akun](https://developer.apple.com/news/?id=12m75xbj). Periksa pedoman toko, privacy manifest, entitlement, perangkat minimum, dan izin terbaru sebelum distribusi.
4. Apple, [SwiftUI](https://developer.apple.com/documentation/swiftui), [SwiftData](https://developer.apple.com/documentation/swiftdata), [Data Protection](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files), [AVFoundation QR](https://developer.apple.com/documentation/avfoundation/avmetadataobject/objecttype/qr), dan [PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker). Uji target iOS dan perilaku file store nyata.
5. Supabase, [SDK Swift](https://supabase.com/docs/reference/swift/introduction) untuk Auth, database, Storage, dan fungsi server; verifikasi penyimpanan sesi pada versi SDK yang dikunci.
6. [Plus Jakarta Sans oleh Tokotype](https://github.com/tokotype/PlusJakartaSans) dan [lisensi font di repositori Google Fonts](https://github.com/google/fonts/blob/main/ofl/plusjakartasans/OFL.txt). Periksa berkas final/subset dan sertakan lisensi ketika di-host sendiri di web.
7. Apple, [Fonts](https://developer.apple.com/documentation/technologyoverviews/fonts) untuk font sistem, desain rounded, dan batas distribusi font; iOS memakai font melalui API sistem.
8. W3C, [WCAG 2.2 Contrast (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) dan [Non-text Contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html) untuk evaluasi teks serta komponen pada kedua tema.

**Akhir spesifikasi.** Perubahan ruang lingkup selanjutnya dilakukan melalui revisi bernomor yang menyebut ID kebutuhan terdampak, alasan, dampak data/API, dan tes penerimaannya.
