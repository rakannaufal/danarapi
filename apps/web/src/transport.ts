export function transportError(cause: unknown): Error {
  if (cause instanceof Error && cause.name === 'AbortError') return new Error('Permintaan dibatalkan.');
  if (cause instanceof Error && cause.name === 'TimeoutError') return new Error('Layanan cloud terlalu lama merespons. Muat ulang sebelum mencoba menyimpan lagi.');
  if (cause instanceof TypeError) return new Error('Tidak dapat terhubung ke layanan cloud. Periksa koneksi; jika berlanjut, hubungi pengelola aplikasi.');
  return cause instanceof Error ? cause : new Error('Layanan cloud belum dapat dihubungi.');
}
