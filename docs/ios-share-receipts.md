# Bukti transaksi melalui Share iOS

Danarapi menerima bukti yang dibagikan aplikasi lain melalui Share Sheet iOS. Ini bukan koneksi API bank dan tidak mengambil riwayat rekening otomatis. Aplikasi bank harus menyediakan tombol Bagikan; jika tidak tersedia, bagikan screenshot melalui Foto atau PDF melalui Files.

## Alur pemakaian

1. Masuk ke akun Danarapi tujuan terlebih dahulu. Buka bukti transaksi di aplikasi bank, Foto, atau Files. Pilih **Bagikan > Danarapi > Simpan draft**. Jika Danarapi belum terlihat, buka **More/Lainnya** pada daftar aplikasi Share. Bukti langsung disimpan dengan pemilik akun aktif; belum login atau Mode Demo tidak dapat menyimpan bukti pribadi.
2. Buka **Beranda > Tinjauan > Bukti dari Share** pada akun yang sama. Bukti tetap tersimpan lokal ketika offline atau logout, tetapi hanya terlihat oleh pemiliknya. Akun baru mempunyai daftar kosong. Layar awal tidak menampilkan Demo atau Bukti dari Share.
3. Klik berkas draft setelah masuk akun. Baris berkas menampilkan **Menyiapkan draft** selama foto, halaman PDF, atau teks dibaca oleh AI; halaman detail dibuka setelah hasil siap, langsung berisi nominal, merchant/penerima, tanggal, dan rincian lainnya. Hasil yang sudah tersimpan digunakan saat membuka ulang. Bagian Pembacaan AI serta tombol Baca dengan AI tidak ditampilkan. Persetujuan AI diaktifkan dan disimpan untuk akun tanpa dialog berulang. Saat belum masuk/offline, Vision/PDFKit memberi hasil lokal. Gangguan AI membuka isian manual dengan pesan kegagalan; **Coba lagi** tersedia.
4. AI membaca nominal pokok, merchant/penerima, tanggal/jam, penyedia, biaya admin efektif, total, status, jenis transaksi, dan referensi. Merchant bukan nama pemilik rekening sumber atau logo bank. Biaya dicoret dengan Gratis berarti biaya efektif nol. Nominal kosong jika status belum berhasil, mata uang bukan IDR/belum jelas, atau nominal + biaya tidak sesuai total. Angka yang belum pasti tetap kosong.
5. Hasil AI tersimpan lokal secara terlindungi untuk akun pemilik, sesuai pemilik yang ditetapkan sejak Share disimpan. Membuka ulang bukti menggunakan hasil tersebut. Koreksi manual yang sudah dilakukan tidak ditimpa oleh AI. Tanggal tanpa zona tercetak memakai zona akun; jam yang tidak terbaca perlu diperiksa. Jenis transfer merupakan petunjuk, bukan keputusan bahwa kedua akun milik pengguna.
6. Hubungkan internet, lalu **Simpan ke draft akun ini**. Konfirmasi menampilkan akun tujuan. Pemilik tidak dapat berubah; pergantian akun tidak memindahkan bukti atau unggahan.
7. Pilih **Tinjau draft transaksi**, lalu tentukan pemasukan/pengeluaran, akun bank, kategori, nominal dan tanggal. Saldo berubah hanya setelah pencatatan dikonfirmasi. Transfer antar dua akun sendiri menggunakan **Transfer antar akun sendiri** pada draft, bukan pengeluaran.

## Pembacaan bukti bank

