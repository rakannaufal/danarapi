// Shared presentation data; fixed ledger fixtures remain reproducible.
const recurring = [
  [1, 'income', '8500000', 'bank', 'salary', 'Gaji bulanan', 'Gaji bersih setelah potongan'],
  [1, 'expense', '1800000', 'bank', 'household', 'Sewa kamar', 'Sewa bulanan termasuk air'],
  [1, 'expense', '1500000', 'bank', 'feature-goal', 'Tabungan laptop', 'Alokasi ke tabungan target', 'demo-goal'],
  [1, 'expense', '1000000', 'bank', 'feature-goal', 'Dana darurat', 'Alokasi dana darurat', 'demo-emergency'],
  [3, 'expense', '185000', 'bank', 'bills', 'Internet rumah', 'Paket internet bulanan'],
  [4, 'expense', '245000', 'bank', 'household', 'Pasar Lokal', 'Beras, telur, sayur, dan kebutuhan dapur'],
  [5, 'expense', '99000', 'wallet', 'bills', 'Paket data', 'Paket data ponsel 30 hari'],
  [7, 'expense', '65000', 'wallet', 'entertainment', 'Bioskop akhir pekan', 'Satu tiket bioskop'],
  [10, 'expense', '85000', 'bank', 'health', 'Apotek Sehat', 'Vitamin dan kebutuhan kesehatan'],
  [12, 'income', '1250000', 'bank', 'freelance', 'Proyek desain', 'Pelunasan desain katalog UMKM'],
  [14, 'expense', '219000', 'bank', 'household', 'Pasar Lokal', 'Belanja kebutuhan dua minggu'],
  [18, 'expense', '129000', 'bank', 'shopping', 'Toko Buku', 'Dua buku untuk belajar'],
  [20, 'expense', '300000', 'bank', 'feature-goal', 'Tabungan liburan', 'Alokasi liburan keluarga', 'demo-holiday'],
  [22, 'expense', '120000', 'bank', 'bills', 'Token listrik', 'Isi token listrik kamar'],
  [26, 'expense', '45000', 'wallet', 'entertainment', 'Langganan musik', 'Paket individu bulanan'],
  [28, 'expense', '189000', 'bank', 'household', 'Pasar Lokal', 'Kebutuhan dapur akhir bulan'],
];
for (let day = 1; day <= 28; day++) {
  recurring.push([day, 'expense', String([22000, 28000, 25000, 32000][(day - 1) % 4]), day % 2 ? 'cash' : 'wallet', 'food', day % 3 ? 'Warung Pagi' : 'Kedai Sore', day % 3 ? 'Makan siang' : 'Makan malam']);
  if (day % 7 !== 0 && day % 7 !== 6) recurring.push([day, 'expense', '14000', 'wallet', 'transport', 'Transportasi kota', 'Perjalanan pergi dan pulang kerja']);
}
export const showcase = {
  accounts: [
    { id: 'cash', name: 'Tunai', kind: 'cash', openingBalance: '1250000' },
    { id: 'bank', name: 'Bank utama', kind: 'bank', openingBalance: '5000000' },
    { id: 'wallet', name: 'Dompet digital', kind: 'ewallet', openingBalance: '750000' },
  ],
  categories: [
    ['food', 'Makan', 'expense'], ['transport', 'Transportasi', 'expense'],
    ['household', 'Rumah', 'expense'], ['bills', 'Tagihan', 'expense'],
    ['health', 'Kesehatan', 'expense'], ['shopping', 'Belanja', 'expense'],
    ['entertainment', 'Hiburan', 'expense'], ['salary', 'Gaji', 'income'],
    ['freelance', 'Freelance', 'income'],
  ].map(([id, name, kind]) => ({ id, name, kind })),
  recurring: recurring.map(([day, kind, amount, accountID, categoryID, merchant, note, goalID]) => ({ day, kind, amount, accountID, categoryID, merchant, note, ...(goalID ? { goalID } : {}) })),
  transfers: [
    { day: 1, fromAccountID: 'bank', toAccountID: 'cash', amount: '600000', note: 'Tarik tunai untuk makan sehari-hari' },
    { day: 1, fromAccountID: 'bank', toAccountID: 'wallet', amount: '1000000', note: 'Isi dompet digital untuk makan dan transportasi' },
  ],
  budgets: [
    ['food', '1200000'], ['transport', '450000'], ['household', '2600000'],
    ['bills', '500000'], ['entertainment', '200000'], ['shopping', '350000'], ['health', '200000'],
  ].map(([categoryID, limitAmount]) => ({ categoryID, limitAmount })),
  goals: [
    { id: 'demo-goal', name: 'Laptop impian', targetAmount: '15000000', monthsUntil: 6 },
    { id: 'demo-emergency', name: 'Dana darurat', targetAmount: '18000000', monthsUntil: 12 },
    { id: 'demo-holiday', name: 'Liburan keluarga', targetAmount: '6000000', monthsUntil: 8 },
  ],
  splitBills: [
    { id: 'demo-bill-self', title: 'Makan bersama', total: '240000', categoryID: 'food', monthOffset: 0, day: 1, selfPaid: true, accountID: 'bank', shareAmount: '80000', settlements: [{ memberIndex: 1, amount: '50000', day: 1 }] },
    { id: 'demo-bill-other', title: 'Tiket pameran seni', total: '180000', categoryID: 'entertainment', monthOffset: -1, day: 28, selfPaid: false, accountID: 'bank', shareAmount: '60000', settlements: [] },
    { id: 'demo-bill-settled', title: 'Makan siang tim', total: '150000', categoryID: 'food', monthOffset: -1, day: 24, selfPaid: true, accountID: 'bank', shareAmount: '50000', settlements: [{ memberIndex: 1, amount: '50000', day: 25 }, { memberIndex: 2, amount: '50000', day: 26 }] },
  ],
  reviews: [
    { id: 'review-qris', source: 'qris', merchant: 'Kedai Sore', amount: '48000', daysAgo: 0, note: 'Pembayaran QRIS makan dan minum. Periksa sebelum disimpan.' },
    { id: 'review-text', source: 'pasted_text', merchant: 'Pasar Lokal', amount: '156000', daysAgo: 1, note: 'Belanja mingguan\nBeras 75.000\nTelur 31.000\nSayur 50.000\nTotal 156.000' },
    { id: 'review-ambiguous', source: 'pasted_text', merchant: 'Warung Pagi', daysAgo: 2, note: 'Subtotal 50.000\nTotal 58.000\nTotal 60.000\nPeriksa nominal akhir pada struk.' },
  ],
  merchantRules: [
    ['warung', 'food'], ['kedai', 'food'], ['pasar lokal', 'household'],
    ['transportasi kota', 'transport'], ['apotek', 'health'], ['toko buku', 'shopping'],
  ].map(([normalizedPattern, categoryID], index) => ({ id: `demo-rule-${index}`, matchType: 'contains', normalizedPattern, categoryID, priority: 10 + index })),
};
