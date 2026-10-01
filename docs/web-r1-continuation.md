# Penutupan gerbang web R1 — lanjutan

Dokumen ini menggantikan daftar status web sebelumnya di `web-r1-verification.md`, bukan menyatakan semua gerbang rilis telah lulus. Bukti memakai data sintetis. Tidak ada deployment, perubahan akun nyata, commit, atau branch baru.

## Bagian yang dituntaskan

- **Lampiran catatan posted:** detail transaksi manual dan split bill menyediakan unggah JPEG/PNG/PDF dan pratinjau privat. Validasi MIME/signature, batas 5 MB, sanitasi metadata gambar, pemeriksaan pemilik sebelum Storage, serta kuota berlaku. Menambahkan lampiran tidak menjalankan parser ekstraksi atau membuat transaksi lain. Lampiran Demo dipindahkan dari review ke transaksi/bill saat konfirmasi/gabung/konversi. E2E memeriksa lampiran manual dan hasil impor setelah konfirmasi.
- **Fokus WebKit:** Tab/Shift+Tab di dialog sekarang berpindah eksplisit di antara kontrol aktif yang terlihat; tidak bergantung pada preferensi navigasi tombol Safari. Escape dan pengembalian fokus tetap diuji. Kegagalan ditemukan melalui perluasan lintas engine, bukan disembunyikan dengan menghapus assertion.
- **Kontrol WebKit:** inspeksi contact sheet menemukan select native mengabaikan tinggi/padding yang dipakai Chromium. `appearance: none`, tinggi minimum 48 px, serta chevron CSS bersama memperbaiki tampilan dan target sentuh; assertion kini memeriksa input/select/textarea, bukan tombol saja. Format bulan/tanggal native masih berbeda menurut engine/locale (misalnya `2026-09` dibanding label September); nilai ISO dan label tetap konsisten.
- **Paritas keenam CSV:** implementasi Swift, web, dan server kini memakai status `unsettled/partially_settled/settled`, pembayar Saya/nama lokal, kode kejadian write-off sama, sisa hanya untuk anggota berkewajiban, dan nominal negatif tetap numerik tanpa apostrof. Runner mengompilasi fungsi ekspor Swift nyata; server memakai fungsi ekspor gateway nyata. Perbandingan semantik mencakup 12 kombinasi bulan/zona waktu, pembayar teman dengan porsi tidak sama, reversal, write-off/pembebasan, record dihapus, formula, kutipan dan teks multiline. Ini paritas fungsi/fixture, bukan bukti ZIP dengan objek Storage nyata atau E2E dua aplikasi berjalan.
- **Retensi:** migrasi `202610010010_review_retention.sql` dan fungsi `review-retention` menyediakan klaim batch service-role, bukti penerimaan kebijakan, penguncian draft kedaluwarsa, penghapusan objek sebelum metadata, verifikasi objek benar-benar tidak ada, retry fail-closed, serta endpoint bersecret khusus. Ditolak memenuhi syarat setelah 30 hari; pending 90 hari hanya setelah pemberitahuan tercatat dan tenggang tambahan 7 hari. Pending tanpa pemberitahuan tidak dibersihkan. UI privasi mencatat penerimaan kebijakan dengan waktu server; Demo tidak mengirim penerimaan. **Fungsi tidak diterapkan, tidak dijadwalkan terhadap produksi. Aktivasi penghapusan produksi memerlukan persetujuan eksplisit operator.**
- **Backup/restore DB sintetis:** migrasi membangun schema tujuan, dump data dipulihkan dengan trigger dimatikan hanya selama restore, lalu fingerprint akun/transaksi/ledger/overview dan tes retensi/RLS dibandingkan. Percobaan restore schema langsung menemukan masalah dummy view/domain PostgreSQL; schema-as-code + data-only restore mengatasinya. Ini bukan pemulihan objek Storage atau bukti kebijakan backup penyedia produksi.
- **Performa:** formatter `Intl.DateTimeFormat` sebelumnya dibangun setiap baris; laporan anggaran menghitung periode sama berulang. Formatter sekarang dicache terbatas per timezone, tanggal dihitung sekali per predicate, laporan anggaran dihitung sekali per bulan. Pada run sintetis 50.000 transaksi, derive turun dari 13.295 ms menjadi 221 ms; laporan dari 3.384 ms menjadi 102 ms; keenam CSV dari 10.259 ms menjadi 293 ms. Benchmark Node bukan SLA/browser/HTTP/ZIP. E2E tambahan menguji snapshot 50.000 baris dengan DOM daftar tetap 30 baris dan filter bekerja.
- **Palet bersama:** `product-update-planning.md` sudah menyatakan keputusan putih/navy/biru menggantikan warna lama yang terkait. Token v1.1 dipertahankan di kedua klien, bukan dikembalikan sepihak ke baseline mint. Keputusan tersebut sekarang ditautkan dari PRD; tidak lagi dilaporkan sebagai keputusan palet yang belum ditemukan.

