import js from '@eslint/js';
import ts from 'typescript-eslint';
import vue from 'eslint-plugin-vue';

export default ts.config(js.configs.recommended, ...ts.configs.recommended, ...vue.configs['flat/recommended'], {
  files: ['**/*.vue'], languageOptions: { parserOptions: { parser: ts.parser } },
}, {
  files: ['**/*.ts', '**/*.vue'], rules: { 'no-undef': 'off' },
}, {
  languageOptions: { globals: { document: 'readonly', window: 'readonly', navigator: 'readonly', localStorage: 'readonly', sessionStorage: 'readonly', matchMedia: 'readonly', crypto: 'readonly', fetch: 'readonly', Blob: 'readonly', URL: 'readonly', File: 'readonly', HTMLInputElement: 'readonly', HTMLDialogElement: 'readonly', HTMLElement: 'readonly', HTMLTextAreaElement: 'readonly', HTMLSelectElement: 'readonly', setTimeout: 'readonly', clearTimeout: 'readonly', TextEncoder: 'readonly', TextDecoder: 'readonly', Image: 'readonly', Uint8ClampedArray: 'readonly', console: 'readonly', Event: 'readonly', KeyboardEvent: 'readonly', ResizeObserver: 'readonly', FileReader: 'readonly', location: 'readonly', history: 'readonly', AbortController: 'readonly' } },
  rules: { 'vue/multi-word-component-names': 'off', 'vue/max-attributes-per-line': 'off', 'vue/singleline-html-element-content-newline': 'off', 'vue/html-self-closing': 'off', 'vue/html-indent': 'off', 'vue/html-closing-bracket-newline': 'off', '@typescript-eslint/no-explicit-any': 'off' },
});
