import { expect, test } from '@playwright/test';
import { cloudProject } from '../src/cloud.ts';
import AxeBuilder from '@axe-core/playwright';

test('Google-only login retains its official logo and readable pill on mobile and desktop', async ({ page, browserName }) => {
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'Lanjutkan dengan Google' })).toBeVisible();
  await page.evaluate(async () => {
    await document.fonts.load('500 14px "Google Sans Sign In"');
    await document.fonts.ready;
  });
  for (const theme of ['light', 'dark']) {
    await page.evaluate(value => { document.documentElement.dataset.theme = value; }, theme);
    for (const width of [320, 375, 1280]) {
      await page.setViewportSize({ width, height: 900 });
      const google = page.getByRole('button', { name: 'Lanjutkan dengan Google' });
      const googleBox = (await google.boundingBox())!;
      await expect(page.locator('.provider-sign-in')).toHaveCount(1);
      await expect(page.getByRole('button', { name: /Apple/ })).toHaveCount(0);
      expect(googleBox.height).toBeGreaterThanOrEqual(56);
      expect(await google.locator('img').getAttribute('src')).toBe('/brand/google-sign-in.png');
      for (const button of [google]) {
        expect(await button.locator('.provider-label').evaluate(label => label.scrollWidth <= label.clientWidth)).toBe(true);
        expect(await button.locator('img').evaluate(image => (image as HTMLImageElement).complete && (image as HTMLImageElement).naturalWidth > 0)).toBe(true);
        expect(await button.evaluate(element => getComputedStyle(element).backgroundColor)).toBe('rgb(255, 255, 255)');
      }
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    }
  }
  await page.setViewportSize({ width: 375, height: 900 });
  await page.getByRole('button', { name: 'Lanjutkan dengan Google' }).focus();
  await page.keyboard.press(browserName === 'webkit' ? 'Alt+Tab' : 'Tab');
  await expect(page.getByRole('button', { name: 'Coba Demo' })).toBeFocused();
  expect((await new AxeBuilder({ page }).include('.auth-card').analyze()).violations).toEqual([]);
  await test.info().attach('Login provider web dark', { body: await page.screenshot({ fullPage: true }), contentType: 'image/png' });
});

test('disabled cloud providers show clear errors without leaving the login screen', async ({ page }) => {
  await page.route('**/auth/v1/settings', async route => {
    expect(route.request().headers().apikey).toBe(cloudProject.key);
    expect(route.request().headers().authorization).toBeUndefined();
    await route.fulfill({ json: { external: { google: false, apple: false } } });
  });
  await page.goto('/');
  for (const provider of ['Google']) {
    await page.getByRole('button', { name: `Lanjutkan dengan ${provider}` }).click();
    await expect(page.getByRole('alert')).toContainText(`Login ${provider} belum diaktifkan`);
    await expect(page.getByRole('button', { name: `Lanjutkan dengan ${provider}` })).toBeEnabled();
    expect(new URL(page.url()).host).not.toBe(new URL(cloudProject.url).host);
  }
});

test('enabled Google starts PKCE with the application callback', async ({ page }) => {
  await page.route('**/auth/v1/settings', route => route.fulfill({ json: { external: { google: true } } }));
  await page.route('**/auth/v1/authorize?**', async route => {
    const url = new URL(route.request().url());
    expect(url.searchParams.get('provider')).toBe('google');
    expect(url.searchParams.get('prompt')).toBe('select_account');
    expect(url.searchParams.get('code_challenge_method')).toBe('s256');
    expect(url.searchParams.get('code_challenge')).toBeTruthy();
    expect(url.searchParams.get('redirect_to')).toBe(new URL('/', test.info().project.use.baseURL).href);
    await route.fulfill({ contentType: 'text/html', body: '<main>OAuth testing</main>' });
  });
  await page.goto('/');
  await page.getByRole('button', { name: 'Lanjutkan dengan Google' }).click();
  await expect(page.getByText('OAuth testing')).toBeVisible();
});

test('unavailable Auth service leaves login and demo usable', async ({ page }) => {
  await page.route('**/auth/v1/settings', route => route.fulfill({ status: 503, json: { message: 'unavailable' } }));
  await page.goto('/');
  await page.getByRole('button', { name: 'Lanjutkan dengan Google' }).click();
  await expect(page.getByRole('alert')).toContainText('Layanan login belum tersedia');
  await expect(page.getByRole('button', { name: 'Lanjutkan dengan Google' })).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Coba Demo' })).toBeEnabled();
});