- Parser mengenali label nominal transaksi seperti `Nominal Transfer`, `Nominal Transaksi`, `Jumlah Transfer`, dan `Transaction Amount`, termasuk nilai pada baris berikutnya.
- Format Rupiah Indonesia dan format IDR dengan pemisah ribuan Inggris didukung. Contoh: `Rp 150.000,00` dan `IDR 150,000.00` sama-sama menjadi 150000 Rupiah.
- Saldo, nomor rekening, nomor referensi, total debit, dan biaya admin tidak digunakan sebagai nominal transaksi. Biaya admin perlu dicatat terpisah sebagai pengeluaran.
- Beberapa nominal berbeda, format yang tidak terbaca, mata uang lain, pecahan nonnol, serta status gagal/pending membuat nominal tetap kosong. Tidak ada transaksi yang diposting otomatis.
- Tanggal dan nama penerima hanya diisi saat label serta nilainya dapat dibaca dengan jelas. Semua hasil memiliki keyakinan rendah dan harus diperiksa dengan bukti asli.
- Teks pendamping gambar/PDF disimpan sebagai bukti pembacaan; tidak menimpa nominal yang dibaca dari berkas.
- Foto/PDF bukti transaksi bukan jaminan pembayaran berhasil. Pengguna tetap memeriksa status di aplikasi bank.

## Penyimpanan, batas, dan retry

- JPEG, PNG, HEIC, PDF, serta teks UTF-8. Maksimal 5 bukti per share, 5 MB per berkas, dan 64 KB teks. Link saja tidak diterima dan tidak diambil lewat jaringan.
- Kiriman aplikasi bank dapat berupa berkas sementara, data langsung, objek gambar iOS, atau file URL. Pembaca mencoba representasi alternatif bila berkas sementara tidak tersedia. TIFF/format gambar lain yang dapat dibaca ImageIO disalin ke JPEG; antarmuka menjelaskan konversi agar pengguna tetap memeriksa bukti asli di aplikasi bank.
- Tautan pendamping gambar/PDF dan keterangan kosong tidak menggagalkan bukti yang valid. Link pendamping tidak dibuka atau diunduh. Satu gambar dan URL pendamping tetap menghasilkan satu draft.
- Jika kiriman tidak terbaca, pilih **Coba baca ulang**. **Detail format kiriman** menampilkan jenis UTI yang dikirim, tanpa isi rekening, nominal, URL, atau nama berkas. Bila aplikasi bank tidak menyediakan isi bukti, simpan bukti ke Foto/Files lalu bagikan dari sana.
- Pembacaan provider memiliki timeout dan mendukung pembatalan. Callback terlambat tidak mengulang penyimpanan atau membuat aplikasi macet. Share dengan satu bukti yang gagal dibaca tidak menyimpan berkas lain secara diam-diam.
- Satu berkas menjadi satu draft. Beberapa berkas tidak digabung menjadi satu transaksi. Satu share disimpan secara utuh; kegagalan validasi tidak menyimpan sebagian berkas.
- Pembacaan PDF otomatis maksimal tiga halaman. PDF terkunci, rusak, terlalu banyak halaman, atau OCR gagal tetap dapat ditinjau secara manual dengan lampiran asli.
- Kotak lokal menampung maksimal 50 bukti dan 100 MB isi berkas per akun. Salinan tersimpan sampai pemilik memilih **Hapus lokal**. Menghapus salinan yang sudah diimpor tidak menghapus draft server atau transaksi.
- App dan extension menggunakan App Group `group.id.danarapi.app`. Berkas menggunakan Complete File Protection, dikecualikan dari backup, dan ditulis atomik. Penguncian lintas proses mencegah app dan extension saling menimpa.
- Share berulang dengan isi berkas identik memakai ID draft yang sama pada akun yang sama selama salinan lokal masih ada. Berkas identik yang dibagikan akun lain mendapat ID dan salinan tersendiri. Duplikasi tidak mencari bukti milik akun lain.
- Share Sheet menangkap akun serta revisi sesi sebelum membaca kiriman dan memeriksanya kembali saat menyimpan, di dalam penguncian penyimpanan. Logout/pergantian akun membatalkan penyimpanan dari Share Sheet lama, termasuk jika pengguna kembali ke akun yang sama.
- Bukti lama tanpa pemilik tidak ditampilkan atau diikat otomatis ke akun mana pun, karena pemilik sebelumnya tidak dapat dipastikan. Berkas tetap dipertahankan lokal; bagikan ulang bukti dari sumber dengan akun yang benar. Bukti lama yang sudah mempunyai pemilik tetap tersedia untuk akun tersebut.
- Unggah gagal mempertahankan bukti lokal dan ID draft. Retry memeriksa lampiran berdasarkan hash agar respons unggah yang terputus tidak menggandakan lampiran. Draft yang telah selesai tidak dibuka ulang sebagai pending.
- Pencatatan pemasukan/pengeluaran memakai konfirmasi draft server yang sudah ada. Semua permintaan Share memeriksa akun tujuan sebelum mengirim token/bukti.
- Transfer memakai UUID draft sebagai ID mutasi ledger. Rincian percobaan transfer disimpan sebelum permintaan jaringan dan dipertahankan saat retry atau app dibuka ulang. Bila transfer berhasil tetapi penyelesaian draft gagal, retry menggunakan rincian yang sama; perubahan rincian ditolak untuk menghindari pencatatan ganda.
- Peringatan duplikat adalah bantuan pemeriksaan, bukan jaminan. Foto dan PDF dari transaksi yang sama dapat memiliki isi berbeda dan menjadi dua draft. Periksa sebelum mencatat.
- Mode Demo tidak mengunggah bukti pribadi. Logout menyembunyikan bukti yang telah terikat akun; masuk kembali dengan akun yang sama untuk melanjutkan.

