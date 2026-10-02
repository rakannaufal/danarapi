import { expect, test } from '@playwright/test';
import content from '../../../contracts/product-content.json' with { type: 'json' };

test('demo onboarding can be completed and appears on the next demo entry', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Coba Demo', exact: true }).click();
  const tour = page.getByRole('dialog');
  await expect(tour.getByRole('heading', { name: content.onboarding[0]!.title })).toBeVisible();
  await tour.getByRole('button', { name: 'Lanjut', exact: true }).click();
  await expect(tour.getByRole('heading', { name: content.onboarding[1]!.title })).toBeVisible();
  await tour.getByRole('button', { name: 'Lanjut', exact: true }).click();
  await tour.getByRole('button', { name: 'Mulai mencatat' }).click();
  await expect(tour).toHaveCount(0);
  expect(await page.evaluate(() => Object.keys(localStorage).filter(key => key.startsWith('danarapi.onboarding.')))).toEqual([]);
  await page.reload();
  await page.getByRole('button', { name: 'Coba Demo', exact: true }).click();
  await expect(tour.getByRole('heading', { name: content.onboarding[0]!.title })).toBeVisible();
  await tour.getByRole('button', { name: 'Lewati tur' }).click();
  await expect(tour).toHaveCount(0);
});
