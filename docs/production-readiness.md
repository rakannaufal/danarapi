# Status kesiapan produksi

Diperbarui: 2 Oktober 2026, Asia/Jakarta.

**Status: verifikasi otomatis utama lolos; belum siap dinyatakan produksi.** Web, backend, database lokal, kontrak dan build diverifikasi pada 2 Oktober 2026. Perbaikan fokus nominal dan kategori anggaran masing-masing lolos tiga pengulangan; suite iPhone lengkap terakhir lolos 60 unit dan 15 UI. Build Release terbaru terpasang dan dibuka kembali pada iPhone tanpa argumen tes/demo. Firefox masih terblokir saat peluncuran. Hasil di bawah tidak membuktikan login Google pengguna, foto struk nyata, atau jaringan seluler.

## Implementasi dalam sumber

- Tentang, privasi, syarat, instruksi hapus akun, FAQ, kontak, laporan masalah privat dan persetujuan/pencabutan AI untuk web/iOS. Halaman status layanan dihapus dari kedua platform. Konten bersama memakai versi `2026-10-02`.
- Zona waktu akun, periode laporan, grafik alokasi dan perbandingan, kas per akun, ekspor periode, riwayat target/anggaran berpaginasi dan penyalinan anggaran tanpa mengubah saldo.
- Perlindungan pergantian akun selama permintaan asinkron, status pemuatan/kegagalan dan pemulihan data offline iOS.
- Dashboard iOS dipublikasikan sebelum pengayaan laporan bulanan. Kegagalan laporan tidak menyembunyikan draft atau memblokir beranda; nilai yang belum dimuat ditampilkan sebagai tanda kosong, bukan Rp0. Tombol muat ulang tersedia. Respons pemuatan yang lebih lama tidak mengganti hasil permintaan terbaru.
- Draft hasil impor memakai UUID lowercase. Pembukaan dan pembacaan ulang menerima UUID uppercase/lowercase tanpa mengubah identitas ID demo yang bukan UUID.
- Setelah penyimpanan draft diakui repository, iOS memasukkannya ke snapshot dan cache akun sebelum pemuatan ulang dashboard/laporan. Kegagalan refresh tidak menghilangkan draft; draft yang dikembalikan server tetap diutamakan. Jika akun berubah atau penyimpanan gagal, draft tidak dipublikasikan ke akun lain.
- Ketukan di luar input menutup keyboard iOS pada halaman dan sheet. Gesture tidak membatalkan ketukan tombol, tidak memblokir scroll dan melewati ketukan pada input. Listener dibersihkan ketika view dilepas.
- Web memakai pointer event di luar input untuk melepas fokus. Pergantian input, label, select dan contenteditable mempertahankan perilaku normal; listener dilepas ketika aplikasi dilepas.
- Tes regresi identitas UUID, publikasi/cache draft, pelepasan gesture keyboard dan interaksi form web sudah dijalankan. Tes keyboard iPhone memakai pengulangan terpisah tanpa menyembunyikan kegagalan dengan retry otomatis.

## Bukti pengujian terbaru

Log disimpan sementara di `/tmp`; tidak menjamin artefak tersedia setelah pembersihan sistem. Semua akun/data smoke adalah sintetis.

