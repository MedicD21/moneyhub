import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '../lib/supabase';
import { describeOtpError, readAuthErrorFromHash } from '../lib/authErrors';
import { Banner, Button, Field, inputClass } from '../components/ui';
import { Icon } from '../components/Icon';

type Status = { kind: 'idle' } | { kind: 'sending' } | { kind: 'sent'; email: string } | { kind: 'error'; message: string };

export default function Login() {
  const [email, setEmail] = useState('');
  const [status, setStatus] = useState<Status>(() => {
    const fromHash = readAuthErrorFromHash(window.location.hash);
    return fromHash ? { kind: 'error', message: fromHash } : { kind: 'idle' };
  });

  // Drop a stale #error=... from the address bar once it has been read.
  useEffect(() => {
    if (readAuthErrorFromHash(window.location.hash)) {
      window.history.replaceState(null, '', window.location.pathname + window.location.search);
    }
  }, []);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (!supabase) return;
    const address = email.trim();
    if (!address) return;
    setStatus({ kind: 'sending' });
    try {
      const { error } = await supabase.auth.signInWithOtp({
        email: address,
        options: { shouldCreateUser: false, emailRedirectTo: window.location.origin },
      });
      setStatus(error ? { kind: 'error', message: describeOtpError(error) } : { kind: 'sent', email: address });
    } catch {
      setStatus({ kind: 'error', message: 'Network error: could not reach Supabase. Check your connection and try again.' });
    }
  }

  return (
    <div className="grid min-h-dvh place-items-center bg-bg px-4 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-6 flex items-center gap-2">
          <span className="grid h-10 w-10 place-items-center rounded-xl bg-accent text-accent-ink" aria-hidden="true">
            <svg viewBox="0 0 32 32" width="24" height="24">
              <path d="M9 21V11l7 6 7-6v10" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
          <h1 className="text-xl font-semibold tracking-tight text-ink">Money Hub</h1>
        </div>

        <div className="rounded-2xl border border-line bg-surface p-5 sm:p-6">
          {status.kind === 'sent' ? (
            <div role="status" className="space-y-3">
              <div className="flex items-center gap-2 font-semibold text-ink">
                <Icon name="mail" size={20} /> Check your email
              </div>
              <p className="text-sm text-muted">
                We sent a sign-in link to <span className="font-medium text-ink">{status.email}</span>. Open it on this device to
                continue. You can close this tab once you’re signed in.
              </p>
              <Button variant="ghost" onClick={() => setStatus({ kind: 'idle' })}>
                Use a different email
              </Button>
            </div>
          ) : (
            <form onSubmit={(e) => void onSubmit(e)} className="space-y-4" noValidate>
              <div>
                <h2 className="text-base font-semibold text-ink">Sign in</h2>
                <p className="mt-1 text-sm text-muted">We’ll email you a one-time sign-in link.</p>
              </div>
              <Field label="Email">
                <input
                  type="email"
                  autoComplete="email"
                  inputMode="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className={inputClass}
                  placeholder="you@example.com"
                />
              </Field>
              {status.kind === 'error' ? (
                <Banner tone="danger" title="Couldn’t send the link">
                  {status.message}
                </Banner>
              ) : null}
              <Button type="submit" variant="primary" disabled={status.kind === 'sending' || !email.trim()} className="w-full">
                {status.kind === 'sending' ? 'Sending…' : 'Email me a sign-in link'}
              </Button>
            </form>
          )}
        </div>
        <p className="mt-4 text-center text-xs text-muted">Read-only view of your Money Hub data.</p>
      </div>
    </div>
  );
}
