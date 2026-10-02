import catalog from '../../../contracts/product-content.json';

export const welcomeContent = catalog.welcome;
export const onboardingContent = catalog.onboarding;
export function brandAsset(name: string, theme: 'light' | 'dark') {
  return `/brand/danarapi/${name}-${theme}.webp`;
}