| Cakupan | Hasil pada 2 Oktober 2026 |
| --- | --- |
| Unit web, lint, typecheck, build | 90 tes lolos; lint, typecheck dan build berhasil, `/tmp/danarapi-validation-20261002-web.log` |
| Chromium/WebKit | 122 lolos, termasuk 4 tes keyboard, `/tmp/danarapi-validation-20261002-e2e.log` |
| Edge Functions | 27 lolos, `/tmp/danarapi-validation-20261002-contracts.log` |
| Operasi cloud | 6 lolos, `/tmp/danarapi-validation-20261002-contracts.log` |
| Paket kontrak Swift | 20 lolos, `/tmp/danarapi-validation-20261002-swift-package.log` |
| Database lokal | Seluruh 20 migrasi, RLS, ledger, konkurensi serta backup/restore sintetis lolos, `/tmp/danarapi-validation-20261002-database.log` |
| Paritas ekspor/zona waktu | 6 CSV pada 3 implementasi dan 12 batas periode serta Swift golden lolos, `/tmp/danarapi-validation-20261002-contracts.log` |
| Unit iPhone | 60 lolos pada iPhone 13 fisik, `/tmp/danarapi-validation-20261002-ios-verified-full.log` |
| UI iPhone | 15 dari 15 lolos dalam suite lengkap terakhir, `/tmp/danarapi-validation-20261002-ios-verified-full.log`. Anggaran dan keyboard transaksi juga masing-masing lolos tiga pengulangan tanpa retry otomatis, `/tmp/danarapi-validation-20261002-ios-focus-stability-final.log`. |
| Cloud nyata | Auth akun sintetis, consent, zona waktu, support, transaksi/idempotensi, saldo, target, anggaran, laporan, konflik edit, pagination dan ZIP ekspor lolos; akun uji dibersihkan, `/tmp/danarapi-validation-20261002-cloud.log` |
| Scan AI cloud | Panggilan AI nyata pada struk sintetis menghasilkan total Rp 23.000 dan qty 2, `/tmp/danarapi-validation-20261002-cloud.log`. Bukan bukti paritas foto pengguna pada web/iPhone. |
| Release iOS | Build terbaru berhasil setelah perbaikan perpindahan fokus; pemeriksaan boolean membuktikan URL cloud HTTPS, public key tersedia dan pairing Mac kosong, `/tmp/danarapi-validation-20261002-ios-release-verified.log`. Build ini terpasang dan diluncurkan pada iPhone tanpa mode tes/demo melalui `devicectl`. Ini bukan bukti login atau scan pengguna pada Release. |
| Pemeriksaan sumber | `git diff --check` dan `npm run check:secrets` lolos. Pemeriksaan secret ini mencari pola service-role JWT/private key; Gitleaks tidak dijalankan dan rotasi key penyedia tetap perlu dikonfirmasi. |

Firefox tetap gagal sebelum aplikasi dibuka: `Could not find profile folder`. Percobaan terbaru berhenti pada kegagalan peluncuran pertama, `/tmp/danarapi-validation-20261002-firefox.log`. Ini kendala lingkungan browser, bukan kelulusan atau kegagalan perilaku aplikasi. Chromium/WebKit bukan pengganti verifikasi Firefox, Safari asli atau VoiceOver. Build web memiliki warning ukuran chunk; build iOS memiliki warning metadata AppIntents yang dilewati karena framework tersebut tidak digunakan.

## Koreksi selama pengujian

