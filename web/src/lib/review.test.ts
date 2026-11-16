import { describe, expect, it } from 'vitest';
import type { CategoryRow } from '../types/db';
import { isBankLocked, patternMatches, rankCategories, suggestRulePattern } from './review';

function cat(id: string, name: string, kind: CategoryRow['kind'] = 'expense'): CategoryRow {
  return { id, owner_id: 'o', name, parent_name: null, kind, created_at: '', updated_at: '' };
}

describe('isBankLocked', () => {
  it('locks imported and reconciled rows, not open manual ones', () => {
    expect(isBankLocked({ entry_source: 'import', reconciled: false })).toBe(true);
    expect(isBankLocked({ entry_source: 'manual', reconciled: true })).toBe(true);
    expect(isBankLocked({ entry_source: 'manual', reconciled: false })).toBe(false);
  });
});

describe('suggestRulePattern', () => {
  it('uses the merchant when the description contains it', () => {
    expect(suggestRulePattern('Kroger', 'KROGER #123 CINCINNATI')).toBe('Kroger');
  });
  it('falls back to the description without a trailing ellipsis when the name was truncated', () => {
    expect(suggestRulePattern("Baker's Village Garden Center & Gift Shop", "Baker's Village Garden Center & Gift Sh...")).toBe(
      "Baker's Village Garden Center & Gift Sh",
    );
    expect(suggestRulePattern(null, 'HOME CHEF…')).toBe('HOME CHEF');
  });
  it('keeps the merchant when there is no usable description', () => {
    expect(suggestRulePattern('Apple', '...')).toBe('Apple');
  });
});

describe('patternMatches', () => {
  it('is a trimmed, case-insensitive substring test', () => {
    expect(patternMatches(' kroger ', 'KROGER #1')).toBe(true);
    expect(patternMatches('aldi', 'KROGER #1')).toBe(false);
    expect(patternMatches('  ', 'KROGER')).toBe(false);
  });
});

describe('rankCategories', () => {
  const cats = [cat('g', 'Groceries'), cat('d', 'Dining'), cat('s', 'Shopping'), cat('i', 'Income', 'income')];

  it('puts the most used first and the rest by name', () => {
    const { frequent, rest } = rankCategories(cats, ['d', 'g', 'g', null, 'g', 'd', 'x'], true);
    expect(frequent.map((c) => c.id)).toEqual(['g', 'd']);
    expect(rest.map((c) => c.id)).toEqual(['i', 's']);
  });
  it('leaves income categories out for money going out', () => {
    const { frequent, rest } = rankCategories(cats, ['i', 'i'], false);
    expect([...frequent, ...rest].map((c) => c.id)).not.toContain('i');
  });
  it('caps the frequent row at six', () => {
    const many = Array.from({ length: 9 }, (_, n) => cat(`c${n}`, `Cat ${n}`));
    const { frequent, rest } = rankCategories(many, many.map((c) => c.id), false);
    expect(frequent).toHaveLength(6);
    expect(rest).toHaveLength(3);
  });
});
