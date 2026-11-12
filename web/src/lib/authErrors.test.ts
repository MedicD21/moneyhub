import { describe, expect, it } from 'vitest';
import { describeSignInError } from './authErrors';

describe('describeSignInError', () => {
  it('gives one message for a wrong password or unknown email', () => {
    expect(describeSignInError({ message: 'Invalid login credentials', code: 'invalid_credentials', status: 400 })).toBe(
      'Email or password is incorrect.',
    );
  });
  it('explains an unconfirmed user', () => {
    expect(describeSignInError({ message: 'Email not confirmed', code: 'email_not_confirmed' })).toMatch(/isn’t confirmed/);
  });
  it('explains rate limits', () => {
    expect(describeSignInError({ message: 'x', status: 429 })).toMatch(/Too many/);
  });
  it('explains a disabled email provider', () => {
    expect(describeSignInError({ message: 'Email logins are disabled', code: 'email_provider_disabled' })).toMatch(/turned off/);
  });
  it('falls back to the server message', () => {
    expect(describeSignInError({ message: 'Something odd' })).toBe('Something odd');
  });
});
