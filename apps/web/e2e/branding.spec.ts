import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import content from '../../../contracts/product-content.json' with { type: 'json' };

for (const theme of ['light', 'dark']) for (const width of [320, 390, 1440]) {
  test(`brand assets and onboarding remain readable ${theme} ${width}`, async ({ page }, info) => {
    await page.setViewportSize({ width, height: 960 });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.addInitScript(value => localStorage.setItem('danarapi.theme', value), theme);
    await page.goto('/');
    await expect(page.getByRole('heading', { name: content.welcome.headline.replace('\n', ' ') })).toBeVisible();
    const prefix = `/tmp/danarapi-brand-qa/${info.project.name}-${theme}-${width}`;
    const expectedCanvas = theme === 'light' ? 'rgb(251, 252, 251)' : 'rgb(10, 22, 36)';
    expect(await page.locator('body').evaluate(element => getComputedStyle(element).backgroundColor)).toBe(expectedCanvas);
    await expect(page.locator(`.auth-story .brand-logo.brand-${theme}`)).toBeVisible();
    await expect(page.locator(`.auth-story .brand-wordmark.brand-${theme}`)).toBeVisible();
    const assertImages = async () => {
      for (const image of await page.locator('img:visible').all()) {
        await expect(image).toHaveJSProperty('complete', true);
        expect(await image.evaluate(element => (element as HTMLImageElement).naturalWidth)).toBeGreaterThan(0);
      }
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
    };
    await assertImages();
    await page.screenshot({ path: `${prefix}-login.png`, fullPage: true });
    expect((await new AxeBuilder({ page }).include('.auth-screen').analyze()).violations).toEqual([]);
    if (width === 320) {
      await page.evaluate(() => { document.documentElement.style.fontSize = '200%'; });
      await assertImages();
      await page.screenshot({ path: `${prefix}-login-text200.png`, fullPage: true });
      await page.evaluate(() => { document.documentElement.style.fontSize = ''; });
    }
    await page.getByRole('button', { name: 'Coba Demo', exact: true }).click();
    const tour = page.getByRole('dialog');
    for (const [index, step] of content.onboarding.entries()) {
      await expect(tour.getByRole('heading', { name: step.title, exact: true })).toBeVisible();
      await expect(tour.locator(`.brand-artwork .brand-${theme}`)).toHaveAttribute('src', `/brand/danarapi/${step.image}-${theme}.webp`);
      await expect(tour).toContainText(step.description);
      await expect(tour.locator('[data-initial-focus]')).toBeFocused();
      await assertImages();
      expect((await new AxeBuilder({ page }).include('dialog').analyze()).violations).toEqual([]);
      await page.screenshot({ path: `${prefix}-${step.image}.png` });
      if (width === 320) {
        await page.evaluate(() => { document.documentElement.style.fontSize = '200%'; });
        await assertImages();
        expect(await tour.evaluate(element => element.scrollWidth <= element.clientWidth + 1)).toBe(true);
        await page.screenshot({ path: `${prefix}-${step.image}-text200.png` });
        await page.evaluate(() => { document.documentElement.style.fontSize = ''; });
      }
      if (index === 1) {
        await tour.getByRole('button', { name: 'Kembali', exact: true }).click();
        await expect(tour.getByRole('heading', { name: content.onboarding[0]!.title })).toBeVisible();
        await tour.getByRole('button', { name: 'Lanjut', exact: true }).click();
      }
      await tour.getByRole('button', { name: index === content.onboarding.length - 1 ? 'Mulai mencatat' : 'Lanjut', exact: true }).click();
    }
    await expect(tour).toHaveCount(0);
    await expect(page.getByRole('heading', { name: 'Ringkasan keuangan', exact: true })).toBeVisible();
    await assertImages();
    await page.screenshot({ path: `${prefix}-home.png`, fullPage: true });
  });
}
