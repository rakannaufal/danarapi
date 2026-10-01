import { readFile, mkdir, writeFile } from 'node:fs/promises';
import QRCode from 'qrcode';

const fixture = JSON.parse(await readFile(new URL('../../../tests/fixtures/import-v1.json', import.meta.url), 'utf8'));
const directory = new URL('../public/demo/', import.meta.url);
await mkdir(directory, { recursive: true });
await writeFile(new URL('qris-sintetis.png', directory), await QRCode.toBuffer(fixture.qris[0].raw, { width: 600, margin: 4 }));
const lines = fixture.text[0].raw.split('\n').map(value => value.replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)'));
const content = `BT /F1 12 Tf 50 750 Td ${lines.map((line, index) => `${index ? '0 -20 Td ' : ''}(${line}) Tj`).join(' ')} ET`;
const objects = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>', '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>', '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>', `<< /Length ${Buffer.byteLength(content)} >>\nstream\n${content}\nendstream`];
let document = '%PDF-1.4\n';
const offsets = [];
for (const [index, object] of objects.entries()) {
  offsets.push(Buffer.byteLength(document));
  document += `${index + 1} 0 obj\n${object}\nendobj\n`;
}
const xref = Buffer.byteLength(document);
document += `xref\n0 6\n0000000000 65535 f \n${offsets.map(offset => String(offset).padStart(10, '0') + ' 00000 n \n').join('')}trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
await writeFile(new URL('bukti-teks.pdf', directory), document);
