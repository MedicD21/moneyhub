/** Turn a Supabase Auth OTP error into a message for the sign-in screen. */
export function describeOtpError(error: { message?: string; code?: string; status?: number }): string {
  const message = (error.message ?? '').toLowerCase();
  const code = error.code ?? '';

  // shouldCreateUser:false + unknown email -> "Signups not allowed for otp" (code otp_disabled, 422).
  if (
    code === 'otp_disabled' ||
    code === 'user_not_found' ||
    code === 'signup_disabled' ||
    message.includes('signups not allowed') ||
    message.includes('user not found') ||
    message.includes('signup is disabled')
  ) {
    return 'That email isn’t recognized. Money Hub is private and sign-ups are turned off; use the email address of the owner account.';
  }
  if (code === 'over_email_send_rate_limit' || code === 'over_request_rate_limit' || error.status === 429) {
    return 'Too many sign-in emails were requested. Wait a minute, then try again.';
  }
  if (code === 'email_address_invalid' || message.includes('invalid') && message.includes('email')) {
    return 'That doesn’t look like a valid email address.';
  }
  return error.message || 'Could not send the sign-in link. Try again.';
}

/**
 * Supabase appends `#error=...&error_code=...&error_description=...` to the
 * redirect URL when a magic link is expired or already used.
 */
export function readAuthErrorFromHash(hash: string): string | null {
  if (!hash || hash.length < 2) return null;
  const params = new URLSearchParams(hash.replace(/^#/, ''));
  const code = params.get('error_code');
  const description = params.get('error_description');
  if (!params.get('error') && !code) return null;
  if (code === 'otp_expired') return 'That sign-in link has expired or was already used. Request a new one.';
  return description ? description.replace(/\+/g, ' ') : 'Sign-in failed. Request a new link.';
}
