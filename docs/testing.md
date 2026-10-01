# Strategi Uji

| Lapisan | Pemeriksaan | Perintah |
| --- | --- | --- |
| Kontrak JSON | file valid, 200 transaksi demo, nominal string | `npm run check:json` |
| TypeScript | nominal, sama rata, largest remainder | `npm run test:contracts` |
| Swift | fixture yang sama, nominal, pembulatan | `swift test --package-path apps/ios` |
| Aplikasi iOS | domain, parser, Demo ledger, outbox, ekspor | `xcodebuild -project apps/ios/Danarapi.xcodeproj -scheme Danarapi -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test` |
| Migrasi | tabel, domain, view, RPC, bucket privat | `supabase test db` |
| RLS | baca/tulis dua identitas dan perubahan owner | `supabase test db` |
| Ledger | retry, saldo, split, pelunasan, overpay, write-off | `supabase test db` |
| Konkurensi | dua koneksi membayar Rp30.000 pada sisa Rp50.000; tepat satu sukses | `sh tests/database/concurrency.sh` |
| Edge Function | type-check tanpa koneksi eksternal | `deno check supabase/functions/ledger/index.ts supabase/functions/ios-data/index.ts supabase/functions/export-data/index.ts` |
| Secret | pola service-role JWT/private key | `npm run check:secrets` |

CI Linux menjalankan kontrak, Deno, Supabase/pgTAP, dan konkurensi. CI macOS menjalankan Swift package, build aplikasi Simulator, XCTest, serta UI test. Gitleaks memindai riwayat Git. Uji database dan perangkat tidak boleh ditandai lulus dari inspeksi statis.

Checklist dan status perangkat ada di `docs/ios-r1-testing.md`.
