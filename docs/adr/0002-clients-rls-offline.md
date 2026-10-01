# ADR 0002: Dua Klien Native/Web, RLS, dan Batas Offline

Status: diterima untuk Fase 0.

Keputusan: iOS tetap SwiftUI native; web tetap Vue 3. UI tidak dibagi. Keduanya berbagi DTO, error, fixture, dan token desain. RLS serta FK pemilik menjadi lapisan isolasi wajib. Split bill akun nyata tetap online pada R1; outbox split ditunda karena ketergantungan versi dan pelunasan.

Konsekuensi: Swift package Fase 0 hanya domain contract; Xcode app, Keychain, SwiftData/Data Protection, dan UI masuk fase berikutnya. Web Fase 0 hanya domain contract; Vue UI masuk Fase 2.

