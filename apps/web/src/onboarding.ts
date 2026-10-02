export function onboardingKey(userID: string) { return `danarapi.onboarding.${userID}`; }
export function hasCompletedOnboarding(storage: Pick<Storage, 'getItem'>, userID: string) {
  return storage.getItem(onboardingKey(userID)) === 'true';
}
export function saveOnboardingCompletion(storage: Pick<Storage, 'setItem'>, userID: string) {
  storage.setItem(onboardingKey(userID), 'true');
}