## Proyek dan pengujian

`apps/ios/scripts/generate_project.rb` membuat target `DanarapiShare`, memasangnya sebagai extension aplikasi, menyertakan sumber inbox bersama dan entitlement App Group. Team signing proyek yang sudah ada dipertahankan. App Group harus tersedia pada provisioning app dan extension.

Pengujian menggunakan bukti sintetis berlabel BSI di iPhone 13 Rakan, bukan Simulator dan bukan transaksi bank nyata. Uji mencakup Share Sheet teks/foto/PDF, OCR, persistensi setelah relaunch, batas berkas, duplikasi, akun tujuan, upload timeout, nominal ambigu, ledger tidak berubah saat impor, serta retry transfer. Sumber tes: `SharedInboxTests.swift` dan `SharedReceiptUITests.swift`. Entry Share sintetis hanya muncul pada build DEBUG dengan argumen `--ui-testing-share`.

Hasil dan lokasi bukti perangkat dicatat di `docs/ios-r1-testing.md`. Alur aplikasi BSI sebenarnya tetap perlu dicoba memakai bukti pengguna; tidak ada login, pembayaran, atau pesan ke bank yang dilakukan oleh pengujian ini.

Pembaruan AI 5 Oktober 2026: 110 tes unit aplikasi dan satu uji UI Share Sheet teks lulus pada iPhone 13 Rakan (`/tmp/danarapi-ios-bank-ai-auto.xcresult`). 25 tes logika scan/bank dan tujuh tes autentikasi/consent endpoint lulus; typecheck backend dan web lulus. Panggilan Gemini nyata melalui endpoint cloud menggunakan dua gambar sintetis: BSI menghasilkan nominal 45900, merchant Tokopedia, penerima TPRTokopediaShop, tanggal 2026-10-05, jam 10:23:50, biaya 0; GoPay menghasilkan nominal 10000, penerima M Rakan Naufal, tanggal 2026-09-29, jam 13:10:00, biaya efektif 0 meskipun biaya Rp2.000 dicoret. Cache dan ketiadaan transaksi ledger diperiksa; akun uji sementara sudah dihapus (`/tmp/danarapi-bank-ai-cloud-smoke.log`). Gambar pengguna tidak dikirim dalam pengujian ini. Uji UI memakai Demo sehingga tidak membuktikan ekstraksi cloud otomatis dengan sesi pengguna di iPhone.
