import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  addDays,
  addMonths,
  dayNumberToIso,
  daysInMonth,
  formatCurrency,
  formatCurrencyWhole,
  formatDate,
  formatDateRange,
  formatMonth,
  formatPercent,
  formatRelativeDays,
  humanize,
  isMonthStart,
  isoToDayNumber,
  monthStart,
  moneyTone,
  parseIsoDate,
  todayLocal,
  weekdayOf,
} from './format';

describe('formatCurrency', () => {
  it('formats positive amounts as USD', () => {
    expect(formatCurrency(1234.56)).toBe('$1,234.56');
    expect(formatCurrency(0.5)).toBe('$0.50');
  });

  it('formats negative amounts with a leading minus', () => {
    expect(formatCurrency(-1234.56)).toBe('-$1,234.56');
    expect(formatCurrency(-0.01)).toBe('-$0.01');
  });

  it('formats zero and negative zero without a sign', () => {
    expect(formatCurrency(0)).toBe('$0.00');
    expect(formatCurrency(-0)).toBe('$0.00');
  });

  it('renders missing values as an em dash', () => {
    expect(formatCurrency(null)).toBe('—');
    expect(formatCurrency(undefined)).toBe('—');
    expect(formatCurrency(Number.NaN)).toBe('—');
  });

  it('formats whole dollars', () => {
    expect(formatCurrencyWhole(-1499.6)).toBe('-$1,500');
  });
});

describe('moneyTone', () => {
  it('maps sign convention to tone (negative = money out)', () => {
    expect(moneyTone(-5)).toBe('out');
    expect(moneyTone(5)).toBe('in');
    expect(moneyTone(0)).toBe('zero');
    expect(moneyTone(null)).toBe('zero');
  });
});

describe('dates without timezone shift', () => {
  const originalTz = process.env.TZ;
  afterEach(() => {
    process.env.TZ = originalTz;
  });

  for (const tz of ['America/Los_Angeles', 'America/New_York', 'UTC', 'Pacific/Kiritimati', 'Pacific/Pago_Pago']) {
    describe(`in ${tz}`, () => {
      beforeEach(() => {
        process.env.TZ = tz;
      });

      it('formats 2026-03-05 as Mar 5, 2026', () => {
        expect(formatDate('2026-03-05')).toBe('Mar 5, 2026');
        expect(formatDate('2026-03-05', 'short')).toBe('Mar 5');
        expect(formatDate('2026-03-05', 'weekday')).toBe('Thu, Mar 5');
      });

      it('formats a first-of-month date as that month', () => {
        expect(formatMonth('2026-03-01')).toBe('March 2026');
        expect(formatMonth('2026-01-01', 'short')).toBe('Jan ’26');
        expect(formatMonth('2009-12-01', 'short')).toBe('Dec ’09');
      });

      it('handles year boundaries', () => {
        expect(formatDate('2026-01-01')).toBe('Jan 1, 2026');
        expect(formatDate('2025-12-31')).toBe('Dec 31, 2025');
      });
    });
  }

  it('demonstrates the bug being avoided: new Date(iso) shifts west of UTC', () => {
    process.env.TZ = 'America/Los_Angeles';
    const naive = new Date('2026-03-05').toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    expect(naive).toBe('Mar 4');
    expect(formatDate('2026-03-05', 'short')).toBe('Mar 5');
  });
});

describe('date parsing and arithmetic', () => {
  it('parses ISO dates and the date part of timestamps', () => {
    expect(parseIsoDate('2026-03-05')).toEqual({ year: 2026, month: 3, day: 5 });
    expect(parseIsoDate('2026-03-05T23:59:59+00:00')).toEqual({ year: 2026, month: 3, day: 5 });
  });

  it('rejects invalid dates', () => {
    expect(parseIsoDate('2026-02-30')).toBeNull();
    expect(parseIsoDate('2026-13-01')).toBeNull();
    expect(parseIsoDate('not a date')).toBeNull();
    expect(formatDate('garbage')).toBe('garbage');
    expect(formatDate(null)).toBe('—');
  });

  it('adds days across month and year ends', () => {
    expect(addDays('2026-11-28', 7)).toBe('2026-12-05');
    expect(addDays('2026-12-30', 7)).toBe('2027-01-06');
    expect(addDays('2028-02-28', 1)).toBe('2028-02-29');
    expect(addDays('2026-03-08', 0)).toBe('2026-03-08'); // US DST start
  });

  it('shifts months and normalizes to the 1st', () => {
    expect(addMonths('2026-01-01', -1)).toBe('2025-12-01');
    expect(addMonths('2026-01-31', 1)).toBe('2026-02-01');
    expect(addMonths('2026-11-01', 14)).toBe('2028-01-01');
    expect(monthStart('2026-03-17')).toBe('2026-03-01');
  });

  it('knows month lengths and weekdays', () => {
    expect(daysInMonth(2026, 2)).toBe(28);
    expect(daysInMonth(2028, 2)).toBe(29);
    expect(daysInMonth(2026, 12)).toBe(31);
    expect(weekdayOf('2026-11-01')).toBe(0); // Sunday
    expect(weekdayOf('2026-03-05')).toBe(4); // Thursday
  });

  it('formats ranges', () => {
    expect(formatDateRange('2026-03-05', '2026-03-18')).toBe('Mar 5 – Mar 18, 2026');
    expect(formatDateRange('2025-12-26', '2026-01-08')).toBe('Dec 26, 2025 – Jan 8, 2026');
  });

  it('builds the local date from local parts', () => {
    expect(todayLocal(new Date(2026, 10, 12, 23, 30))).toBe('2026-11-12');
  });

  it('validates month params', () => {
    expect(isMonthStart('2026-03-01')).toBe(true);
    expect(isMonthStart('2026-03-02')).toBe(false);
    expect(isMonthStart('2026-3-01')).toBe(false);
    expect(isMonthStart(null)).toBe(false);
  });
});

describe('misc formatting', () => {
  it('formats percents, relative days and enums', () => {
    expect(formatPercent(24.99)).toBe('24.99%');
    expect(formatPercent(null)).toBe('—');
    expect(formatRelativeDays(0)).toBe('today');
    expect(formatRelativeDays(3)).toBe('in 3 days');
    expect(formatRelativeDays(-2)).toBe('2 days ago');
    expect(humanize('credit_card')).toBe('Credit card');
  });
});

describe('chart day numbers', () => {
  it('round-trips ISO dates through day numbers', () => {
    expect(isoToDayNumber('1970-01-02')).toBe(1);
    expect(dayNumberToIso(isoToDayNumber('2026-03-05'))).toBe('2026-03-05');
    expect(isoToDayNumber('2026-03-09') - isoToDayNumber('2026-03-05')).toBe(4);
  });
});
