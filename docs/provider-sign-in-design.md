# Tombol login Google

Redesain terfokus: login minimalis untuk pengguna aplikasi keuangan, mengacu pada tombol kapsul pada referensi pengguna. Struktur halaman, identitas Danarapi, bahasa Indonesia dan OAuth PKCE dipertahankan. Variasi 3/10, gerak 1/10, kepadatan 2/10.

- Web/iOS: latar putih, garis netral 1px, kapsul, tinggi minimal 56px, jarak 12px, teks di tengah dan lebar sejajar.
- Google: logo dari paket resmi Google Identity, tanpa recolor, gradient/logo tidak digambar ulang. Font Google Sans Medium disimpan lokal: web Latin WOFF2 sekitar 23KB; native subset label sekitar 22KB. Bukan font lengkap 4,7MB.
- Login dan konfirmasi akun hanya menggunakan Google pada web/iOS. Tombol Apple, pemilih provider saat penghapusan akun dan aset logo Apple web dihapus. Pemeriksaan kesiapan cloud tidak mensyaratkan provider Apple; akun/data pengguna tidak dihapus.
- Logo dekoratif tidak dibacakan ulang. Nama tombol tetap tersedia saat loading, spinner tidak menggeser posisi teks, seluruh tombol dikunci selama satu login berlangsung. Focus keyboard, reduced motion dan scaling teks iOS tetap tersedia.
- Seluruh aset berada di aplikasi, tanpa mengambil logo/font dari CDN pada runtime. Lisensi Google Sans ikut didistribusikan pada web dan bundle iOS.
- `--ui-testing-auth` tersedia hanya pada build Debug untuk inspeksi visual; tidak membaca/menghapus sesi Keychain atau mengautentikasi pengguna. Release tetap memakai alur normal.

Sumber aset/pedoman: Google Identity `https://developers.google.com/identity/branding-guidelines`, paket `https://developers.google.com/static/identity/images/signin-assets.zip`, Google Fonts Google Sans. Merek dipakai hanya pada tombol login penyedianya.

Pemeriksaan: mobile 320/375px dan desktop, terang/gelap, logo tidak terpotong, teks tidak meluber, hanya satu provider, kontras tombol putih/teks gelap, fokus keyboard, VoiceOver identifiers, aset/font native dan screenshot pada iPhone fisik. Perubahan visual tidak mengaktifkan provider Supabase yang masih nonaktif.

Verifikasi desain sebelumnya pada iPhone 13: 50 tes unit dan satu tes UI terang/gelap lolos, tanpa runtime warning. Screenshot menemukan resource Google tidak dirender oleh initializer SwiftUI berbasis nama; penggunaan UIImage eksplisit memperbaikinya. Tinggi CSS web yang tertimpa token global dan ruang teks layar 320px juga diperbaiki, bukan sekadar mengubah ekspektasi ukuran.

Verifikasi Google-only pada 1 Oktober 2026: 79 unit web, sepuluh tes Chromium/WebKit, tiga tes cloud operations dan 50 unit iPhone lolos. Typecheck, lint dan production build web lolos; warning existing chunk JavaScript di atas 500KB tetap ada. Tes browser mencakup provider nonaktif, network error, redirect PKCE mock, terang/gelap, lebar 320/375/1280px dan audit aksesibilitas. Tes UI Google-only iPhone belum berjalan karena sertifikat runner developer belum dipercaya perangkat; tidak ada simulator iOS tersedia. Bukan bukti login provider produksi berhasil.
