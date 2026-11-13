import { describe, expect, it } from 'vitest';
import { amountToInputText, centsToDollars, parseAmountCents, parseCentsAllowZero, sanitizeAmountInput, signedDollars } from './money';

describe('sanitizeAmountInput', () => {
  it('keeps digits and one decimal point', () => {
    expect(sanitizeAmountInput('12.34')).toBe('12.34');
    expect(sanitizeAmountInput('1a2b.3c4')).toBe('12.34');
    expect(sanitizeAmountInput('$ 5')).toBe('5');
  });
  it('limits to two decimals and one point', () => {
    expect(sanitizeAmountInput('1.234')).toBe('1.23');
    expect(sanitizeAmountInput('1.2.3')).toBe('1.23');
    expect(sanitizeAmountInput('1..5')).toBe('1.5');
  });
  it('treats a comma as the decimal point', () => {
    expect(sanitizeAmountInput('12,5')).toBe('12.5');
  });
  it('drops leading zeros but keeps a lone zero and "0."', () => {
    expect(sanitizeAmountInput('007')).toBe('7');
    expect(sanitizeAmountInput('0')).toBe('0');
    expect(sanitizeAmountInput('0.')).toBe('0.');
    expect(sanitizeAmountInput('00.5')).toBe('0.5');
  });
  it('allows a leading point and caps the whole part at 9 digits', () => {
    expect(sanitizeAmountInput('.5')).toBe('.5');
    expect(sanitizeAmountInput('1234567890123')).toBe('123456789');
  });
  it('empties on junk', () => {
    expect(sanitizeAmountInput('abc')).toBe('');
    expect(sanitizeAmountInput('-')).toBe('');
  });
});

describe('parseAmountCents', () => {
  it('parses whole dollars, cents and partial decimals', () => {
    expect(parseAmountCents('12')).toBe(1200);
    expect(parseAmountCents('12.3')).toBe(1230);
    expect(parseAmountCents('12.34')).toBe(1234);
    expect(parseAmountCents('0.05')).toBe(5);
    expect(parseAmountCents('.5')).toBe(50);
    expect(parseAmountCents('7.')).toBe(700);
  });
  it('rejects empty, zero and malformed input', () => {
    for (const bad of ['', ' ', '.', '0', '0.00', '-5', '1.234', '1,5', 'abc', '1e3']) {
      expect(parseAmountCents(bad), bad).toBeNull();
    }
  });
  it('is exact where floating point is not (0.1 + 0.2 style values)', () => {
    expect(parseAmountCents('1.15')).toBe(115);
    expect(parseAmountCents('4.35')).toBe(435);
    expect(parseAmountCents('1000000.01')).toBe(100000001);
  });
});

describe('signedDollars', () => {
  it('is negative for expenses and positive for income', () => {
    expect(signedDollars(1234, 'expense')).toBe(-12.34);
    expect(signedDollars(1234, 'income')).toBe(12.34);
    expect(signedDollars(5, 'expense')).toBe(-0.05);
  });
  it('round-trips every cent value to two decimals', () => {
    for (const cents of [1, 7, 10, 99, 101, 115, 435, 1005, 99999, 123456]) {
      expect(Math.round(signedDollars(cents, 'income') * 100)).toBe(cents);
      expect(Number(signedDollars(cents, 'income').toFixed(2))).toBe(signedDollars(cents, 'income'));
    }
  });
});

describe('amountToInputText', () => {
  it('shows the magnitude with two decimals', () => {
    expect(amountToInputText(-15)).toBe('15.00');
    expect(amountToInputText(250)).toBe('250.00');
    expect(amountToInputText(-0.5)).toBe('0.50');
    expect(amountToInputText(-12.34)).toBe('12.34');
  });
});

describe('parseCentsAllowZero', () => {
  it('accepts zero, unlike parseAmountCents', () => {
    expect(parseCentsAllowZero('0')).toBe(0);
    expect(parseCentsAllowZero('0.00')).toBe(0);
    expect(parseAmountCents('0')).toBeNull();
  });
  it('parses the same shapes as parseAmountCents', () => {
    expect(parseCentsAllowZero('12.3')).toBe(1230);
    expect(parseCentsAllowZero('.5')).toBe(50);
  });
  it('rejects empty and malformed text', () => {
    expect(parseCentsAllowZero('')).toBeNull();
    expect(parseCentsAllowZero('.')).toBeNull();
    expect(parseCentsAllowZero('1.234')).toBeNull();
    expect(parseCentsAllowZero('-1')).toBeNull();
  });
});

describe('centsToDollars', () => {
  it('converts integer cents to the dollar number sent to the database', () => {
    expect(centsToDollars(1230)).toBe(12.3);
    expect(centsToDollars(0)).toBe(0);
  });
});