- Tes pemilihan pemesan awal mengetuk tengah baris switch, bukan kontrol switch. Target sentuhan diarahkan ke switch; tes sekarang menunggu nilai aktif sebelum membandingkan pembayaran. Hasil iPhone untuk contoh menu bersama sama dengan web: Saya Rp 55.585, Ani Rp 55.583, Budi Rp 38.332.
- Gesture keyboard diperketat: hanya memproses ketukan saat ada responder, melewati area input termasuk wrapper SwiftUI, lalu menutup responder lama setelah event selesai apabila fokus belum berganti. Ketukan pada input baru tidak boleh dibatalkan.
- Input nominal mengikat `FocusState` ke kontrol melalui `.focused`; ketukan kartu nominal juga memindahkan fokus. Perbaikan ini lolos tiga pengulangan berurutan, `/tmp/danarapi-validation-20261002-ios-focus-binding.log`, lalu lolos dalam suite lengkap berikutnya.
- Anggaran memakai satu status fokus untuk limit dan kategori. Callback `UITextField` yang mengakhiri edit tidak lagi mengosongkan fokus secara sinkron ketika input berikutnya sedang dibuka: pembaruan ditunda hingga event selesai dan hanya dijalankan jika kontrol lama belum aktif kembali serta ID fokus masih sama. Kegagalan juga terjadi ketika gesture penutup keyboard dilepas dalam percobaan diagnostik; gesture tersebut tetap dipasang dalam sumber akhir.
- Harness scroll memperhitungkan seluruh bingkai kontrol, batas navbar/keyboard dan margin berbeda saat keyboard tertutup, bukan hanya `isHittable` atau titik tengah. Tes menunggu keyboard muncul sebelum mengukur batas. Kategori disentuh pada lokasi yang terlihat; nilai input diperiksa persis dan sheet harus tertutup setelah penyimpanan.
- Perbaikan batas scroll atau fokus bersama saja belum menyelesaikan kegagalan: `/tmp/danarapi-validation-20261002-ios-budget-stability.log` dan `/tmp/danarapi-validation-20261002-ios-shared-focus.log` tetap mencatat kegagalan. Setelah perbaikan callback dan margin harness, enam pengulangan terfokus lolos, `/tmp/danarapi-validation-20261002-ios-focus-stability-final.log`.
- Run lengkap `/tmp/danarapi-validation-20261002-ios-complete.log` juga mencatat kegagalan nominal/navigasi, perpindahan ke aplikasi lain dan putusnya komunikasi proses perangkat. Run berikutnya, `/tmp/danarapi-validation-20261002-ios-clean-full.log`, lolos 13 dari 15 UI; hierarki saat anggaran gagal menunjukkan alert sistem `Undo Typing`, dan navigasi beranda juga gagal. Kegagalan tersebut tidak dihapus atau diperlakukan sebagai kelulusan.
- Harness menetapkan orientasi portrait, memilih tombol kembali dari navbar halaman yang tepat dan menunggu beranda sebelum lanjut. Hanya alert sistem `Undo Typing` dengan tombol `Cancel` yang boleh ditutup otomatis; alert aplikasi dan pengaturan perangkat tidak diubah. Suite lengkap setelah penyesuaian ini lolos 60 unit dan 15 UI, `/tmp/danarapi-validation-20261002-ios-verified-full.log`.
- Hasil awal yang gagal tetap tercatat; kelulusan pengulangan tunggal tidak dianggap cukup untuk stabilitas.

## Database dan deployment

### Perbaikan login Google, 2 Oktober 2026

- Web dan iOS meminta `prompt=select_account`. Pemeriksaan redirect read-only pada Supabase produksi menghasilkan HTTP 302 menuju Google dengan pilihan akun dan callback cloud yang sesuai. Ini bukan bukti penyelesaian login pengguna.
- Status login iOS dimiliki model aplikasi, bukan view yang dapat dibuat ulang. Refresh dashboard ditahan selama login/reauthentication; kegagalan refresh lama diabaikan setelah generasi pemuatan berubah. Data offline dan pemeriksaan pemilik akun dipertahankan.
- Browser OAuth memiliki timeout 120 detik, pembatalan eksplisit, penanganan gagal membuka browser dan perlindungan callback terlambat. Pembatalan saat pertukaran token tidak menampilkan kesalahan sesi generik. Tombol `Batalkan login` tersedia ketika login berlangsung.
- Pengujian terbaru lolos 64 unit iOS, termasuk empat regresi lifecycle OAuth, dan satu UI login terang/gelap pada iPhone: `/tmp/danarapi-validation-20261002-ios-auth-repair-final.log`. Seluruh 15 UI sebelumnya tidak diulang untuk patch ini.
- Delapan tes login Chromium/WebKit lolos: `/tmp/danarapi-validation-20261002-e2e-auth-repair.log`. Lint dan build web lolos: `/tmp/danarapi-validation-20261002-web-auth-repair.log`. Build Release iOS lolos: `/tmp/danarapi-validation-20261002-ios-auth-release.log`.
- Konfigurasi Release memakai HTTPS cloud, public client key tersedia dan seluruh pairing scan LAN kosong. Login Google nyata sampai masuk beranda serta fetch/save setelah login tetap membutuhkan verifikasi akun pengguna. Perubahan login web dalam sumber belum dideploy.
- Release perbaikan login sudah terpasang dan dibuka kembali pada iPhone tersambung, tanpa argumen tes/demo; instalasi mempertahankan data aplikasi dan Keychain.

