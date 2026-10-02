# Audit kesiapan produksi Danarapi

Tanggal: 2 Oktober 2026. Cakupan: kode web, iOS, database, layanan cloud, dan konfigurasi pengujian. Ini bukan sertifikasi keamanan, audit hukum, atau bukti seluruh layar/perangkat sudah lolos pengujian.

Prioritas: P0 sebelum rilis publik; P1 untuk pengalaman produk lengkap; P2 pengembangan setelah fondasi stabil. Status "belum ditemukan" merujuk implementasi di repository, bukan klaim mengenai seluruh konfigurasi dashboard penyedia.

Audit ditinjau ulang setelah perubahan peserta split bill dan tampilan laporan. Pemeriksaan ini membaca sumber lokal, bukan dashboard Vercel/Supabase atau hasil App Store review. Tidak ada perubahan fitur maupun data pengguna dalam audit ini.

## Fondasi yang sudah tersedia

- Login Google, pencatatan transaksi, akun keuangan, kategori, target, anggaran, dan laporan.
- Scan struk AI melalui server, tinjauan draft, QRIS untuk pencatatan, dan impor foto/PDF.
- Split bill dengan rincian, diskon, pajak/service, pembulatan, dan pencatatan pelunasan.
- Ekspor data/lampiran dan penghapusan akun dengan autentikasi ulang Google. Keduanya tidak perlu dibuat ulang.
- RLS pemilik, idempotensi ledger, konflik versi, dan storage privat.
- Cache dan antrean perubahan offline iOS; retry/error awal pada web dan iOS.
- Mode terang/gelap, input rupiah, beberapa pengujian aksesibilitas dan fixture lintas platform.
- Perbaikan terbaru: transaksi sebelum tanggal pembukaan akun, pembuka iOS berlogo, dan grafik/tata letak web.

## 1. Halaman publik dan bantuan

| Prioritas | Halaman | Kondisi sekarang | Penyelesaian yang disarankan |
| --- | --- | --- | --- |
| P0 | Kebijakan privasi | Web memiliki halaman ringkas; iOS hanya disclosure pengaturan | Satu dokumen resmi dengan versi/tanggal, identitas pengelola, data, tujuan, penyedia, retensi, hak pengguna, dan kontak; dapat dibaca sebelum login pada kedua platform |
| P0 | Syarat penggunaan | Halaman khusus belum ditemukan | Batas layanan, tanggung jawab verifikasi struk, bukan bank/pembayaran, akun, penghentian layanan, serta mekanisme keluhan; isi ditinjau pemilik/legal |
| P0 | Kontak dukungan | Web bergantung `VITE_SUPPORT_EMAIL`; kanal iOS khusus belum ditemukan | Tetapkan alamat dukungan yang benar-benar dipantau; tombol bantuan login, scan, dan masalah data; jangan memakai alamat contoh |
| P0 | Cara menghapus akun | Penghapusan dalam aplikasi sudah ada; `/hapus-akun` mengarah ke pengaturan | Halaman publik menjelaskan langkah, data yang dihapus, pengecualian retensi, serta kontak jika akun tidak dapat diakses |
| P1 | Tentang Danarapi | Web punya paragraf di privasi; layar iOS khusus belum ditemukan | Identitas singkat, tujuan aplikasi, versi/build, batas layanan, tautan privasi/syarat/bantuan |
| P1 | FAQ dan panduan | Disclosure tersebar; pusat bantuan belum ditemukan | FAQ pencatatan, saldo awal, target, anggaran, scan, QRIS, split bill, sinkronisasi, ekspor, dan penghapusan |
| P1 | Lapor masalah | Error memiliki pesan/ID; pengiriman laporan belum ditemukan | Formulir/topik atau email terstruktur; sertakan versi dan ID request, bukan token atau data keuangan otomatis |
| P1 | Keamanan dan data | Kontrol tersebar di pengaturan | Gabungkan ekspor, penghapusan, penjelasan sinkronisasi, perangkat/sesi, dan pengunci; tindakan berbahaya tetap dikonfirmasi |
| P2 | Halaman pengantar web | Halaman publik utama adalah login dengan cerita singkat | Pengantar pendek: manfaat, tiga fitur, tombol masuk, tautan bantuan/legal; tidak perlu landing page panjang |
| P2 | Status layanan dan catatan versi | Halaman khusus belum ditemukan | Status login/data/scan serta catatan perubahan versi; hanya tampilkan status yang berasal dari pemeriksaan nyata |

