# Aset dan palet Danarapi

## Pemetaan

| Sumber | Penggunaan |
| --- | --- |
| `logo.png` | Logo login/sidebar, favicon web, logo startup/layar privasi, dan ikon aplikasi iOS |
| `danarapi_text.png` | Nama bergambar pada login/sidebar web dan login/startup iOS |
| `background.png` | Latar login dan onboarding dengan varian terang/gelap |
| `onboarding_1.png` | Panduan scan struk menjadi catatan |
| `onboarding_2.png` | Panduan anggaran/target dan ilustrasi login desktop |
| `onboarding_3.png` | Panduan split bill |

File sumber dalam `danarapi_assets` tidak diubah. `scripts/generate-brand-assets.py` memotong ruang transparan, menjaga rasio, menyiapkan varian gelap, menghasilkan WebP web dan PNG katalog iOS. Ikon aplikasi memakai kanvas buram 1024 × 1024. Google tetap memakai logo sign-in resmi, bukan logo aplikasi.

## Tema

`contracts/design-tokens.json` menjadi sumber palet web dan iOS. Mode terang memakai teal `#09746C`, mint `#BAF4DE`, peach `#FDCEB2`, dan kanvas `#FBFCFB`. Mode gelap memakai mint `#7BDDC2`, mint muda `#9DE4C0`, peach `#FDCBAC`, dan navy `#0A1624`.

Warna permukaan, border, teks, fokus, serta status diturunkan agar terbaca. Warna merah/kuning untuk kesalahan dan batas anggaran tetap dipertahankan; warna pastel bukan pengganti status.

Grafik web dan iOS memakai seri teal, mint, peach, serta warna turunan yang sama. Pemasukan dan pengeluaran punya warna tetap pada grafik perbandingan maupun diagram bulat; legenda mengikuti warna segmennya.

## Konten

Teks login dan tiga langkah onboarding berasal dari `welcome` dan `onboarding` dalam `contracts/product-content.json`, dipakai bersama web dan iOS. Tidak ada perubahan login, data transaksi, persetujuan AI, atau versi kebijakan.

## Pembaruan aset

Jalankan generator dengan Python yang menyediakan Pillow 13 atau lebih baru. Hasil pada `apps/web/public/brand/danarapi` dan `apps/ios/DanarapiApp/Assets.xcassets` diperlukan saat deployment/build. Pengujian pekerjaan ini hanya dijalankan pada web; iOS tidak dibangun, diuji, atau diinstal.

## Lingkup verifikasi

Pengujian browser memakai server lokal terpisah pada port 5190, data Demo, dan respons layanan tiruan. Pengujian ini tidak memverifikasi login Google produksi atau ekstraksi AI terhadap layanan nyata. Server pengembangan pengguna pada port 5173 tidak diubah.

Pemeriksaan visual mencakup login, beranda, dan tiga halaman onboarding dalam tema terang/gelap, lebar 320/390/1440 px, serta teks 200%. Logo dan ilustrasi mempertahankan rasio; gambar dekoratif tidak menambah bacaan pembaca layar. Tombol utama onboarding menerima fokus awal, navigasi kembali tetap tersedia, dan gerakan mengikuti preferensi perangkat.

### Hasil 2 Oktober 2026

- `npm run check:web`: lint, pemeriksaan tipe, 97 unit test, dan build produksi berhasil.
- Regresi lengkap Chromium/WebKit: 156 dari 158 berhasil. Berkas konten dan tes berubah saat suite berjalan: satu onboarding mengalami reload ke login, satu judul tes tidak lagi ditemukan oleh worker.
- Onboarding WebKit gelap desktop berhasil pada dua pengulangan terpisah. Setelah perubahan berkas selesai, seluruh 22 tes branding dan halaman produk dijalankan ulang pada Chromium/WebKit dan berhasil. Suite lengkap tidak dijalankan ulang setelah perubahan tersebut.
- Pemeriksaan JSON, pola secret, dan `git diff --check` berhasil.
- Build masih menampilkan peringatan ukuran chunk utama di atas 500 kB, bukan kegagalan build.
- Tidak ada build, simulator, pengujian perangkat, atau instalasi iOS; perubahan native perlu build berikutnya untuk tampil pada aplikasi terpasang.

### Pembaruan navbar dan pemeriksaan sebelum push

- Navbar iOS memakai inset bawah dengan satu permukaan sampai area home indicator. Ikon kecil berada di dalam bar; tombol scan 60 px menonjol pada area transparan 18 px di atasnya. Label mengikuti baseline yang sama.
- Navbar web ponsel mengikuti pola yang sama: ikon kecil tanpa kapsul latar terpisah, tombol scan bulat 60 px, label sejajar, serta padding safe area.
- Seluruh 158 skenario Chromium/WebKit berhasil setelah pembaruan navbar. Sebanyak 79 skenario Firefox tidak bisa dimulai pada Mac ini: runtime menampilkan `Could not find profile folder`, termasuk saat memakai direktori sementara alternatif. Firefox tetap ada dalam CI; kegagalan runtime lokal tidak disembunyikan dengan menonaktifkan browser.
- Pemeriksaan sebelum push mencakup 97 unit test web, tes cloud, 27 tes edge, pemeriksaan tipe fungsi backend, dan pemeriksaan secret.
- Judul onboarding dalam XCTest diselaraskan dengan konten baru. Form menu split bill dipecah menjadi view lebih kecil untuk mengatasi kegagalan compiler pada CI sebelumnya; iOS tidak diuji lokal.
