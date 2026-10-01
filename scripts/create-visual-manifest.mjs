import { readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const root = new URL('../apps/web/artifacts/visual/', import.meta.url);
const files = [];
for (const browser of ['chromium', 'webkit', 'firefox']) {
  const directory = new URL(browser === 'chromium' ? './' : `${browser}/`, root);
  for (const name of await readdir(directory).catch(() => [])) {
    if (!name.endsWith('.png') || name.includes('before-reflow')) continue;
    const file = new URL(name, directory), bytes = await readFile(file);
    files.push({ browser, name: browser === 'chromium' ? name : `${browser}/${name}`, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex'), captured_at: (await stat(file)).mtime.toISOString() });
  }
}
const sources = ['apps/web/src/App.vue', 'apps/web/src/style.css', 'apps/web/src/tokens.css', 'apps/web/src/components/Modal.vue', 'apps/web/src/components/AttachmentPanel.vue', 'apps/web/src/components/TransactionForm.vue', 'apps/web/src/components/SplitForm.vue', 'apps/web/e2e/web.spec.ts', 'apps/web/playwright.config.ts', 'contracts/design-tokens.json'];
const sourceFiles = await Promise.all(sources.map(async name => ({ name, sha256: createHash('sha256').update(await readFile(new URL(`../${name}`, import.meta.url))).digest('hex') })));
await writeFile(new URL('manifest.json', root), JSON.stringify({ synthetic: true, generated_at: new Date().toISOString(), browsers: [...new Set(files.map(file => file.browser))], screens: ['beranda', 'input', 'split-bill', 'perlu-ditinjau', 'laporan'], matrix: ['390 light/dark', '1440 light/dark', '375 text200 light/dark'], screenshot_count: files.length, source_files: sourceFiles, files }, null, 2) + '\n');
console.log(`${files.length} synthetic screenshots indexed with SHA-256.`);
