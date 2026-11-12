import { describe, expect, it } from 'vitest';
import { describeOtpError, readAuthErrorFromHash } from './authErrors';

describe('describeOtpError', () => {
  it('explains an unrecognized email when sign-ups are disabled', () => {
    const msg = describeOtpError({ message: 'Signups not allowed for otp', code: 'otp_disabled', status: 422 });
    expect(msg).toMatch(/isn’t recognized/);
  });
  it('explains rate limits', () => {
    expect(describeOtpError({ message: 'x', status: 429 })).toMatch(/Too many/);
  });
  it('falls back to the server message', () => {
    expect(describeOtpError({ message: 'Something odd' })).toBe('Something odd');
  });
});

describe('readAuthErrorFromHash', () => {
  it('reads expired-link errors', () => {
    expect(readAuthErrorFromHash('#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid')).toMatch(
      /expired/,
    );
  });
  it('ignores normal hashes', () => {
    expect(readAuthErrorFromHash('')).toBeNull();
    expect(readAuthErrorFromHash('#access_token=abc')).toBeNull();
  });
});
