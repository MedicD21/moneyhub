/** Turn a Supabase Auth sign-in error into a message for the sign-in screen. */
export function describeSignInError(error: { message?: string; code?: string; status?: number }): string {
  const message = (error.message ?? '').toLowerCase();
  const code = error.code ?? '';

  // Wrong password and unknown email both come back as invalid_credentials (400),
  // deliberately indistinguishable so the form doesn't reveal which emails exist.
  if (code === 'invalid_credentials' || message.includes('invalid login credentials')) {
    return 'Email or password is incorrect.';
  }
  if (code === 'email_not_confirmed' || message.includes('email not confirmed')) {
    return 'This account isn’t confirmed yet. Confirm the user in the Supabase dashboard (Authentication → Users).';
  }
  if (code === 'over_request_rate_limit' || error.status === 429) {
    return 'Too many sign-in attempts. Wait a minute, then try again.';
  }
  if (code === 'email_provider_disabled' || message.includes('email logins are disabled')) {
    return 'Email sign-in is turned off for this project. Enable the Email provider in Supabase (Authentication → Sign In / Providers).';
  }
  return error.message || 'Could not sign in. Try again.';
}
