import { createApp } from 'vue';
import App from './App.vue';
import tokens from '../../../contracts/design-tokens.json';
import './style.css';
import './tokens.css';
import './planning.css';
import './interface.css';

for (const [theme, values] of Object.entries(tokens.color)) {
  const style = document.createElement('style');
  style.textContent = `:root${theme === 'dark' ? '[data-theme="dark"]' : ''}{${Object.entries(values).map(([name, value]) => `--${name}:${value}`).join(';')}}`;
  document.head.append(style);
}
const root = document.documentElement;
for (const [name, value] of Object.entries(tokens.radius)) root.style.setProperty(`--radius-${name}`, `${value}px`);
for (const [name, value] of Object.entries(tokens.space)) root.style.setProperty(`--space-${name}`, `${value}px`);
for (const [name, value] of Object.entries(tokens.typography.size)) root.style.setProperty(`--font-${name}`, `${value / 16}rem`);
root.style.setProperty('--control', 'var(--radius-button)');
root.style.setProperty('--card', 'var(--radius-card)');
root.style.setProperty('--font-family', tokens.typography.webFamily);
root.style.setProperty('--body-line-height', String(tokens.typography.bodyLineHeight));
root.style.setProperty('--title-line-height', String(tokens.typography.titleLineHeight));
root.style.setProperty('--touch-minimum', `${tokens.touchTarget.minimum}px`);
root.style.setProperty('--motion-fast', `${tokens.motion.fastMs}ms`);
root.style.setProperty('--motion-normal', `${tokens.motion.normalMs}ms`);
root.style.setProperty('--priority-shadow', tokens.shadow.priority);
for (const [name, value] of Object.entries(tokens.layout)) root.style.setProperty(`--layout-${name}`, `${value}px`);
createApp(App).mount('#app');