1. Supabase `zoccosfjulasqxczhvfm` sudah memiliki migrasi 1–20, terakhir `202610020020_product_access_hardening.sql`. Jangan menjalankan ulang migrasi awal, seed, reset atau SQL pengujian di produksi.
2. Pembaruan fungsi `ios-data`, `export-data` dan `product-info` sudah diterapkan. `receipt-scan` yang terdeploy belum memakai penegakan consent terbaru dalam sumber. Urutkan rollout klien kompatibel dahulu, kemudian fungsi scan.
3. Web produksi `https://danarapi.vercel.app` masih memakai deployment sebelumnya. Preview `https://danarapi-f9aqfxsom-rakannaufals-projects.vercel.app` berhasil dibuat, tetapi mendahului perbaikan draft/keyboard dan belum dipromosikan.
4. Tidak ada commit/push untuk perubahan sesi ini. Deployment berbasis Git berikutnya dapat mengganti hasil deployment CLI jika sumber belum diselaraskan.
5. `SUPPORT_EMAIL` belum diatur. Halaman kontak tidak mengarang alamat pemilik; kanal dukungan publik harus disiapkan sebelum rilis.

## Gerbang rilis tersisa

Lakukan berurutan; simpan hasil per platform dan jangan mengisi status lulus tanpa bukti:

1. Lengkapi injeksi kegagalan dan pengujian integrasi draft: refresh dashboard gagal, laporan gagal, save gagal dan pergantian akun selama unggah. Tes identitas UUID beda casing, cache/publikasi draft segera serta impor teks ke tinjauan sudah lolos; jangan menganggap seluruh cabang kegagalan asinkron ikut terverifikasi.
2. Lengkapi pemeriksaan manual keyboard di transaksi, target, anggaran, tinjauan dan split bill: pemilihan teks, scroll, tombol simpan dan sheet. Ketukan luar/pergantian input transaksi, kategori anggaran, form target dan focus trap web sudah memiliki bukti otomatis; tidak menggantikan seluruh pemeriksaan manual perangkat.
3. Selesaikan kendala peluncuran Firefox dan uji Safari asli. Unit, kontrak, database lokal, Chromium/WebKit, suite iPhone lengkap dan Release terbaru sudah lolos; ulangi cakupan terdampak apabila sumber berubah sebelum rollout.
4. Uji login Google nyata web/iOS: callback, batal, sesi kedaluwarsa, logout, login ulang, fetch dan penyimpanan data. Jangan mengambil token akun dari log perangkat.
5. Gunakan struk identik pada web/iPhone. Bandingkan menu, qty, harga satuan, subtotal, service, pajak, diskon, rounding dan total. Draft harus langsung tersedia tanpa keluar dari layar scan.
6. Uji iPhone dengan seluler dan Wi-Fi berbeda saat Mac dimatikan. Pastikan cloud scan, login, sinkronisasi, input dan ekspor tidak memakai LAN/bridge pengembangan.
7. Uji dua klien nyata yang mengedit data sama, retry idempoten, konflik versi dan pergantian akun. Bukti konflik sintetis tidak menggantikan pengujian dua klien.
8. Verifikasi backup/restore produksi pada lingkungan terpisah, termasuk lampiran Storage, retensi, pemulihan izin dan prosedur pemulihan. Backup database lokal bukan bukti pemulihan layanan terkelola.
9. Tinjau VoiceOver, Dynamic Type, kontras, area sentuh, keyboard dan keadaan kosong/gagal pada perangkat. Tinjau kebijakan distribusi iOS untuk login Google-only tanpa menambahkan Apple kembali tanpa permintaan pengguna.
10. Siapkan kanal kontak publik, verifikasi rotasi key penyedia yang pernah dibagikan, konfigurasi retensi dan pemeriksaan hak akses. Jangan meletakkan key AI/service-role di klien, Git atau log.
11. Setelah semua gerbang lulus, deploy klien/fungsi kompatibel, verifikasi rute HTTPS, aset dan header, lakukan smoke pascadeploy yang diizinkan, lalu catat versi rilis dan deployment sebelumnya untuk rollback.

Status siap produksi hanya boleh ditetapkan setelah verifikasi dan rollout selesai. Dokumen ini mencatat pekerjaan dan batas bukti; bukan sertifikasi rilis.
