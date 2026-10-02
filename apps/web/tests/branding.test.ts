import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const tokens = JSON.parse(readFileSync(new URL('../../../contracts/design-tokens.json', import.meta.url), 'utf8'));
const content = JSON.parse(readFileSync(new URL('../../../contracts/product-content.json', import.meta.url), 'utf8'));

function luminance(hex: string) {
  const channels = hex.slice(1).match(/../g)!.map(channel => parseInt(channel, 16) / 255).map(channel => channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4);
  return channels[0]! * 0.2126 + channels[1]! * 0.7152 + channels[2]! * 0.0722;
}
function contrast(foreground: string, background: string) {
  const values = [luminance(foreground), luminance(background)].sort((first, second) => second - first);
  return (values[0]! + 0.05) / (values[1]! + 0.05);
}

test('brand palettes preserve the supplied light and dark colors', () => {
  assert.equal(tokens.color.light.primary, '#09746C');
  assert.equal(tokens.color.light['primary-soft'], '#BAF4DE');
  assert.equal(tokens.color.light['peach-soft'], '#FDCEB2');
  assert.equal(tokens.color.light.canvas, '#FBFCFB');
  assert.equal(tokens.color.dark.primary, '#7BDDC2');
  assert.equal(tokens.color.dark['brand-mint'], '#9DE4C0');
  assert.equal(tokens.color.dark['brand-peach'], '#FDCBAC');
  assert.equal(tokens.color.dark.canvas, '#0A1624');
});

test('brand text and focus colors keep contrast on surfaces and pastel panels', () => {
  for (const theme of ['light', 'dark']) {
    const palette = tokens.color[theme];
    const surfaces = theme === 'light' ? ['canvas', 'surface', 'primary-soft', 'peach-soft', 'sky-soft', 'sun-soft'] : ['canvas', 'surface', 'mint-surface', 'peach-surface', 'sky-surface', 'sun-surface'];
    for (const surface of surfaces) {
      assert.ok(contrast(palette.muted, palette[surface]) >= 4.5, `${theme}/${surface}: supporting text`);
      assert.ok(contrast(palette['focus-ring'], palette[surface]) >= 3, `${theme}/${surface}: focus ring`);
    }
    assert.ok(contrast(palette['on-primary'], palette.primary) >= 4.5, `${theme}: primary button`);
  }
});

test('six supplied assets have valid lightweight web variants and favicons', () => {
  for (const name of ['logo', 'danarapi_text', 'background', 'onboarding_1', 'onboarding_2', 'onboarding_3']) {
    for (const theme of ['light', 'dark']) {
      const image = readFileSync(new URL(`../public/brand/danarapi/${name}-${theme}.webp`, import.meta.url));
      assert.equal(image.toString('ascii', 0, 4), 'RIFF');
      assert.equal(image.toString('ascii', 8, 12), 'WEBP');
      assert.ok(image.byteLength < 200000, `${name}/${theme}: asset budget`);
    }
  }
  for (const theme of ['light', 'dark']) {
    const favicon = readFileSync(new URL(`../public/brand/danarapi/favicon-${theme}.png`, import.meta.url));
    assert.equal(favicon.readUInt32BE(16), 64);
    assert.equal(favicon.readUInt32BE(20), 64);
  }
});

test('welcome and onboarding copy match each illustration purpose', () => {
  assert.ok(content.welcome.headline.includes('Keuangan rapi'));
  assert.deepEqual(content.onboarding.map((step: { image: string }) => step.image), ['onboarding_1', 'onboarding_2', 'onboarding_3']);
  assert.deepEqual(content.onboarding.map((step: { id: string }) => step.id), ['receipt', 'planning', 'split']);
  assert.equal(new Set(content.onboarding.map((step: { title: string }) => step.title)).size, 3);
  assert.ok(content.onboarding.every((step: { description: string }) => step.description.length < 100));
});
