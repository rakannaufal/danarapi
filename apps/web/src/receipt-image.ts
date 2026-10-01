export async function compressReceiptImage(file: File): Promise<{ mimeType: string; data: string; preview: Blob }> {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > 20 * 1024 * 1024) throw new Error('Pilih gambar JPEG, PNG atau WebP maksimal 20 MB.');
  let bitmap: ImageBitmap;
  try { bitmap = await createImageBitmap(file); } catch { throw new Error('Foto tidak dapat dibaca. Pilih gambar lain atau isi manual.'); }
  try {
    if (bitmap.width * bitmap.height > 40000000) throw new Error('Resolusi foto terlalu besar. Pilih gambar lebih kecil.');
    let scale = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height));
    for (let attempt = 0; attempt < 5; attempt++) {
      const canvas = document.createElement('canvas'); canvas.width = Math.max(1, Math.round(bitmap.width * scale)); canvas.height = Math.max(1, Math.round(bitmap.height * scale));
      const context = canvas.getContext('2d'); if (!context) throw new Error('Gambar tidak dapat diproses.');
      context.fillStyle = '#ffffff'; context.fillRect(0, 0, canvas.width, canvas.height); context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise<Blob>((resolve, reject) => canvas.toBlob(value => value ? resolve(value) : reject(new Error('Gambar tidak dapat dikompres.')), 'image/jpeg', .8 - attempt * .08));
      if (blob.size <= 1300000) {
        const data = await new Promise<string>((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(String(reader.result).split(',')[1]!); reader.onerror = () => reject(new Error('Gambar tidak terbaca.')); reader.readAsDataURL(blob); });
        return { mimeType: 'image/jpeg', data, preview: blob };
      }
      scale *= .8;
    }
    throw new Error('Foto masih terlalu besar. Potong area di luar struk lalu coba lagi.');
  } finally { bitmap.close(); }
}
