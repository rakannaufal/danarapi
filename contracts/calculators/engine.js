/* Shared, offline calculation engine. iOS runs this same file in JavaScriptCore. */
(function (root) {
  'use strict';
  const SCALE = 1000000n, MAX_MONEY = 999999999999n, HUNDRED = 100n * SCALE;
  function fail(message) { throw new Error(message); }
  function decimal(value, label) {
    const text = String(value == null ? '' : value);
    if (!/^(0|[1-9][0-9]{0,11})(\.[0-9]{1,6})?$/.test(text)) fail(label + ': isi angka positif dengan maksimal enam desimal.');
    const parts = text.split('.');
    return BigInt(parts[0]) * SCALE + BigInt((parts[1] || '').padEnd(6, '0'));
  }
  function divide(n, d, mode) {
    if (d <= 0n) fail('Pembagi harus lebih dari nol.');
    const sign = n < 0n ? -1n : 1n, absolute = n < 0n ? -n : n;
    const base = absolute / d, rem = absolute % d;
    return sign * (base + (mode === 'ceil' ? (rem > 0n ? 1n : 0n) : (rem * 2n >= d ? 1n : 0n)));
  }
  function moneyValue(v) {
    const value = BigInt(v);
    if (value < -MAX_MONEY || value > MAX_MONEY) fail('Hasil melebihi batas Rp999.999.999.999. Perkecil nilai atau jangka waktu.');
    return value.toString();
  }
  function fixed(n, d, digits) {
    const scale = 10n ** BigInt(digits), value = divide(n * scale, d), negative = value < 0n;
    const text = (negative ? -value : value).toString().padStart(digits + 1, '0');
    return (negative ? '-' : '') + (digits ? text.slice(0, -digits) + '.' + text.slice(-digits).replace(/0+$/, '') : text).replace(/\.$/, '');
  }
  function gcd(a, b) { while (b) { const c = a % b; a = b; b = c; } return a; }
  function fraction(n, d) { const g = gcd(n < 0n ? -n : n, d); return { n: n / g, d: d / g }; }
  function fadd(a, b) { return fraction(a.n * b.d + b.n * a.d, a.d * b.d); }
  function fmul(a, b) { return fraction(a.n * b.n, a.d * b.d); }
  function fdiv(a, b) { if (!b.n) fail('Bagian pembagian tidak valid.'); return fraction(a.n * b.d, a.d * b.n); }
  const ZERO = fraction(0n, 1n), ONE = fraction(1n, 1n);
  function visible(field, values) {
    return !field.visible || Object.keys(field.visible).every(key => {
      const expected = field.visible[key]; return Array.isArray(expected) ? expected.includes(values[key]) : expected === values[key];
    });
  }
  function parse(definition, input) {
    const values = {};
    for (const field of definition.fields) values[field.key] = input[field.key] == null ? field.default : String(input[field.key]);
    const parsed = {};
    for (const field of definition.fields) {
      if (!visible(field, values)) { parsed[field.key] = ['money', 'decimal', 'integer', 'percent'].includes(field.kind) ? 0n : ''; continue; }
      const value = values[field.key];
      if (field.kind === 'toggle') { if (!['true', 'false'].includes(value)) fail(field.label + ': pilihan tidak valid.'); parsed[field.key] = value === 'true'; }
      else if (field.kind === 'choice') { if (!field.options.some(option => option.value === value)) fail(field.label + ': pilih opsi yang tersedia.'); parsed[field.key] = value; }
      else if (field.kind === 'date') {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(value)) || new Date(value).toISOString().slice(0, 10) !== value) fail(field.label + ': isi tanggal yang valid.');
        parsed[field.key] = value;
      } else {
        const number = decimal(value, field.label);
        if (['money', 'integer'].includes(field.kind) && number % SCALE !== 0n) fail(field.label + ': gunakan bilangan bulat.');
        const min = field.min == null ? 0n : decimal(field.min, field.label);
        const max = decimal(field.max || (field.kind === 'percent' ? '100' : field.kind === 'money' ? MAX_MONEY.toString() : '999999999999'), field.label);
        if (number < min || number > max) fail(field.label + ': angka di luar batas yang diperbolehkan.');
        parsed[field.key] = ['money', 'integer'].includes(field.kind) ? number / SCALE : number;
      }
    }
    return parsed;
  }
  function compute(definition, input) {
    const v = parse(definition, input), rows = [], warnings = [], steps = [], schedule = [];
    let headline = 'Hasil perhitungan', primaryAmount = null, primaryLabel = null, status = 'calculated';
    const m = (label, value, primary) => { const text = moneyValue(value); rows.push({ label, value: text, kind: 'money', unit: 'Rp' }); if (primary) { primaryAmount = text; primaryLabel = label; } };
    const num = (label, value, unit) => rows.push({ label, value: String(value), kind: 'number', unit: unit || '' });
    const txt = (label, value) => rows.push({ label, value: String(value), kind: 'text', unit: '' });
    const pct = (label, n, d) => rows.push({ label, value: fixed(n * 100n, d, 4), kind: 'percent', unit: '%' });
    const ratioMoney = (a, n, d, rounding) => divide(a * n, d, rounding);
    const percentage = (a, p, rounding) => ratioMoney(a, p, HUNDRED, rounding);
    const needPositive = (a, label) => { if (a <= 0n) fail(label + ' harus lebih dari nol.'); };
    const step = text => steps.push(text);
    const notice = text => warnings.push(text);
    const eligible = (conditions, message) => {
      if (conditions.some(condition => !condition)) { status = 'needs-confirmation'; headline = 'Syarat belum dikonfirmasi'; notice(message); return false; }
      return true;
    };
    switch (definition.id) {
      case 'discount': {
        const final = percentage(v.price, HUNDRED - v.discount);
        m('Harga setelah diskon', final, true); m('Penghematan', v.price - final);
        step('Harga awal x (1 - diskon / 100).'); break;
      }
      case 'stacked-discount': {
        let current = v.price;
        [v.first, v.second, v.third].forEach((discount, index) => { const next = percentage(current, HUNDRED - discount); m('Harga setelah diskon ' + (index + 1), next); current = next; });
        m('Harga akhir', current, true); m('Total penghematan', v.price - current);
        if (v.price) pct('Diskon efektif', v.price - current, v.price);
        step('Setiap tahap memakai harga setelah tahap sebelumnya, dengan pembulatan Rupiah per tahap.'); break;
      }
      case 'tax-tip': {
        const service = percentage(v.subtotal, v.service), tax = percentage(v.subtotal + (v.taxBase === 'with-service' ? service : 0n), v.tax);
        const tip = percentage(v.subtotal + (v.tipBase === 'total' ? service + tax : 0n), v.tip);
        m('Subtotal', v.subtotal); m('Service', service); m('Pajak', tax); m('Tip', tip); m('Total pembayaran', v.subtotal + service + tax + tip, true);
        step('Total = subtotal + service + pajak + tip; dasar pajak dan tip mengikuti pilihan.'); break;
      }
      case 'unit-price': {
        const a = v.priceA * SCALE * v.quantityB, b = v.priceB * SCALE * v.quantityA;
        num('Harga per satuan A', fixed(v.priceA * SCALE, v.quantityA, 6), 'Rp/satuan'); num('Harga per satuan B', fixed(v.priceB * SCALE, v.quantityB, 6), 'Rp/satuan');
        txt('Perbandingan', a === b ? 'Harga satuan sama' : a < b ? 'Produk A lebih murah per satuan' : 'Produk B lebih murah per satuan');
        if (a !== b && (a > b ? a : b) > 0n) pct('Selisih relatif terhadap harga yang lebih mahal', a > b ? a - b : b - a, a > b ? a : b);
        step('Harga produk dibagi isi; keputusan memakai nilai sebelum pembulatan tampilan.'); break;
      }
      case 'promo': {
        const offer = suffix => {
          const discounted = percentage(v['price' + suffix], HUNDRED - v['discount' + suffix]);
          let cashback = percentage(discounted, v['cashback' + suffix]);
          const cap = v['cap' + suffix]; if (cap && cashback > cap) cashback = cap;
          const paid = discounted + v['delivery' + suffix];
          m('Dibayar sekarang ' + suffix, paid); m('Cashback ' + suffix, cashback); m('Biaya efektif ' + suffix, paid - cashback);
          return paid - cashback;
        };
        const a = offer('A'), b = offer('B'); txt('Pilihan biaya efektif', a === b ? 'Kedua penawaran setara' : a < b ? 'Penawaran A' : 'Penawaran B'); m('Selisih biaya efektif', a > b ? a - b : b - a);
        notice('Cashback belum tentu dapat dicairkan atau dipakai tanpa syarat.'); break;
      }
      case 'subscriptions': {
        const monthly = v.monthly * v.months, packages = (v.months + 11n) / 12n, annual = v.annual * packages;
        m('Paket bulanan selama penggunaan', monthly); m('Paket tahunan yang harus dibeli', annual); num('Jumlah paket tahunan', packages, 'paket');
        txt('Lebih hemat', monthly === annual ? 'Biaya sama' : monthly < annual ? 'Paket bulanan' : 'Paket tahunan'); m('Selisih biaya', monthly > annual ? monthly - annual : annual - monthly);
        step('Paket tahunan = pembulatan ke atas jumlah bulan / 12.'); break;
      }
      case 'travel': {
        const transport = v.transport * v.people, hotel = v.hotel * v.rooms * v.nights, food = v.food * v.people * v.days, activity = v.activities * v.people;
        const base = transport + hotel + food + activity + v.other, reserve = percentage(base, v.reserve);
        m('Transportasi', transport); m('Penginapan', hotel); m('Makan', food); m('Aktivitas', activity); m('Biaya lain', v.other); m('Cadangan', reserve); m('Total perjalanan', base + reserve, true);
        m('Ekuivalen per orang', divide(base + reserve, v.people)); step('Total biaya rombongan ditambah cadangan; ekuivalen per orang hanya untuk perencanaan.'); break;
      }
      case 'vehicle': {
        const fuel = divide(v.distance * v.fuelPrice, v.efficiency), maintenance = divide(v.distance * v.maintenance, SCALE);
        const total = fuel + maintenance + v.toll + v.parking;
        num('Kebutuhan BBM', fixed(v.distance, v.efficiency, 4), 'liter'); m('Biaya BBM', fuel); m('Cadangan servis', maintenance); m('Tol dan parkir', v.toll + v.parking); m('Total perjalanan', total, true);
        num('Biaya per kilometer', fixed(total * SCALE, v.distance, 4), 'Rp/km'); break;
      }
      case 'electricity': {
        const consumption = v.watts * v.hours * v.devices * v.days;
        const energy = divide(consumption * v.tariff, 1000n * SCALE * SCALE * SCALE), extra = percentage(energy, v.tax);
        num('Konsumsi energi', fixed(consumption, 1000n * SCALE * SCALE, 4), 'kWh'); m('Biaya energi', energy); m('Pajak / tambahan', extra); m('Biaya tetap', v.fixed); m('Total estimasi', energy + extra + v.fixed, true);
        step('kWh = watt / 1.000 x jam per hari x jumlah perangkat x hari.'); break;
      }
      case 'housing': {
        const aMonthly = v.rentA + v.utilitiesA + v.commuteA, bMonthly = v.rentB + v.utilitiesB + v.commuteB;
        const a = aMonthly * v.months + v.setupA, b = bMonthly * v.months + v.setupB;
        m('Biaya tinggal A', a); m('Biaya tinggal B', b); m('Uang awal A (bulan pertama + biaya awal + deposit)', aMonthly + v.setupA + v.depositA); m('Uang awal B (bulan pertama + biaya awal + deposit)', bMonthly + v.setupB + v.depositB);
        txt('Biaya tinggal lebih rendah', a === b ? 'Sama' : a < b ? 'Kos A' : 'Kontrakan B'); m('Selisih biaya tinggal', a > b ? a - b : b - a); break;
      }
      case 'emergency': {
        const target = v.monthly * v.months;
        m('Kebutuhan dana darurat', target, true); m('Dana tersedia', v.available); m('Kekurangan', target > v.available ? target - v.available : 0n);
        num('Perlindungan tersedia', v.monthly ? fixed(v.available, v.monthly, 2) : '0', 'bulan'); if (!v.monthly) notice('Biaya wajib nol; periksa kembali kebutuhan biaya hidup.'); break;
      }
      case 'wage': {
        m('Pendapatan per hari', divide(v.salary, v.days)); m('Pendapatan per jam', divide(v.salary * SCALE, v.days * v.hours), true); num('Jam kerja per bulan', fixed(v.days * v.hours, SCALE, 4), 'jam'); break;
      }
      case 'compound': {
        let balance = v.principal * SCALE;
        const contribution = v.contribution * SCALE;
        for (let i = 1n; i <= v.months; i++) {
          if (v.timing === 'start') balance += contribution;
          balance += divide(balance * v.annualRate, HUNDRED * 12n);
          if (v.timing === 'end') balance += contribution;
          if (balance > MAX_MONEY * SCALE) fail('Proyeksi melebihi batas nominal. Perkecil jangka waktu atau imbal hasil.');
          if (i % 12n === 0n || i === v.months) schedule.push({ period: 'Bulan ' + i, amount: moneyValue(divide(balance, SCALE)), detail: 'Saldo proyeksi' });
        }
        const deposits = v.principal + v.contribution * v.months, total = divide(balance, SCALE);
        m('Total modal dan setoran', deposits); m('Pertumbuhan estimasi', total - deposits); m('Saldo akhir estimasi', total, true);
        step('Setiap bulan: saldo x bunga nominal tahunan / 12, dengan waktu setoran sesuai pilihan.'); break;
      }
      case 'inflation': {
        let future = v.price * SCALE, denominator = HUNDRED + v.inflation;
        for (let i = 0n; i < v.years; i++) { future = divide(future * denominator, HUNDRED); if (future > MAX_MONEY * SCALE) fail('Proyeksi harga melebihi batas nominal.'); }
        const price = divide(future, SCALE); m('Perkiraan harga masa depan', price, true); m('Kenaikan harga', price - v.price);
        let purchasing = v.price * SCALE; for (let i = 0n; i < v.years; i++) purchasing = divide(purchasing * HUNDRED, denominator);
        m('Daya beli uang yang tidak bertumbuh', divide(purchasing, SCALE)); step('Harga masa depan = harga kini x (1 + inflasi)^tahun.'); break;
      }
      case 'currency': {
        if (v.direction === 'from-idr' && v.amount % SCALE !== 0n) fail('Nominal Rupiah yang ditukar harus berupa bilangan bulat.');
        const rupiah = v.direction === 'to-idr' ? divide(v.amount * v.rate, SCALE * SCALE) : divide(v.amount, SCALE);
        const fee = percentage(rupiah, v.feeRate) + v.fee;
        if (fee > rupiah) fail('Biaya penukaran melebihi nominal yang ditukar.');
        m('Nilai Rupiah sebelum biaya', rupiah); m('Biaya penukaran', fee);
        if (v.direction === 'to-idr') m('Rupiah diterima', rupiah - fee, true);
        else num('Valuta diterima', fixed((rupiah - fee) * SCALE, v.rate, 6), v.currency);
        txt('Tanggal kurs manual', v.rateDate); step('Biaya persentase dan biaya tetap dikurangkan dari nilai Rupiah sebelum konversi akhir.'); break;
      }
      case 'loan': {
        needPositive(v.principal, 'Pokok pinjaman');
        const count = Number(v.months);
        let balance = v.principal, totalInterest = 0n, totalPayment = 0n, first = 0n, last = 0n;
        let annuity = divide(v.principal, v.months, 'ceil');
        if (v.annualRate) {
          // Rational powers avoid floating-point rounding at Rupiah boundaries.
          const common = gcd(v.annualRate, HUNDRED * 12n), n = v.annualRate / common, d = HUNDRED * 12n / common;
          const growth = (d + n) ** v.months, base = d ** v.months;
          annuity = divide(v.principal * n * growth, d * (growth - base), 'ceil');
        }
        const flatInterest = divide(v.principal * v.annualRate, HUNDRED * 12n);
        for (let i = 1; i <= count; i++) {
          let interest = v.method === 'flat' ? flatInterest : divide(balance * v.annualRate, HUNDRED * 12n);
          let principal = v.method === 'annuity' ? annuity - interest : v.principal / v.months + (BigInt(i) <= v.principal % v.months ? 1n : 0n);
          if (principal < 0n) fail('Angsuran tidak menutup bunga.');
          if (principal > balance || i === count) principal = balance;
          if (!balance) interest = 0n;
          const payment = principal + interest; balance -= principal; totalInterest += interest; totalPayment += payment;
          if (i === 1) first = payment;
          if (payment > 0n) last = payment;
          schedule.push({ period: 'Bulan ' + i, amount: moneyValue(payment), detail: 'Pokok Rp' + principal + ' + bunga Rp' + interest + '; sisa Rp' + balance });
        }
        m('Angsuran pertama', first, true); m('Pembayaran terakhir yang tidak nol', last); m('Total bunga', totalInterest); m('Biaya awal', v.fee); m('Total pembayaran termasuk biaya', totalPayment + v.fee);
        step(v.method === 'annuity' ? 'Anuitas memakai bunga efektif bulanan atas sisa pokok; angsuran dibulatkan ke atas, terakhir disesuaikan.' : v.method === 'flat' ? 'Bunga bulanan = pokok awal x bunga tahunan / 12.' : 'Pokok dibagi rata; bunga tiap bulan dihitung dari sisa pokok.'); break;
      }
      case 'fixed-margin': {
        const selling = v.price + v.margin;
        if (v.downPayment > selling) fail('Uang muka melebihi harga jual yang disepakati.');
        const financed = selling - v.downPayment, payment = divide(financed, v.months, 'ceil');
        // Very small balances can finish before the last calendar installment.
        const installments = payment ? (financed + payment - 1n) / payment : 0n;
        m('Harga jual disepakati', selling); m('Sisa pembayaran', financed); m('Angsuran reguler', payment, true); m('Pembayaran terakhir', installments ? financed - payment * (installments - 1n) : 0n); num('Angsuran berisi pembayaran', installments, 'bulan'); m('Uang awal termasuk biaya', v.downPayment + v.fee); m('Total biaya', selling + v.fee);
        step('Sisa pembayaran = harga pokok + total margin - uang muka; dibagi tenor, pembulatan ke atas dengan pembayaran terakhir disesuaikan.'); break;
      }
      case 'debt-payoff': {
        needPositive(v.principal, 'Sisa utang'); const payment = v.payment + v.extra; needPositive(payment, 'Pembayaran bulanan');
        let balance = v.principal, totalInterest = 0n, totalPayment = 0n, months = 0;
        while (balance > 0n && months < 600) {
          const interest = divide(balance * v.annualRate, HUNDRED * 12n);
          if (payment <= interest) fail('Pembayaran bulanan harus melebihi bunga bulan pertama.');
          const paid = payment < balance + interest ? payment : balance + interest;
          balance -= paid - interest; totalInterest += interest; totalPayment += paid; months++;
          schedule.push({ period: 'Bulan ' + months, amount: moneyValue(paid), detail: 'Bunga Rp' + interest + '; sisa Rp' + balance });
        }
        if (balance > 0n) fail('Belum lunas dalam 600 bulan. Naikkan pembayaran bulanan.');
        num('Lama pelunasan', months, 'bulan'); m('Total bunga', totalInterest); m('Total pembayaran', totalPayment); m('Pembayaran bulanan', payment, true); step('Setiap pembayaran menutup bunga bulan berjalan, kemudian mengurangi pokok.'); break;
      }
      case 'debt-ratio': {
        needPositive(v.income, 'Penghasilan'); const payments = v.existing + v.newPayment, allowed = percentage(v.income, v.limit);
        pct('Rasio cicilan', payments, v.income); m('Total cicilan', payments); m('Batas cicilan pribadi', allowed); m('Ruang cicilan tambahan', allowed > v.existing ? allowed - v.existing : 0n);
        txt('Status batas pribadi', payments <= allowed ? 'Dalam batas pilihan Anda' : 'Melebihi batas pilihan Anda'); m('Pendapatan tersisa', v.income - payments); break;
      }
      case 'selling-price': {
        const denominator = v.basis === 'margin' ? HUNDRED - v.profit - v.fee : HUNDRED - v.fee;
        if (denominator <= 0n) fail('Gabungan margin dan biaya platform harus kurang dari 100%.');
        const price = divide(v.cost * (v.basis === 'markup' ? HUNDRED + v.profit : HUNDRED), denominator, 'ceil'), fee = percentage(price, v.fee);
        m('Harga jual minimum', price, true); m('Biaya platform', fee); m('Laba setelah biaya', price - fee - v.cost);
        if (price) pct('Margin aktual setelah biaya', price - fee - v.cost, price);
        step(v.basis === 'markup' ? 'Harga = modal x (1 + markup) / (1 - biaya platform).' : 'Harga = modal / (1 - margin - biaya platform).'); break;
      }
      case 'margin': {
        needPositive(v.cost, 'Modal'); needPositive(v.price, 'Harga jual'); const profit = v.price - v.cost;
        m('Laba per unit', profit, true); pct('Margin dari harga jual', profit, v.price); pct('Markup dari modal', profit, v.cost); if (profit < 0n) notice('Harga jual lebih rendah dari modal; penjualan menghasilkan kerugian.'); break;
      }
      case 'break-even': {
        const contribution = v.price - v.variable; needPositive(contribution, 'Selisih harga jual dan biaya variabel');
        const units = divide(v.fixed, contribution, 'ceil'); num('Unit minimum titik impas', units, 'unit'); m('Omzet minimum pada unit tersebut', units * v.price); m('Kontribusi per unit', contribution); m('Laba pada rencana penjualan', contribution * v.sales - v.fixed);
        step('Unit titik impas = biaya tetap / (harga jual - biaya variabel), dibulatkan ke atas.'); break;
      }
      case 'zakat-maal': case 'zakat-savings': case 'zakat-trade': case 'zakat-investment': {
        let assets;
        if (definition.id === 'zakat-maal') assets = v.cash + v.savings + v.gold + v.silver + v.trade + v.investment + v.receivables;
        else if (definition.id === 'zakat-trade') assets = v.inventory + v.cash + v.receivables;
        else if (definition.id === 'zakat-investment') assets = (v.purpose === 'trading' ? v.market : v.eligible) + v.returns;
        else assets = v.assets;
        const liabilities = v.deduction === 'due' ? v.liabilities : 0n;
        if (liabilities > assets) fail('Pengurang melebihi harta wajib zakat.');
        const net = assets - liabilities, nisab = v.metalPrice * (v.benchmark === 'gold' ? 85n : 595n);
        m('Total harta wajib zakat', assets); m('Pengurang sesuai metode', liabilities); m('Dasar zakat', net); m('Nisab pilihan', nisab); txt('Tanggal harga logam', v.priceDate);
        const confirmed = eligible([v.owned, v.haul], 'Konfirmasikan kepemilikan sempurna dan satu haul Hijriah sebelum menetapkan kewajiban.');
        const due = confirmed && net >= nisab ? divide(net, 40n, 'ceil') : 0n;
        if (confirmed) { status = net >= nisab ? 'eligible' : 'below-nisab'; headline = net >= nisab ? 'Memenuhi nisab dan syarat pilihan' : 'Belum mencapai nisab'; }
        m('Zakat hasil simulasi', due, due > 0n && definition.id !== 'zakat-investment'); if (definition.id === 'zakat-investment') { m('Sudah dibayar untuk aset dan haul sama', v.paid); m('Sisa zakat', due > v.paid ? due - v.paid : 0n, due > v.paid); if (v.paid > due) notice('Pembayaran sebelumnya melebihi hasil simulasi; periksa dasar dan periode agar tidak dihitung ganda.'); }
        step('Dasar zakat dibandingkan dengan nisab; jika memenuhi syarat, zakat = dasar / 40 (2,5%).'); break;
      }
      case 'zakat-income': {
        const expenses = v.basis === 'net' ? v.expenses : 0n;
        if (expenses > v.income) fail('Pengurang melebihi penghasilan.');
        const base = v.income - expenses, annualNisab = v.goldPrice * 85n, meets = v.period === 'annual' ? base >= annualNisab : base * 12n >= annualNisab;
        m('Dasar penghasilan', base); m('Nisab tahunan', annualNisab); m('Ekuivalen nisab bulanan', divide(annualNisab, 12n, 'ceil')); txt('Tanggal harga emas', v.priceDate);
        const confirmed = eligible([v.owned], 'Konfirmasikan penghasilan telah diterima / dimiliki.');
        const due = confirmed && meets ? divide(base, 40n, 'ceil') : 0n;
        if (confirmed) { status = meets ? 'eligible' : 'below-nisab'; headline = meets ? 'Memenuhi ambang metode penghasilan' : 'Belum mencapai ambang metode penghasilan'; }
        m('Zakat hasil simulasi periode ini', due, due > 0n); if (v.period === 'monthly') notice('Pembayaran bulanan perlu diperiksa kembali terhadap penghasilan dan kewajiban tahunan.');
        step('Nisab tahunan = 85 x harga emas murni. Pembayaran berkala = 2,5% dasar penghasilan periode pilihan.'); break;
      }
      case 'zakat-gold': case 'zakat-silver': {
        const excluded = v.jewelry === 'exclude' ? v.jewelryWeight : 0n;
        if (excluded > v.weight) fail('Berat perhiasan yang dikecualikan melebihi berat total.');
        const pure = (v.weight - excluded) * v.purity, nisab = (definition.id === 'zakat-gold' ? 85n : 595n) * SCALE * HUNDRED;
        num('Berat murni wajib zakat', fixed(pure, SCALE * HUNDRED, 6), 'gram'); num('Nisab berat murni', definition.id === 'zakat-gold' ? '85' : '595', 'gram');
        const value = divide(pure * v.price, SCALE * HUNDRED); m('Nilai harta wajib zakat', value); txt('Tanggal harga logam', v.priceDate);
        const confirmed = eligible([v.owned, v.haul], 'Konfirmasikan kepemilikan sempurna dan satu haul Hijriah.');
        const meets = pure >= nisab, due = confirmed && meets ? divide(pure * v.price, SCALE * HUNDRED * 40n, 'ceil') : 0n;
        if (confirmed) { status = meets ? 'eligible' : 'below-nisab'; headline = meets ? 'Memenuhi nisab berat murni' : 'Belum mencapai nisab berat murni'; }
        m('Nilai zakat hasil simulasi', due, due > 0n); if (confirmed && meets) num('Ekuivalen zakat logam murni', fixed(pure, SCALE * HUNDRED * 40n, 6), 'gram');
        step('Berat wajib x kadar kemurnian, dibandingkan nisab; zakat = 2,5% berat murni atau nilai ekuivalennya.'); break;
      }
      case 'zakat-crops': {
        const rate = v.irrigation === 'natural' ? 10n : v.irrigation === 'paid' ? 5n : 75n;
        const denominator = v.irrigation === 'mixed' ? 1000n : 100n;
        num('Nisab menurut rujukan', fixed(v.nisabKg, SCALE, 6), 'kg'); num('Hasil panen', fixed(v.harvest, SCALE, 6), 'kg');
        const confirmed = eligible([v.eligible], 'Pastikan jenis hasil panen termasuk hasil yang wajib zakat menurut rujukan Anda.');
        const meets = v.harvest >= v.nisabKg;
        if (confirmed) { status = meets ? 'eligible' : 'below-nisab'; headline = meets ? 'Panen memenuhi nisab pilihan' : 'Panen belum mencapai nisab'; }
        const numerator = confirmed && meets ? v.harvest * rate : 0n;
        num('Zakat hasil panen', fixed(numerator, SCALE * denominator, 6), 'kg'); m('Nilai ekuivalen zakat', divide(numerator * v.price, SCALE * SCALE * denominator, 'ceil'), confirmed && meets);
        step('Hasil panen x tarif pengairan. Nisab kg diambil dari konversi lima wasaq menurut komoditas.'); break;
      }
      case 'zakat-livestock': {
        const threshold = v.animal === 'sheep' ? 40n : v.animal === 'cattle' ? 30n : 5n;
        num('Jumlah ternak', v.count, 'ekor'); num('Nisab', threshold, 'ekor');
        if (!eligible([v.owned, v.haul, v.grazing], 'Konfirmasikan kepemilikan, haul Hijriah, dan syarat ternak gembalaan bukan hewan kerja.')) break;
        if (v.count < threshold) { status = 'below-nisab'; headline = 'Belum mencapai nisab ternak'; txt('Zakat ternak', 'Belum wajib pada jumlah ini'); break; }
        status = 'eligible'; headline = 'Memenuhi nisab ternak';
        if (v.animal === 'sheep') {
          const due = v.count <= 120n ? 1n : v.count <= 200n ? 2n : v.count <= 300n ? 3n : v.count / 100n;
          num('Kambing / domba untuk zakat', due, 'ekor'); notice('Kambing minimal genap satu tahun atau domba memenuhi umur jadza sesuai rujukan.');
        } else if (v.animal === 'camel' && v.count <= 120n) {
          if (v.count < 25n) num('Kambing untuk zakat unta', v.count / 5n, 'ekor');
          else txt('Hewan zakat', v.count <= 35n ? '1 bint makhad (unta betina genap 1 tahun)' : v.count <= 45n ? '1 bint labun (betina genap 2 tahun)' : v.count <= 60n ? '1 hiqqah (betina genap 3 tahun)' : v.count <= 75n ? '1 jadzaah (betina genap 4 tahun)' : v.count <= 90n ? '2 bint labun (betina genap 2 tahun)' : '2 hiqqah (betina genap 3 tahun)');
        } else {
          const small = v.animal === 'cattle' ? 30n : 40n, big = v.animal === 'cattle' ? 40n : 50n;
          let best = -1n, alternatives = [];
          for (let b = 0n; b * big <= v.count; b++) {
            const a = (v.count - b * big) / small, covered = a * small + b * big;
            if (covered > best) { best = covered; alternatives = [{ a, b }]; } else if (covered === best) alternatives.push({ a, b });
          }
          alternatives.sort((a, b) => Number((a.a + a.b) - (b.a + b.b)));
          alternatives.slice(0, 4).forEach((option, index) => txt('Kombinasi hewan' + (index ? ' alternatif ' + index : ''), v.animal === 'cattle' ? option.a + ' tabi/tabiah (genap 1 tahun) + ' + option.b + ' musinnah (genap 2 tahun)' : option.a + ' bint labun (betina genap 2 tahun) + ' + option.b + ' hiqqah (betina genap 3 tahun)'));
          if (alternatives.length > 1) notice('Terdapat kombinasi ambang setara. Pemilihan hewan pembayaran dikonfirmasi dengan amil.');
        }
        step('Jumlah hewan mengikuti tabel ambang, tanpa mengubahnya menjadi persentase harga ternak.'); break;
      }
      case 'zakat-rikaz': {
        if (!eligible([v.eligible], 'Kategori rikaz harus dipastikan; temuan biasa, hadiah, dan hasil tambang tidak otomatis termasuk rikaz.')) break;
        m('Nilai harta rikaz', v.value); m('Zakat rikaz (20%)', divide(v.value, 5n, 'ceil'), v.value > 0n); status = 'eligible'; step('Zakat = nilai rikaz / 5; tidak menunggu haul pada metode jumhur.'); break;
      }
      case 'zakat-fitrah': {
        num('Jumlah orang', v.people, 'orang'); num('Bahan makanan pokok', fixed(v.kg * v.people, SCALE, 6), 'kg');
        if (v.payment === 'money') { needPositive(v.perPerson, 'Ketetapan uang per orang'); m('Total zakat fitrah uang', v.perPerson * v.people, true); }
        txt('Ukuran asal', 'Satu sha per orang'); step('Jumlah orang x konversi satu sha atau ketetapan uang per orang.'); break;
      }
      case 'fidyah': {
        num('Hari yang dihitung', v.days, 'hari');
        if (!eligible([v.confirmed], 'Pastikan kondisi ini memang mewajibkan fidyah menurut rujukan; qadha tidak otomatis digantikan dengan pembayaran.')) break;
        num('Porsi untuk orang miskin', v.days, 'porsi sesuai ketentuan'); m(v.payment === 'money' ? 'Fidyah uang menurut metode pilihan' : 'Estimasi biaya penyediaan makanan', v.days * v.perDay, true);
        if (v.condition === 'other') notice('Dasar kewajiban memakai konfirmasi rujukan Anda, termasuk perbedaan pendapat pada kondisi khusus.'); step('Hari yang wajib fidyah x satu porsi / nilai per hari menurut rujukan.'); break;
      }
      case 'kaffarah-oath': {
        if (!eligible([v.confirmed], 'Pastikan sumpah dan jumlah kafarat yang benar sebelum menghitung.')) break;
        if (v.method === 'fast') { num('Puasa', v.count * 3n, 'hari'); notice('Puasa berlaku setelah tidak mampu menunaikan bentuk kafarat harta. Ketentuan berturut-turut mengikuti rujukan.'); }
        else { num('Jumlah penerima', v.count * 10n, 'orang miskin'); m('Estimasi biaya ' + (v.method === 'food' ? 'makanan' : 'pakaian'), v.count * 10n * v.perPerson, true); }
        step('Satu kafarat: sepuluh penerima makanan / pakaian; jika tidak mampu, tiga hari puasa.'); break;
      }
      case 'kaffarah-ramadan': {
        if (!eligible([v.confirmed], 'Pastikan jenis pelanggaran dan urutan kemampuan; kafarat ini tidak otomatis berlaku pada setiap puasa yang batal.')) break;
        if (v.stage === 'fast') { num('Jumlah kafarat', v.count, 'kafarat'); num('Puasa untuk setiap kafarat', 2n, 'bulan Hijriah berturut-turut'); notice('Setiap kafarat memerlukan dua bulan berturut-turut. Dua bulan tidak diganti secara otomatis dengan 60 hari kalender.'); }
        else { num('Jumlah penerima makanan', v.count * 60n, 'orang miskin'); m('Estimasi biaya makanan', v.count * 60n * v.perPerson, true); }
        step('Ikuti urutan kemampuan dalam hadis untuk tiap kewajiban kafarat yang telah dipastikan.'); break;
      }
      case 'wasiyyah': case 'faraid': {
        if (v.funeral + v.debts > v.estate) fail('Biaya pengurusan jenazah dan utang melebihi harta; belum tersedia harta untuk dibagi.');
        const afterDebts = v.estate - v.funeral - v.debts, limit = afterDebts / 3n;
        if (v.bequest > afterDebts) fail('Wasiat melebihi sisa harta setelah kewajiban.');
        const requiresConsent = v.bequest > limit || (v.beneficiaryHeir && v.bequest > 0n);
        m('Harta setelah pengurusan dan utang', afterDebts); m('Batas umum wasiat sepertiga', limit);
        if (requiresConsent && !v.consent) { status = 'needs-confirmation'; headline = 'Wasiat memerlukan persetujuan'; m('Wasiat yang diminta', v.bequest); notice('Wasiat kepada ahli waris atau melebihi sepertiga belum dapat diterapkan tanpa persetujuan ahli waris yang berhak.'); break; }
        const net = afterDebts - v.bequest; m('Wasiat yang diterapkan', v.bequest); m('Harta bersih untuk ahli waris', net, definition.id === 'wasiyyah');
        if (definition.id === 'faraid') {
          if (!eligible([v.scope], 'Pastikan semua ahli waris dan lingkup kasus. Kondisi di luar form memerlukan perhitungan khusus.')) break;
          const inheritance = faraid(v, net); rows.push(...inheritance.rows); warnings.push(...inheritance.warnings); steps.push(...inheritance.steps); status = inheritance.status;
          headline = status === 'unallocated' ? 'Ada sisa untuk penetapan lebih lanjut' : 'Simulasi pembagian warisan';
        }
        step('Harta bersih = harta pewaris - pengurusan jenazah - utang - wasiat yang sah.'); break;
      }
      default: fail('Kalkulator belum dikenal.');
    }
    return { calculatorID: definition.id, headline, status, rows, warnings, steps, schedule, primaryAmount, primaryLabel };
  }

  function faraid(v, estate) {
    const shares = [], warnings = [], steps = [], blocked = [], present = {};
    const counts = ['sons', 'daughters', 'grandsons', 'granddaughters', 'brothers', 'sisters', 'paternalBrothers', 'paternalSisters', 'maternalBrothers', 'maternalSisters'];
    counts.forEach(key => { present[key] = v[key]; });
    ['father', 'mother', 'grandfather', 'paternalGrandmother', 'maternalGrandmother', 'husband'].forEach(key => { present[key] = v[key] ? 1n : 0n; });
    present.wives = v.wives || 0n;
    const names = { sons: 'Anak laki-laki', daughters: 'Anak perempuan', grandsons: 'Cucu laki-laki dari anak laki-laki', granddaughters: 'Cucu perempuan dari anak laki-laki', father: 'Ayah', mother: 'Ibu', grandfather: 'Kakek dari ayah', paternalGrandmother: 'Nenek dari ayah', maternalGrandmother: 'Nenek dari ibu', husband: 'Suami', wives: 'Istri', brothers: 'Saudara laki-laki kandung', sisters: 'Saudara perempuan kandung', paternalBrothers: 'Saudara laki-laki seayah', paternalSisters: 'Saudara perempuan seayah', maternalBrothers: 'Saudara laki-laki seibu', maternalSisters: 'Saudara perempuan seibu' };
    const block = (key, reason) => { if (present[key]) blocked.push(names[key] + ': terhalang oleh ' + reason + '.'); present[key] = 0n; };
    const add = (key, numerator, denominator) => { if (present[key]) shares.push({ key, count: present[key], share: fraction(numerator, denominator), reason: 'Bagian tetap ' + numerator + '/' + denominator }); };
    const siblingsForMother = v.brothers + v.sisters + v.paternalBrothers + v.paternalSisters + v.maternalBrothers + v.maternalSisters;
    if (present.father) { block('grandfather', 'ayah'); block('paternalGrandmother', 'ayah'); }
    if (present.mother) { block('paternalGrandmother', 'ibu'); block('maternalGrandmother', 'ibu'); }
    if (present.sons) { block('grandsons', 'anak laki-laki'); block('granddaughters', 'anak laki-laki'); }
    const maleDescendant = present.sons > 0n || present.grandsons > 0n;
    const descendant = maleDescendant || present.daughters > 0n || present.granddaughters > 0n;
    const ascendantKey = present.father ? 'father' : present.grandfather ? 'grandfather' : null;
    if (maleDescendant || ascendantKey) ['brothers', 'sisters', 'paternalBrothers', 'paternalSisters'].forEach(key => block(key, maleDescendant ? 'keturunan laki-laki' : names[ascendantKey]));
    if (descendant || ascendantKey) ['maternalBrothers', 'maternalSisters'].forEach(key => block(key, descendant ? 'keturunan' : names[ascendantKey]));
    if (present.brothers) { block('paternalBrothers', 'saudara laki-laki kandung'); block('paternalSisters', 'saudara laki-laki kandung'); }
    if (present.husband) add('husband', 1n, descendant ? 4n : 2n);
    if (present.wives) add('wives', 1n, descendant ? 8n : 4n);
    if (present.mother) {
      if (descendant || siblingsForMother >= 2n) add('mother', 1n, 6n);
      else if (present.father && (present.husband || present.wives)) {
        const spouse = shares.reduce((sum, row) => fadd(sum, row.share), ZERO);
        const remainder = fadd(ONE, fraction(-spouse.n, spouse.d));
        shares.push({ key: 'mother', count: 1n, share: fmul(remainder, fraction(1n, 3n)), reason: 'Sepertiga sisa setelah bagian pasangan (umariyyatain)' });
      } else add('mother', 1n, 3n);
    } else {
      const grandmothers = (present.paternalGrandmother ? 1n : 0n) + (present.maternalGrandmother ? 1n : 0n);
      if (grandmothers) { add('paternalGrandmother', 1n, 6n * grandmothers); add('maternalGrandmother', 1n, 6n * grandmothers); }
    }
    if (ascendantKey && descendant) add(ascendantKey, 1n, 6n);
    let residual = [];
    const pair = (male, female) => { residual = [{ key: male, count: present[male], weight: 2n }]; if (present[female]) residual.push({ key: female, count: present[female], weight: 1n }); };
    if (present.sons) pair('sons', 'daughters');
    else {
      if (present.daughters) add('daughters', present.daughters === 1n ? 1n : 2n, present.daughters === 1n ? 2n : 3n);
      if (present.grandsons) pair('grandsons', 'granddaughters');
      else if (present.granddaughters) {
        if (present.daughters >= 2n) block('granddaughters', 'dua atau lebih anak perempuan tanpa cucu laki-laki penyerta');
        else if (present.daughters === 1n) add('granddaughters', 1n, 6n);
        else add('granddaughters', present.granddaughters === 1n ? 1n : 2n, present.granddaughters === 1n ? 2n : 3n);
      }
      if (!residual.length && ascendantKey && !maleDescendant) residual = [{ key: ascendantKey, count: 1n, weight: 1n }];
      if (!ascendantKey) {
        const maternal = present.maternalBrothers + present.maternalSisters;
        if (maternal) {
          const denominator = maternal === 1n ? 6n : 3n;
          if (present.maternalBrothers) add('maternalBrothers', present.maternalBrothers, denominator * maternal);
          if (present.maternalSisters) add('maternalSisters', present.maternalSisters, denominator * maternal);
        }
        if (!residual.length) {
          if (present.brothers) pair('brothers', 'sisters');
          else if (present.sisters && descendant) {
            residual = [{ key: 'sisters', count: present.sisters, weight: 1n }];
            block('paternalBrothers', 'saudara perempuan kandung sebagai asabah bersama keturunan perempuan');
            block('paternalSisters', 'saudara perempuan kandung sebagai asabah bersama keturunan perempuan');
          } else {
            if (present.sisters) add('sisters', present.sisters === 1n ? 1n : 2n, present.sisters === 1n ? 2n : 3n);
            if (present.paternalBrothers) pair('paternalBrothers', 'paternalSisters');
            else if (present.paternalSisters) {
              if (present.sisters >= 2n) block('paternalSisters', 'dua atau lebih saudara perempuan kandung tanpa saudara laki-laki seayah penyerta');
              else if (descendant) residual = [{ key: 'paternalSisters', count: present.paternalSisters, weight: 1n }];
              else if (present.sisters === 1n) add('paternalSisters', 1n, 6n);
              else add('paternalSisters', present.paternalSisters === 1n ? 1n : 2n, present.paternalSisters === 1n ? 2n : 3n);
            }
          }
        }
      }
    }
    let total = shares.reduce((sum, row) => fadd(sum, row.share), ZERO), remainder = fadd(ONE, fraction(-total.n, total.d));
    if (total.n > total.d) {
      shares.forEach(row => { row.share = fdiv(row.share, total); row.reason += '; disesuaikan dengan aul'; });
      remainder = ZERO; steps.push('Jumlah bagian tetap melebihi satu; aul menormalkan seluruh bagian secara proporsional.');
    } else if (remainder.n > 0n && residual.length) {
      const weight = residual.reduce((sum, row) => sum + row.count * row.weight, 0n);
      residual.forEach(row => {
        const extra = fmul(remainder, fraction(row.count * row.weight, weight)), existing = shares.find(item => item.key === row.key);
        if (existing) { existing.share = fadd(existing.share, extra); existing.reason += ' dan sisa sebagai asabah'; }
        else shares.push({ key: row.key, count: row.count, share: extra, reason: 'Asabah, bobot ' + row.weight + ' per orang' });
      }); remainder = ZERO; steps.push('Sisa dibagi kepada asabah terdekat; kelompok laki-laki/perempuan memakai bobot 2:1 jika berlaku.');
    } else if (remainder.n > 0n) {
      const eligible = shares.filter(row => !['husband', 'wives'].includes(row.key));
      const sum = eligible.reduce((value, row) => fadd(value, row.share), ZERO);
      if (sum.n) { eligible.forEach(row => { row.share = fadd(row.share, fmul(remainder, fdiv(row.share, sum))); row.reason += '; termasuk radd'; }); remainder = ZERO; steps.push('Radd dibagikan proporsional kepada pemilik bagian selain pasangan menurut metode Hanafi.'); }
    }
    warnings.push(...blocked);
    if (!shares.length) fail('Belum ada ahli waris yang dapat dihitung. Periksa lingkup ahli waris dan gunakan penetapan khusus jika ahli waris berada di luar form.');
    const members = [];
    for (const row of shares) {
      const share = fmul(row.share, fraction(1n, row.count));
      for (let i = 1n; i <= row.count; i++) members.push({ label: names[row.key] + (row.count > 1n ? ' ' + i : ''), share, reason: row.reason });
    }
    if (remainder.n > 0n) { members.push({ label: 'Sisa untuk penetapan pihak berwenang', share: remainder, reason: 'Tidak otomatis diberikan kepada pasangan; ahli waris lebih jauh / ketentuan lain perlu diperiksa.' }); warnings.push('Ada sisa di luar bagian ahli waris pada form. Pembagian belum lengkap untuk dilaksanakan.'); }
    // Largest-remainder allocation preserves every Rupiah of the estate.
    const allocations = members.map((member, index) => ({ ...member, index, amount: estate * member.share.n / member.share.d, remainder: estate * member.share.n % member.share.d }));
    let pennies = estate - allocations.reduce((sum, member) => sum + member.amount, 0n);
    const ordered = allocations.slice().sort((a, b) => { const delta = a.remainder * b.share.d - b.remainder * a.share.d; return delta === 0n ? a.index - b.index : delta > 0n ? -1 : 1; });
    for (let i = 0; pennies > 0n; i++, pennies--) ordered[i % ordered.length].amount++;
    const rows = [];
    allocations.forEach(member => {
      rows.push({ label: member.label, value: moneyValue(member.amount), kind: 'money', unit: 'Rp' });
      rows.push({ label: 'Bagian ' + member.label, value: member.share.n + '/' + member.share.d + ' (' + fixed(member.share.n * 100n, member.share.d, 4) + '%). ' + member.reason, kind: 'text', unit: '' });
    });
    steps.push('Pembulatan memakai sisa terbesar; total seluruh nominal termasuk sisa sama persis dengan harta bersih.');
    return { rows, warnings, steps, status: remainder.n > 0n ? 'unallocated' : 'calculated' };
  }

  const engine = {
    visible,
    calculate(catalog, id, input) {
      try {
        const definition = catalog.calculators.find(item => item.id === id);
        if (!definition) fail('Kalkulator tidak tersedia.');
        return { result: compute(definition, input), error: null };
      } catch (error) { return { result: null, error: error.message || 'Perhitungan belum dapat diselesaikan.' }; }
    },
    calculateJSON(catalogJSON, id, inputJSON) {
      try { return JSON.stringify(engine.calculate(JSON.parse(catalogJSON), id, JSON.parse(inputJSON))); }
      catch (_) { return JSON.stringify({ result: null, error: 'Data perhitungan tidak valid.' }); }
    }
  };
  root.DanarapiCalculatorEngine = engine;
})(globalThis);
