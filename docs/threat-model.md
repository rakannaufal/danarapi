# Threat Model Fase 0

## Aset

Saldo, transaksi, identitas pengguna, nama peserta split bill, lampiran, token sesi, dan service-role key.

## Batas kepercayaan dan kontrol

- Klien tidak dipercaya menentukan `user_id`, saldo, status bill, atau sisa kewajiban.
- RLS membatasi semua tabel pemilik. FK komposit menolak relasi ke row pengguna lain walau UUID diketahui.
- RPC `SECURITY DEFINER` memakai `search_path` tetap, mengambil `auth.uid()`, dan hanya fungsi bernama yang diberikan ke `authenticated`.
- Tabel finansial tidak dapat dimutasi langsung oleh role klien. Trigger menjaga batas kewajiban walau jalur privileged salah pakai.
- Storage privat memakai folder pertama UUID pemilik, MIME allowlist, 5 MB/file; metadata aplikasi membatasi 200 file/100 MB.
- Error publik tidak memuat email, token, nama peserta, isi transaksi, atau payload mentah.
- Edge Function meneruskan JWT pengguna dan anon key. Service-role tidak digunakan pada gateway ledger.

## Risiko tersisa

- MIME sniff mendalam dan sanitasi EXIF belum diterapkan; masuk fase impor.
- Rate limit transaksi/hari belum memiliki infrastruktur konfigurasi; sebelum akun publik, tambahkan limiter server.
- Backup/restore, SMTP, CAPTCHA, staging, audit produksi, dan retensi cadangan memerlukan proyek Supabase nyata.
- Pengujian perangkat untuk Keychain/Data Protection/biometrik memerlukan implementasi iOS berikutnya dan iPhone nyata.

