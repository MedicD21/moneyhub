import js from '@eslint/js';
import globals from 'globals';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist', 'node_modules', 'coverage'] },
  {
    files: ['**/*.{ts,tsx}'],
    extends: [js.configs.recommended, ...tseslint.configs.recommendedTypeChecked],
    languageOptions: {
      ecmaVersion: 2023,
      globals: { ...globals.browser },
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    plugins: {
      'react-hooks': reactHooks,
      'react-refresh': reactRefresh,
    },
    rules: {
      ...reactHooks.configs.flat.recommended.rules,
      'react-refresh/only-export-components': ['warn', { allowConstantExport: true }],
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      // Hard rule: this app is read-only. Forbid the write methods at lint time too.
      'no-restricted-syntax': [
        'error',
        {
          selector:
            "CallExpression[callee.property.name=/^(insert|update|upsert|delete|rpc)$/]",
          message: 'Money Hub web is read-only: no insert/update/upsert/delete/rpc calls.',
        },
      ],
    },
  },
  {
    files: ['tests/**/*.ts', 'vite.config.ts'],
    languageOptions: { globals: { ...globals.node } },
  },
);
