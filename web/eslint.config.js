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
      // Hard rule: tables are never written from the browser. The only write path is a fixed set of
      // owner-checked RPCs, and `.rpc(` is allowed only in src/lib/writes.ts (the nine writes) and
      // src/lib/reads.ts (the one read-only simulator), see overrides below.
      'no-restricted-syntax': [
        'error',
        {
          selector: "CallExpression[callee.property.name=/^(insert|update|upsert|delete)$/]",
          message: 'Money Hub web never writes tables directly: no insert/update/upsert/delete calls.',
        },
        {
          selector: "CallExpression[callee.property.name='rpc']",
          message: 'Call database functions only through src/lib/writes.ts (writes) or src/lib/reads.ts (read-only simulation).',
        },
      ],
    },
  },
  {
    files: ['src/lib/writes.ts'],
    rules: {
      'no-restricted-syntax': [
        'error',
        {
          selector: "CallExpression[callee.property.name=/^(insert|update|upsert|delete)$/]",
          message: 'Money Hub web never writes tables directly: no insert/update/upsert/delete calls.',
        },
      ],
    },
  },
  {
    files: ['src/lib/reads.ts'],
    rules: {
      'no-restricted-syntax': [
        'error',
        {
          selector: "CallExpression[callee.property.name=/^(insert|update|upsert|delete)$/]",
          message: 'Money Hub web never writes tables directly: no insert/update/upsert/delete calls.',
        },
      ],
    },
  },
  {
    files: ['tests/**/*.ts', 'vite.config.ts'],
    languageOptions: { globals: { ...globals.node } },
  },
);
