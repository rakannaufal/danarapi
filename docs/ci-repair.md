# Perbaikan CI

Kegagalan awal pada commit `fbcef2b` diperiksa dari log GitHub Actions run `36877614565`, bukan dari ikon status saja.

| Job | Penyebab | Perbaikan |
| --- | --- | --- |
| iOS app dan contracts | Compiler runner gagal memeriksa ekspresi validasi persentase yang terlalu kompleks | Helper validasi Double dengan langkah terpisah; aturan finite, rentang 0–100 dan dua desimal tetap sama |
| Database | Signature RPC belum memasukkan goal; fixture RLS belum memperhitungkan akun Tunai onboarding; overload throws_ok salah; plan ledger salah | Signature/fixture diperbarui, SQLSTATE tetap diverifikasi melalui overload empat argumen, seluruh assertion dijalankan |
| Database opening balance | Test mengharapkan trigger berjalan sebelum pemeriksaan izin tabel authenticated | Uji penolakan raw write untuk authenticated dan uji trigger immutable melalui role privileged dipisahkan |
| Secret scan | Tujuh penulisan publishable key publik dianggap generic API secret | Allowlist satu nilai key publik yang persis sama; default detector tetap aktif, tanpa mengecualikan file/riwayat/secret lain |
| Export parity | Kompilasi Models.swift belum menyertakan MonthPeriod.swift | Dependency dimasukkan dalam harness ekspor, bukan menghapus pemeriksaan kesamaan ekspor |
| Web | Judul laporan menolak menyusut pada teks 200%; label Google terlalu sempit pada 320px | Layout judul fleksibel dan wrapping, tambahan ruang tombol kecil, tes menunggu font resmi siap sebelum mengukur |

Regresi mencakup rate NaN/infinity/negatif/di atas 100/lebih dari dua desimal dan rate valid di batas. Pengujian keamanan memastikan allowlist tidak cocok dengan secret key atau nilai key yang berubah. Pengujian lokal Gitleaks juga menolak dua secret sintetis; tidak menggunakan credential aktif.

Verifikasi lokal: 20 kontrak Swift, 74 assertion pgTAP, migrations/RLS/saldo/konkurensi/backup-restore serta paritas ekspor web/server/Swift. pgTAP lokal menggunakan SQL resmi v1.3.4 di database disposable; runner Supabase tetap menjalankan `supabase test db` dengan extension sebenarnya. Tidak ada migrasi atau grant produksi yang diubah.

Build Simulator lokal tertahan ruang disk Mac, bukan diklaim lulus. Hasil seluruh job CI harus diperiksa pada commit perbaikan sebelum dinyatakan hijau; job yang masih berjalan belum dianggap berhasil.
