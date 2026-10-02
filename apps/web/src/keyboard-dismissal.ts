const editableSelector = 'input, textarea, select, [contenteditable]:not([contenteditable="false"]), [role="textbox"]';
const preserveFocusSelector = `${editableSelector}, label, [data-keep-keyboard]`;

export function installKeyboardDismissal(document: Document): () => void {
  const dismiss = (event: PointerEvent) => {
    if (event.button !== 0 || !event.isPrimary) return;
    const active = document.activeElement;
    if (!active?.matches(editableSelector) || !('blur' in active)) return;
    if (event.composedPath().some(target => target instanceof Element && target.closest(preserveFocusSelector))) return;
    (active as HTMLElement).blur();
  };
  document.addEventListener('pointerdown', dismiss, true);
  return () => document.removeEventListener('pointerdown', dismiss, true);
}
