import { useState, type FormEvent } from 'react';
import { supabase } from '../lib/supabase';
import { describeSignInError } from '../lib/authErrors';
import { Banner, Button, Field, inputClass } from '../components/ui';

type Status = { kind: 'idle' } | { kind: 'signing-in' } | { kind: 'error'; message: string };

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [status, setStatus] = useState<Status>({ kind: 'idle' });

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (!supabase) return;
    const address = email.trim();
    if (!address || !password) return;
    setStatus({ kind: 'signing-in' });
    try {
      // On success the auth listener (useAuth) swaps this screen for the app.
      const { error } = await supabase.auth.signInWithPassword({ email: address, password });
      if (error) setStatus({ kind: 'error', message: describeSignInError(error) });
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
          <form onSubmit={(e) => void onSubmit(e)} className="space-y-4" noValidate>
            <h2 className="text-base font-semibold text-ink">Sign in</h2>
            <Field label="Email">
              <input
                type="email"
                autoComplete="username"
                inputMode="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className={inputClass}
                placeholder="you@example.com"
              />
            </Field>
            <Field label="Password">
              <input
                type="password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className={inputClass}
              />
            </Field>
            {status.kind === 'error' ? (
              <Banner tone="danger" title="Couldn’t sign in">
                {status.message}
              </Banner>
            ) : null}
            <Button
              type="submit"
              variant="primary"
              disabled={status.kind === 'signing-in' || !email.trim() || !password}
              className="w-full"
            >
              {status.kind === 'signing-in' ? 'Signing in…' : 'Sign in'}
            </Button>
          </form>
        </div>
        <p className="mt-4 text-center text-xs text-muted">Private to the Money Hub owner.</p>
      </div>
    </div>
  );
}
