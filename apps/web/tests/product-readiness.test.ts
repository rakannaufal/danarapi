import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { calendarDate } from '../../../supabase/functions/_shared/calendar.ts';
import { consentAllowsScan, policyVersion } from '../../../supabase/functions/_shared/product.ts';
import { fromZonedTime } from '../src/timezone.ts';
import { localDay } from '../src/domain.ts';
import { DemoRepository } from '../src/demo.ts';

test('about and help content is shared by web and the bundled iOS catalog', () => {
  const catalog = JSON.parse(readFileSync(new URL('../../../contracts/product-content.json', import.meta.url), 'utf8'));
  assert.equal(catalog.features.length, 8);
  assert.equal(new Set(catalog.features.map((feature: { id: string }) => feature.id)).size, 8);
  assert.equal(catalog.help.gettingStarted.length, 3);
  assert.equal(catalog.supportTopics.length, 6);
  assert.equal(catalog.links.length, 6);
  assert.ok(catalog.links.every((link: { id: string }) => link.id !== 'status'));
  assert.doesNotMatch(JSON.stringify(catalog), /status layanan/i);
  for (const feature of catalog.features) {
    assert.ok(feature.title.length > 3);
    assert.ok(feature.description.length > 20);
  }
  assert.equal(new Set(catalog.faq.map((answer: { id: string }) => answer.id)).size, catalog.faq.length);
  for (const identifier of ['google', 'demo', 'camera', 'goal', 'budget', 'qris', 'split', 'transfer', 'period', 'offline', 'conflict', 'delete']) {
    assert.ok(catalog.faq.some((answer: { id: string }) => answer.id === identifier));
  }
  const native = readFileSync(new URL('../../ios/DanarapiApp/UI/ProductViews.swift', import.meta.url), 'utf8');
  assert.ok(native.includes('let features: [Feature]'));
  assert.ok(native.includes('let help: Help'));
  assert.ok(native.includes('let supportTopics: [Link]'));
  const project = readFileSync(new URL('../../ios/Danarapi.xcodeproj/project.pbxproj', import.meta.url), 'utf8');
  assert.ok(project.includes('../../contracts/product-content.json'));
});

test('product copy uses general infrastructure wording and preserves Google login and AI disclosure', () => {
  const catalog = JSON.parse(readFileSync(new URL('../../../contracts/product-content.json', import.meta.url), 'utf8'));
  assert.doesNotMatch(JSON.stringify(catalog), /\b(supabase|vercel|gemini|openai)\b/i);
  const privacy = catalog.pages.find((page: { id: string }) => page.id === 'privacy');
  const text = JSON.stringify(privacy);
  assert.match(text, /Login menggunakan Google/);
  assert.match(text, /layanan cloud/);
  assert.match(text, /layanan AI eksternal/);
  assert.match(text, /persetujuan terpisah/);
});

test('shared product catalog supplies legal pages, FAQ and exact consent version', () => {
  const catalog = JSON.parse(readFileSync(new URL('../../../contracts/product-content.json',import.meta.url),'utf8'));
  assert.equal(catalog.version,policyVersion);
  assert.equal(catalog.owner,'Rakan Naufal');
  for (const identifier of ['about','privacy','terms','delete-account']) {
    const page = catalog.pages.find((row: { id: string }) => row.id === identifier);
    assert.ok(page?.sections.length);
    assert.ok(page.sections.every((section: { paragraphs: string[] }) => section.paragraphs.every(text => text.length > 10)));
  }
  assert.ok(catalog.faq.length >= 10);
  assert.equal(new Set(catalog.faq.map((row: { id: string }) => row.id)).size,catalog.faq.length);
});
test('AI is denied for missing, revoked, malformed or stale consent', () => {
  for (const value of [null,undefined,{},[],{ granted: false,policy_version: policyVersion },{ granted: true,policy_version: 'old' },{ granted: 'true',policy_version: policyVersion }]) assert.equal(consentAllowsScan(value),false);
  assert.equal(consentAllowsScan({ granted: true,policy_version: policyVersion }),true);
});
test('date-only goals/budgets and report boundaries match web and Edge across account zones', () => {
  const cases = [['Asia/Jakarta','2026-09-30T17:00:00.000Z'],['Asia/Makassar','2026-09-30T16:00:00.000Z'],['Asia/Jayapura','2026-09-30T15:00:00.000Z'],['UTC','2026-10-01T00:00:00.000Z']];
  for (const [timezone,expected] of cases) {
    assert.equal(calendarDate('2026-10-01',timezone),expected);
    assert.equal(fromZonedTime('2026-10-01',timezone),expected);
    assert.equal(localDay(expected,timezone),'2026-10-01');
    assert.equal(localDay(new Date(Date.parse(expected)-1).toISOString(),timezone),'2026-09-30');
    assert.equal(localDay(calendarDate('2027-01-01',timezone),timezone),'2027-01-01');
  }
});
test('copying a budget preserves existing limits without financial movements', async () => {
  const repository = new DemoRepository();
  const data = await repository.snapshot();
  const categoryID = data.categories.find(row => row.kind === 'expense' && !row.archived)!.id;
  await repository.mutate('upsert_budget',{ category_id: categoryID,month: '2030-10-01',limit_amount: '120000' });
  await repository.mutate('upsert_budget',{ category_id: categoryID,month: '2030-11-01',limit_amount: '99000' });
  const before = await repository.snapshot();
  await repository.mutate('copy_budgets',{ from: '2030-10-01',to: '2030-11-01' });
  await repository.mutate('copy_budgets',{ from: '2030-10-01',to: '2030-12-01' });
  await repository.mutate('copy_budgets',{ from: '2030-10-01',to: '2030-12-01' });
  const after = await repository.snapshot();
  assert.equal(after.budgets.find(row => row.categoryID === categoryID && row.month.startsWith('2030-11'))!.limitAmount,'99000');
  assert.equal(after.budgets.filter(row => row.categoryID === categoryID && row.month.startsWith('2030-12')).length,1);
  assert.deepEqual(after.transactions,before.transactions);
  assert.deepEqual(after.overview,before.overview);
});