## Bukti otomatis

Perintah dan output akhir berada di `apps/web/artifacts/verification/`:

| Pemeriksaan | Bukti |
| --- | --- |
| Lint, vue-tsc, 33/33 domain/fixture, Vite build lulus | `continuation-check.log` |
| 40/40 Chromium + WebKit lulus, termasuk lampiran dan dataset 50.000 | `continuation-e2e.log` |
| Firefox | `firefox-final.log`: browser gagal diluncurkan, bukan assertion aplikasi |
| 15/15 gateway mock dan retensi fail-closed lulus | `retention-edge.log` |
| Keempat fungsi Deno lulus check | `continuation-deno.log` |
| Enam CSV tiga implementasi, 12 jendela bulan/timezone lulus | `export-parity.log` |
| Sepuluh migrasi, seed, domain/RLS, konkurensi, backup/restore sintetis lulus | `continuation-postgres.log` |
| 4/4 kontrak Swift, fixture dan typecheck aplikasi/XCTest/UI test lulus | `continuation-swift.log` |
| Benchmark 10.000/50.000 | `performance.log` |
| JSON dan secret scan | `continuation-json.log`, `continuation-secrets.log` |

76 PNG final mencakup lima layar inti, ponsel/desktop terang/gelap, serta ponsel teks 200% pada Chromium dan WebKit. Manifest SHA-256 mencatat waktu capture per file dan fingerprint source. Dua belas contact sheet diperiksa setelah capture ulang. Tata letak, hierarki nominal, navigasi, tombol, scroll dialog dan keadaan terang/gelap dibandingkan; select WebKit yang terlalu kecil diperbaiki sebelum capture final. Nominal maksimum pada dialog tetap terbaca, layout 200% mereflow tanpa overflow dokumen; navigasi besar menggulir di dalam bar. Contact sheet dibuat ulang dari PNG, bukan memakai contact sheet lama. Axe, kontras pasangan surface, fokus, reduced motion dan reflow diuji. WebKit bukan Safari aplikasi/perangkat asli; teks 200% CSS bukan zoom browser native atau audit screen reader.

## Gerbang yang tidak dapat diklaim lulus

1. **Supabase nyata dan dua aplikasi hidup.** CLI, Docker CLI dan Colima sudah dipasang; dua percobaan VM/stack gagal karena disk kehabisan ruang. Log `supabase-start.log` mencatat kegagalan penulisan daemon saat penarikan image. Konfigurasi Docker uji tidak mengubah credential helper pengguna. VM dan disk container khusus percobaan telah dibuang untuk memulihkan ruang; tidak menghapus data pengguna lain. Diperlukan ruang tambahan atau staging Supabase yang diizinkan untuk akun sintetis. Auth kode/SMTP/recovery/refresh/429, HTTP Storage lintas pemilik, pgTAP, ZIP berobjek nyata, ekspor/hapus akun nyata, dan web+iOS terhadap backend sama tetap belum terverifikasi.
2. **Firefox native runner.** Setelah instalasi ulang dan percobaan direktori sementara alternatif, Firefox tetap berhenti dengan `Could not find profile folder` sebelum membuka aplikasi. Tidak mengganti hasil ini dengan klaim Firefox lulus. Konfigurasi/CI mencakup Firefox; perlu runner yang dapat meluncurkannya.
3. **Audit manusia/perangkat.** Safari asli, zoom browser, high contrast, VoiceOver/TalkBack, iPhone fisik G0/G1, serta 20 input cepat/10 split oleh manusia tanpa bantuan memerlukan perangkat/peserta. Regresi otomatis tidak menggantikan gerbang ini.
4. **Operasional produksi.** Retensi cleanup belum diaktifkan; jadwal destruktif produksi tidak dibuat tanpa persetujuan khusus. SMTP/anti-abuse produksi, backup seluruh stack beserta Storage, retensi cadangan sebenarnya, dan alamat dukungan masih memerlukan konfigurasi pemilik. `VITE_SUPPORT_EMAIL` menyediakan kanal UI setelah alamat nyata ditetapkan; tidak menggunakan alamat rekaan.
5. **Prefetch HTTP skala besar.** Benchmark domain dan DOM lulus tidak mengubah fakta bahwa akun nyata masih memprefetch snapshot lengkap. Latensi jaringan, memori ZIP dan dataset produksi tetap memerlukan benchmark backend nyata.

Tidak ada akses produksi yang digunakan, jadwal penghapusan produksi yang diaktifkan, atau klaim semua R1 selesai.