FAQ awal yang paling berguna: mengapa saldo berbeda dari bank; apakah QRIS melakukan pembayaran; cara mencatat transaksi lama; scan gagal/angka keliru; siapa membayar biaya tambahan split bill; apakah target mengurangi saldo; apakah limit anggaran mengurangi saldo; data offline belum muncul di web; cara memperbaiki transaksi; ekspor dan penghapusan akun.

## 2. Privasi, keamanan, dan distribusi

| Prioritas | Temuan | Langkah penerimaan |
| --- | --- | --- |
| P0 | Scan mengirim gambar ke AI; persetujuan pengiriman terpisah belum ditemukan dalam alur scan | Informasi singkat sebelum upload pertama, persetujuan eksplisit, versi kebijakan, batal/isi manual, dan cara menarik persetujuan; QRIS lokal tidak memakai persetujuan AI yang tidak relevan |
| P0 | Teks privasi web masih menyebut penghapusan dengan kata sandi, sedangkan implementasi Google melakukan autentikasi ulang | Samakan dokumentasi dengan perilaku nyata pada web dan iOS |
| P0 | Manifest iOS memuat array collected-data kosong | Inventaris data nyata dan pemrosesan pihak ketiga; cocokkan manifest, disclosure App Store, dan kebijakan. Manifest bukan pengganti disclosure App Store |
| P0 | iOS hanya menawarkan Google | Evaluasi kesesuaian dengan ketentuan distribusi/App Store yang berlaku sebelum pengiriman. Jangan mengaktifkan metode login lain tanpa keputusan pemilik |
| P0 | Secret AI pernah dibagikan dalam percakapan | Konfirmasi rotasi secret tersebut; tetap server-only. Publishable key Supabase adalah konfigurasi publik, bukan service-role key |
| P0 | Ada fungsi retensi; aktivasi/jadwal produksi dan retensi backup belum terverifikasi | Tetapkan jadwal, notifikasi, retensi, pemantauan gagal, serta bukti uji restore; jangan menjanjikan penghapusan backup instan |
| P1 | Pengelolaan sesi/perangkat pengguna belum ditemukan sebagai halaman | Tampilkan sesi aktif bila backend mendukungnya; keluarkan perangkat lain dengan autentikasi ulang dan konfirmasi |
| P1 | Pemantauan crash/alert operator belum terlihat sebagai alur lengkap | Catat versi, kode error, request ID, dan latency tanpa foto, OCR, nominal pribadi, email, atau token; beri alert kegagalan berulang |

Kebijakan AI harus mengikuti paket layanan yang benar-benar dipakai. Jangan menyatakan gambar tidak pernah disimpan/digunakan penyedia sebelum hal itu diverifikasi. Tidak perlu banner cookie promosi jika aplikasi tidak memakai pelacakan yang memerlukannya; keputusan mengikuti penggunaan nyata dan peninjauan yang sesuai.

## 3. Konsistensi web dan iOS

