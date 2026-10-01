# ADR 0001: Ledger Server, Bigint, dan Kontrak V1

Status: diterima untuk Fase 0.

Keputusan: PostgreSQL RPC menjadi sumber kebenaran. Rupiah disimpan `bigint`, dibatasi Rp999.999.999.999, dan dikirim sebagai string desimal. Source row mempertahankan makna produk; `ledger_entries` menyimpan efek kas, pendapatan/pengeluaran pribadi, piutang, dan utang. Mutasi memakai receipt UUID atomik.

Alasan: float tidak aman untuk uang; perhitungan terpisah Swift/TypeScript berisiko berbeda; receipt di transaksi yang sama mencegah retry menggandakan efek.

Konsekuensi: UI tidak boleh menulis tabel finansial langsung. Perubahan kontrak harus additive. Fixture emas wajib lulus di server dan dua bahasa.

