import { describe, expect, it } from 'vitest';
import { addHours, draftToEntries, entriesToDraft, parseHours, parseSpend, sameEntries, sanitizeHoursInput } from './planner';

describe('sanitizeHoursInput', () => {
  it('keeps digits, one dot and two decimals', () => {
    expect(sanitizeHoursInput('6.256')).toBe('6.25');
    expect(sanitizeHoursInput('1,5')).toBe('1.5');
    expect(sanitizeHoursInput('abc12')).toBe('12');
    expect(sanitizeHoursInput('0012')).toBe('12');
    expect(sanitizeHoursInput('12345')).toBe('123');
  });
});

describe('parseHours', () => {
  it('reads hours, treats blank as zero and rejects the rest', () => {
    expect(parseHours('')).toBe(0);
    expect(parseHours('6')).toBe(6);
    expect(parseHours('6.5')).toBe(6.5);
    expect(parseHours('120')).toBe(120);
    expect(parseHours('121')).toBeNull();
    expect(parseHours('.')).toBeNull();
    expect(parseHours('-3')).toBeNull();
  });
});

describe('parseSpend', () => {
  it('reads dollars through cents, blank is zero', () => {
    expect(parseSpend('')).toBe(0);
    expect(parseSpend('150')).toBe(150);
    expect(parseSpend('150.50')).toBe(150.5);
    expect(parseSpend('1.005')).toBeNull();
    expect(parseSpend('x')).toBeNull();
  });
});

describe('draftToEntries', () => {
  it('drops zero rows and sorts by date', () => {
    const r = draftToEntries({
      '2026-12-23': { ot: '4', spend: '' },
      '2026-12-09': { ot: '', spend: '100.25' },
      '2027-01-06': { ot: '', spend: '' },
    });
    expect(r.error).toBeNull();
    expect(r.entries).toEqual([
      { pay_date: '2026-12-09', ot_hours: 0, spend: 100.25 },
      { pay_date: '2026-12-23', ot_hours: 4, spend: 0 },
    ]);
  });
  it('reports a value it cannot read', () => {
    expect(draftToEntries({ '2026-12-09': { ot: '999', spend: '' } }).error).toMatch(/Overtime hours/);
    expect(draftToEntries({ '2026-12-09': { ot: '', spend: '1.234' } }).error).toMatch(/Spending/);
  });
});

describe('entriesToDraft / sameEntries', () => {
  it('round-trips and compares ignoring order and zero rows', () => {
    const entries = [
      { pay_date: '2026-12-09', ot_hours: 6, spend: 0 },
      { pay_date: '2026-12-23', ot_hours: 0, spend: 75.5 },
    ];
    expect(draftToEntries(entriesToDraft(entries)).entries).toEqual(entries);
    expect(sameEntries(entries, [...entries].reverse())).toBe(true);
    expect(sameEntries(entries, [...entries, { pay_date: '2027-01-06', ot_hours: 0, spend: 0 }])).toBe(true);
    expect(sameEntries(entries, [{ pay_date: '2026-12-09', ot_hours: 7, spend: 0 }])).toBe(false);
  });
});

describe('addHours', () => {
  it('adds suggested hours to what is typed', () => {
    expect(addHours('', 6)).toBe('6');
    expect(addHours('3', 4)).toBe('7');
    expect(addHours('0.1', 0.2)).toBe('0.3');
    expect(addHours('', 0)).toBe('');
  });
});