| Prioritas | Perbedaan/celah | Penyelesaian |
| --- | --- | --- |
| P0 | Web mendukung zona waktu profil; `MonthPeriod` iOS memakai `Asia/Jakarta` tetap | Pilih kebijakan produk: Jakarta untuk semua atau profil untuk keduanya. Uji transaksi dekat tengah malam dan batas bulan agar laporan tidak berbeda |
| P1 | Laporan web mendukung bulanan/tahunan; UI iOS masih memilih bulan | Tambahkan tahunan/rentang pada iOS dengan agregasi server sama, atau batasi opsi bersama secara eksplisit |
| P1 | Laporan iOS dimulai dari nol sebelum respons; error awal dashboard sudah dibedakan | Beri status pemuatan/error/retry khusus laporan, jangan menyajikan nol sebagai laporan sukses bila request gagal |
| P1 | Web memerlukan internet saat simpan; iOS memiliki antrean transaksi offline | Jelaskan kemampuan offline yang berbeda. Jika paritas diperlukan, simpan draft/antrean web dengan isolasi pemilik dan penanganan konflik |
| P1 | Refresh ada; langganan realtime antarperangkat belum ditemukan | Pilih refresh saat fokus/manual atau subscription aman; tampilkan waktu sinkronisasi dan pastikan perubahan iOS terlihat di web tanpa menimpa edit |
| P1 | Banyak kontrol dan teks ditulis terpisah | Gunakan kontrak data/error dan glossary bersama; tabel paritas setiap fitur dengan fixture yang identik |

## 4. Fitur lanjutan yang bernilai

| Prioritas | Fitur | Batas penting |
| --- | --- | --- |
| P1 | Onboarding akun nyata | Tur iOS dan pembuatan akun Tunai awal sudah ada; lengkapi panduan saldo awal, akun lain, dan transaksi pertama. Jangan mengganti tur yang sudah tersedia atau menganggap saldo awal sebagai pemasukan |
| P1 | Riwayat progres target | Kontribusi sudah tercatat sebagai transaksi; tambahkan tampilan detail target yang memfilter kontribusi, tanggal, akun, edit/hapus, dan dampak saldo, bukan membuat ledger kedua |
| P1 | Anggaran bulan berikutnya | Salin limit/kategori tanpa menyalin transaksi; rollover bersifat pilihan, bukan saldo tambahan |
| P1 | Impor ulang CSV/arsip | Preview, mapping, validasi, deteksi duplikat, pembatalan, dan transaksi atomik. Ekspor sudah ada; restore pengguna belum ditemukan |
| P1 | Pembatalan/refund pengeluaran | Bedakan koreksi salah input, penghapusan, dan uang benar-benar kembali. Pilih model ledger yang tidak menghitung pengeluaran/pemasukan dua kali |
| P2 | Pengingat target/anggaran | Izin notifikasi, jadwal, preferensi, dan pencegahan spam; reminder otomatis belum ditemukan, bukan sekadar teks bagikan split bill |
| P2 | Transaksi berulang | Preview/konfirmasi tanggal dan akun; eksekusi idempotent; jangan membuat transaksi otomatis hanya karena aplikasi dibuka |
| P2 | Split bill bersama | Ringkasan/rincian sudah ada; kolaborasi peserta melalui tautan terproteksi merupakan fitur berbeda, bukan akses publik ke rekening |
| P2 | Pencarian laporan lebih luas | Rentang khusus, akun/kategori/target, dan ekspor periode yang sama; total harus konsisten dengan filter |
| P2 | PWA web | Instalasi, ikon, cache aman, serta kejelasan kemampuan offline; jangan meng-cache respons pengguna secara lintas akun |

Anggaran adalah limit, bukan transaksi pengeluaran. Progres target yang dibayar dari akun adalah transaksi. Dashboard/laporan harus membedakan rencana, uang terkumpul, dan arus uang agar tidak dijumlahkan dua kali.

## 5. Operasional dan pengujian

- Terapkan seluruh perubahan sumber melalui pipeline rilis; database/Edge yang aktif tidak berarti bundle Vercel atau aplikasi terpasang sudah terbaru.
- Workflow sudah menjalankan `test:edge`. Daftar `deno check` masih belum mencantumkan `receipt-scan`; pastikan validasi endpoint scan dan seluruh dependensinya eksplisit. Adanya langkah CI bukan bukti run terbaru berhasil atau sumber sudah dipublikasikan.
- Uji login Google interaktif akun nyata, batal login, sesi habis, callback salah, dan pergantian akun. Uji unit PKCE bukan pengganti login nyata.
- Uji scan struk nyata yang sama pada web/iOS: kecil, miring, gelap, diskon, pajak termasuk harga, unit/qty, PDF multi-halaman, pembulatan, dan total tidak terbaca.
- Uji iPhone melalui seluler tanpa Mac: scan, simpan, refresh web, restart, offline, serta sinkronisasi ulang.
- Uji aksesibilitas dengan VoiceOver, keyboard, Dynamic Type besar, zoom browser, warna, reduced motion, dan ukuran layar kecil; pengujian otomatis saja belum cukup.
- Uji histori panjang dan pagination. Web saat ini mengambil semua halaman transaksi ketika snapshot dimuat; ukur performa dan pindahkan pemuatan riwayat ke pagination jika perlu.
- Verifikasi backup/restore produksi, staging, kuota AI, rate limit, budget biaya, dan penanganan penyedia gagal; uji database lokal tidak membuktikan semua konfigurasi operasional cloud.

