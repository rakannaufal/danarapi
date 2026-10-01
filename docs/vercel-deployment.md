# GitHub dan Vercel

Repository: `https://github.com/rakannaufal/danarapi`.

## Import web

1. Di Vercel, pilih **Add New → Project**, hubungkan akun GitHub dan import `rakannaufal/danarapi`.
2. Gunakan **Root Directory `./`**, bukan `apps/web`. Aplikasi memakai kontrak bersama di luar folder web; konfigurasi build tersedia pada `vercel.json` di root repository.
3. Gunakan **Framework Preset Vite** dan Node.js **22.x**. Konfigurasi repository menetapkan:

   | Pengaturan | Nilai |
   | --- | --- |
   | Install Command | `npm ci --prefix apps/web` |
   | Build Command | `npm run web:build` |
   | Output Directory | `apps/web/dist` |
   | Production Branch | `main` |

4. Pada Environment Variables, isi konfigurasi publik berikut untuk Production. Isi juga pada Preview hanya bila backend mengizinkan origin preview tersebut:

   ```text
   VITE_SUPABASE_URL=https://zoccosfjulasqxczhvfm.supabase.co
   VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_HFNe0r92MxPPmck_SxfvdA_dwVecyjx
   ```

   Nilai tersebut sudah tersedia sebagai default klien. Jika melakukan override, selalu isi URL dan key bersamaan. `VITE_SUPPORT_EMAIL` opsional: gunakan alamat dukungan yang benar-benar aktif.

5. Pilih **Deploy**. Catat domain produksi yang benar-benar diberikan Vercel; jangan menebak domain dari nama repository.

`.env`, `.env.*` selain template, key AI, service-role key, private key dan konfigurasi scan lokal tidak ikut repository. Jangan masukkan secret AI/admin pada environment berawalan `VITE_`; nilai ini menjadi bagian JavaScript publik. Web di Vercel hanya frontend. Database, autentikasi dan ekstraksi struk tetap berjalan di Supabase.

## Hubungkan domain produksi ke backend

1. Supabase **Authentication → URL Configuration**: isi **Site URL** dengan origin HTTPS produksi yang diberikan Vercel. Tambahkan URL callback aplikasi web yang digunakan ke **Redirect URLs**; pertahankan `id.danarapi.app://auth/callback` untuk iOS.
2. Pada secret Supabase Edge Functions, tambahkan origin HTTPS produksi tersebut ke **`ALLOWED_ORIGINS`**. Pertahankan origin lain yang masih dibutuhkan. Gunakan origin lengkap tanpa path atau trailing slash; jangan gunakan `*` untuk produksi.
3. Untuk preview, tambahkan setiap origin yang akan diuji secara eksplisit pada redirect allowlist dan CORS. Preview tidak otomatis menjadi origin yang diizinkan.
4. Callback provider Google di Google Cloud Console tetap `https://zoccosfjulasqxczhvfm.supabase.co/auth/v1/callback`, bukan domain Vercel.
5. Deploy migrations dan fungsi Supabase sesuai `docs/supabase-cloud-setup.md`. Hosting Vercel tidak menerapkan SQL, secret atau fungsi Supabase secara otomatis.

Tanpa langkah backend tersebut, halaman bisa terbuka tetapi login atau pemuatan data/scan tetap gagal. Jangan menganggap frontend berhasil build sebagai bukti backend produksi siap.

## Pemeriksaan sebelum rilis

```sh
npm ci --prefix apps/web
npm run check:web
npm run test:cloud
npm run check:json
npm run check:secrets
npm run cloud:check
```

Uji domain produksi: login Google, muat data akun, simpan satu transaksi, keluar/masuk kembali, scan struk dan koreksi hasil. Periksa `/privacy` dan `/hapus-akun` saat dibuka langsung. Periksa iPhone melalui seluler, tanpa bergantung pada Mac. Gunakan akun uji; jangan menjalankan seed/reset/tes database pada produksi.

## Perubahan berikutnya

Setelah proyek Vercel terhubung ke GitHub, commit yang di-push ke production branch diproses melalui integrasi Git Vercel. Secret lokal tetap disimpan di perangkat/server, bukan Git. Tidak perlu memasang aplikasi iOS pada Vercel; source iOS berada di repository yang sama tetapi tidak termasuk output web.

Referensi resmi: `https://vercel.com/docs/frameworks/frontend/vite`, `https://vercel.com/docs/project-configuration`, `https://supabase.com/docs/guides/auth/redirect-urls`.
