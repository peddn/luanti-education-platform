import js from '@eslint/js'
import vueI18n from '@intlify/eslint-plugin-vue-i18n'
import vue from 'eslint-plugin-vue'
import globals from 'globals'

export default [
  { ignores: ['dist/', 'src/api/schema.d.ts'] },
  js.configs.recommended,
  ...vue.configs['flat/recommended'],
  ...vueI18n.configs['flat/recommended'],
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: { ...globals.browser },
    },
    settings: {
      'vue-i18n': {
        localeDir: './src/locales/*.json',
        messageSyntaxVersion: '^11.0.0',
      },
    },
    rules: {
      // No text stands in a page. Everything comes from the language files.
      '@intlify/vue-i18n/no-raw-text': 'error',
      '@intlify/vue-i18n/no-missing-keys': 'error',
      '@intlify/vue-i18n/no-unused-keys': [
        'error',
        // Keys the code builds at run time, from codes of the backend.
        { extensions: ['.js', '.vue'], ignores: ['/^errors\\./', '/^health\\.status\\./', '/^health\\.mail\\./', '/^students\\.states\\./', '/^students\\.password\\./', '/^progress\\.change\\./', '/^yearEnd\\.worldStates\\./', '/^protocols\\.(tabs|periods|columns|values)\\./', '/^students\\.displayChange\\./', '/^students\\.removalRefusals\\./', '/^students\\.historyActions\\./', '/^progress\\.materials\\./', '/^languages\\./', '/^nav\\./'] },
      ],
      // The formatting of the templates is not a matter of the linter.
      'vue/max-attributes-per-line': 'off',
      'vue/singleline-html-element-content-newline': 'off',
      'vue/html-self-closing': 'off',
    },
  },
  {
    files: ['vite.config.js', 'eslint.config.js'],
    languageOptions: { globals: { ...globals.node } },
  },
]