## 6. Struktur minimal yang disarankan

Web publik: Masuk, Tentang, Bantuan/FAQ, Kontak, Privasi, Syarat, Cara hapus akun. Tautan legal/bantuan cukup di footer, bukan memenuhi dashboard.

Web dalam akun: pertahankan navigasi inti. Letakkan bantuan, tentang, keamanan/data, dan versi dalam pengaturan/menu profil.

iOS: pertahankan bottom navigation inti dan scan tengah. Tambahkan grup Pengaturan → Tentang & Bantuan serta Pengaturan → Keamanan & Data. Dokumen legal yang sama dapat dibuka dari login/onboarding dan pengaturan.

Urutan pengerjaan: P0 privasi/dukungan/distribusi; kesamaan zona waktu dan data; konsistensi loading/sinkronisasi; halaman bantuan; fitur finansial lanjutan. Jangan memperbesar navigasi utama hanya untuk menambahkan semua halaman.

## 7. Kriteria selesai dan urutan implementasi

### Tahap A: fondasi publik

- Tentang: tujuan, batas layanan, pemilik/pengelola, versi, dan tautan bantuan/legal. iOS menambahkan nomor build; web tidak perlu menampilkan detail teknis kepada semua pengunjung.
- Privasi: satu sumber dokumen, versi/tanggal, jenis data, tujuan, pihak ketiga, retensi, ekspor/penghapusan, dan kontak. Teks penghapusan cocok dengan autentikasi ulang Google, bukan kata sandi yang sudah tidak digunakan.
- Syarat: ruang lingkup pencatatan, tanggung jawab memeriksa hasil scan, akun, penghentian layanan, serta penyelesaian masalah. Pemilik menentukan isi dan peninjauan legal, bukan dokumen generik tanpa identitas.
- Kontak: kanal yang sudah aktif, pilihan topik, pesan, dan lampiran opsional. Jangan mengarang email, jam layanan, maupun jaminan waktu tanggapan.
- Cara hapus akun: dapat dibuka tanpa login; bedakan instruksi publik dengan aksi penghapusan yang memerlukan login, autentikasi ulang, dan konfirmasi.
- FAQ: pencarian/topik ringkas. Jawaban penting mencakup saldo awal, tanggal transaksi lama, target, limit anggaran, QRIS bukan pembayaran, split bill, scan, sinkronisasi, ekspor, dan penghapusan.
- AI: sebelum unggahan pertama, jelaskan pengiriman ke pihak ketiga dan minta persetujuan. Simpan versi persetujuan, sediakan pembatalan/isi manual, dan pengaturan untuk menariknya. Informasi ini bukan pengembalian kartu penjelasan panjang di setiap layar scan.

Penerimaan: halaman legal/bantuan bisa diakses sebelum dan sesudah login; dokumen sama pada kedua platform; tautan tidak buntu; tampilan light/dark dan teks besar terbaca. Google-only perlu ditinjau terhadap ketentuan distribusi Apple dan pengecualian yang berlaku, bukan langsung mengaktifkan Apple tanpa persetujuan pemilik.

### Tahap B: akurasi dan ketahanan

