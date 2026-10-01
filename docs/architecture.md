# Arsitektur Fase 0

```text
SwiftUI/iOS                    Vue/Web
     |                            |
     +------ kontrak JSON v1 -----+
                  |
          Supabase Auth/JWT
                  |
        Edge gateway / RPC publik
                  |
     PostgreSQL SECURITY DEFINER RPC
       |          |             |
   source row  ledger entry  mutation receipt
       |          |             |
       +--- RLS + FK pemilik ----+
                  |
        private Storage bucket
```

Server mengambil pemilik dari `auth.uid()`, bukan payload. RPC membentuk receipt idempotensi dan seluruh source row/ledger entry dalam satu transaksi. Kegagalan membatalkan receipt. Replay identik mengembalikan envelope lama beserta `request_id`; penggunaan UUID sama dengan payload berbeda ditolak.

## Proyeksi

`account_balances` menghitung saldo awal ditambah kaki kas aktif. `split_obligations` membentuk piutang ketika Saya membayar dan satu utang porsi Saya ketika teman membayar. `financial_overview` memisahkan saldo akun, piutang, utang, dan posisi bersih. `split_bill_summaries` menurunkan status dari nilai dibayar, dihapuskan, dan sisa.

## Batas klien

TypeScript dan Swift mengimplementasikan parsing nominal serta pembulatan split yang sama dari fixture emas. Mereka tidak menghitung saldo online secara otoritatif. Fase 0 tidak menyertakan UI produksi, Keychain, SwiftData/outbox, Vue routes, atau parser impor; modul tersebut masuk fase berikutnya dan tetap memakai kontrak v1 secara additive.