- Zona waktu: satu kebijakan pada web/iOS/backend; fixture dekat tengah malam dan pergantian bulan menghasilkan tanggal, saldo, dan laporan sama.
- Laporan: loading/error/retry iOS terpisah dari nol nyata; pilihan bulanan/tahunan serta ekspor memiliki periode dan total konsisten.
- Sinkronisasi: pengguna melihat status terakhir tersinkron dan perubahan pending. Refresh setelah pindah perangkat tidak menimpa perubahan lokal atau menggandakan transaksi.
- Scan: struk fixture identik menghasilkan rincian qty/harga/diskon/service/pajak/pembulatan yang sama melalui normalisasi bersama. Bandingkan input yang sama, bukan menjanjikan keluaran model generatif selalu identik pada dua request berbeda. Angka tidak terbaca tetap bisa dikoreksi.
- Draft: pertimbangkan pemulihan input belum tersimpan saat aplikasi tertutup atau browser dimuat ulang; isolasi akun dan pembersihan setelah logout wajib dirancang jika penyimpanan draft ditambahkan.
- Performa: ukur akun dengan histori panjang; pagination UI tidak cukup bila seluruh snapshot tetap diunduh saat startup.

Penerimaan: uji akun nyata dan akun baru, pembatalan OAuth, sesi kedaluwarsa, jaringan seluler tanpa Mac, offline/reconnect, konflik edit, submit ganda, rotasi layar, VoiceOver, dan Dynamic Type. Catat hasil uji perangkat yang benar-benar dijalankan; jangan menyebut build sukses sebagai UI test sukses.

### Tahap C: kelengkapan produk

- Detail target: ringkasan, tenggat/countdown, riwayat kontribusi, dan akses ke transaksi terkait.
- Detail anggaran: kategori, limit, transaksi pembentuk realisasi, status 70%/melewati limit, serta salin rencana bulan berikutnya.
- Restore pengguna: impor CSV/arsip dengan preview, mapping akun/kategori, deteksi duplikat, dan pembatalan. Backup operator dan restore pengguna adalah dua fitur berbeda.
- Pengembalian dana: definisikan refund sebagai kejadian keuangan terpisah dari koreksi atau penghapusan salah input; ledger dan laporan harus jelas.
- Setelah stabil: pengingat opsional, transaksi berulang, rentang laporan khusus, PWA, dan berbagi split bill terproteksi. Fitur ini bukan syarat untuk merilis versi awal yang aman.

### Gerbang rilis

- Dukungan dan kebijakan aktif; persetujuan pengiriman AI tersedia; secret yang pernah terungkap sudah dirotasi.
- Konfigurasi produksi OAuth/callback, database, storage, Edge, dan Vercel diverifikasi untuk lingkungan rilis yang sama.
- Backup/restore serta jadwal retensi produksi diuji; error/crash dapat ditelusuri tanpa merekam data finansial pribadi atau token.
- CI lulus pada commit rilis; uji iPhone aktual selesai; versi web dan aplikasi terpasang sesuai sumber yang diuji.
- Inventaris data, dokumen privasi, manifest, dan disclosure distribusi selaras. Audit kode ini tidak menggantikan pemeriksaan dashboard atau review distribusi.

## Referensi kode

- `apps/web/src/components/Privacy.vue`: disclosure, dukungan kondisional, dan teks kata sandi lama.
- `apps/web/src/components/Auth.vue`, `apps/web/src/App.vue`: akses publik dan rute saat keluar akun.
- `apps/ios/DanarapiApp/UI/SettingsView.swift`, `apps/ios/DanarapiApp/UI/AuthViews.swift`: pengaturan, disclosure, dan login.
- `apps/ios/DanarapiApp/PrivacyInfo.xcprivacy`: manifest, bukan salinan kebijakan publik.
- `apps/ios/DanarapiApp/Domain/MonthPeriod.swift`, `apps/web/src/store.ts`: kebijakan zona waktu.
- `apps/ios/DanarapiApp/UI/ReportsView.swift`, `apps/web/src/components/Reports.vue`: periode dan status laporan.
- `apps/web/src/remote.ts`: pagination snapshot dan ketergantungan jaringan.
- `supabase/functions/review-retention/index.ts`, `.github/workflows/ci.yml`: retensi dan pipeline tes.
