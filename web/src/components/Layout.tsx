import { NavLink, Outlet } from 'react-router-dom';
import { useState } from 'react';
import { useAuth } from '../hooks/useAuth';
import { Icon, type IconName } from './Icon';
import { cx } from '../lib/cx';
import { EntryProvider, useEntry } from './EntryContext';
import { TransactionSheet } from './TransactionSheet';

const NAV: Array<{ to: string; label: string; short: string; icon: IconName; desktopOnly?: boolean }> = [
  { to: '/', label: 'Dashboard', short: 'Home', icon: 'home' },
  { to: '/transactions', label: 'Transactions', short: 'Activity', icon: 'list' },
  { to: '/bills', label: 'Bills', short: 'Bills', icon: 'calendar' },
  { to: '/paychecks', label: 'Paychecks', short: 'Paychecks', icon: 'wallet' },
  { to: '/spending', label: 'Spending', short: 'Spending', icon: 'chart' },
  { to: '/debts', label: 'Debts', short: 'Debts', icon: 'card' },
  // Reached from the Dashboard card on phones (the bottom bar has room for six tabs).
  { to: '/envelopes', label: 'Envelopes', short: 'Envelopes', icon: 'lock', desktopOnly: true },
];

const MOBILE_NAV = NAV.filter((item) => !item.desktopOnly);

function SignOutButton({ compact = false }: { compact?: boolean }) {
  const { signOut, session } = useAuth();
  const [busy, setBusy] = useState(false);
  return (
    <button
      type="button"
      disabled={busy}
      onClick={() => {
        setBusy(true);
        void signOut().finally(() => setBusy(false));
      }}
      title={session?.user.email ? `Signed in as ${session.user.email}` : undefined}
      className={cx(
        'inline-flex min-h-10 items-center gap-2 rounded-lg px-3 text-sm font-medium text-muted hover:bg-surface-2 hover:text-ink',
        'focus-visible:outline-2 focus-visible:outline-accent disabled:opacity-50',
        compact ? '' : 'w-full',
      )}
    >
      <Icon name="logout" size={18} />
      {busy ? 'Signing out…' : 'Sign out'}
    </button>
  );
}

function Brand() {
  return (
    <div className="flex items-center gap-2">
      <span className="grid h-8 w-8 place-items-center rounded-lg bg-accent text-accent-ink" aria-hidden="true">
        <svg viewBox="0 0 32 32" width="20" height="20">
          <path d="M9 21V11l7 6 7-6v10" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
      <span className="text-base font-semibold tracking-tight text-ink">Money Hub</span>
    </div>
  );
}

function AddButton() {
  const { openAdd } = useEntry();
  return (
    <button
      type="button"
      onClick={openAdd}
      aria-label="Add transaction"
      className="fixed right-4 bottom-[calc(4.5rem+env(safe-area-inset-bottom))] z-30 grid h-14 w-14 place-items-center rounded-full bg-accent text-accent-ink shadow-lg hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent md:right-8 md:bottom-8"
    >
      <Icon name="plus" size={26} />
    </button>
  );
}

export function Layout() {
  return (
    <EntryProvider>
      <Shell />
      <AddButton />
      <TransactionSheet />
    </EntryProvider>
  );
}

function Shell() {
  const { session } = useAuth();
  return (
    <div className="min-h-dvh bg-bg">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:rounded-lg focus:bg-surface focus:px-3 focus:py-2"
      >
        Skip to content
      </a>

      {/* Desktop sidebar */}
      <aside className="fixed inset-y-0 left-0 hidden w-60 flex-col border-r border-line bg-surface px-3 py-5 md:flex">
        <div className="px-2">
          <Brand />
        </div>
        <nav aria-label="Main" className="mt-8 flex flex-1 flex-col gap-1">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === '/'}
              className={({ isActive }) =>
                cx(
                  'flex min-h-10 items-center gap-3 rounded-lg px-3 text-sm font-medium focus-visible:outline-2 focus-visible:outline-accent',
                  isActive ? 'bg-accent-soft text-ink' : 'text-muted hover:bg-surface-2 hover:text-ink',
                )
              }
            >
              <Icon name={item.icon} size={18} />
              {item.label}
            </NavLink>
          ))}
        </nav>
        <div className="border-t border-line pt-3">
          {session?.user.email ? <p className="truncate px-3 pb-2 text-xs text-muted">{session.user.email}</p> : null}
          <SignOutButton />
        </div>
      </aside>

      {/* Mobile top bar */}
      <header className="sticky top-0 z-20 flex items-center justify-between border-b border-line bg-surface/95 px-4 py-2 pt-[max(0.5rem,env(safe-area-inset-top))] backdrop-blur md:hidden">
        <Brand />
        <SignOutButton compact />
      </header>

      <div className="md:pl-60">
        <main id="main" className="mx-auto w-full max-w-6xl px-4 pt-5 pb-28 sm:px-6 md:pt-8 md:pb-12 lg:px-10">
          <Outlet />
        </main>
      </div>

      {/* Mobile bottom tab bar */}
      <nav
        aria-label="Main"
        className="fixed inset-x-0 bottom-0 z-20 grid grid-cols-6 border-t border-line bg-surface/95 pb-[env(safe-area-inset-bottom)] backdrop-blur md:hidden"
      >
        {MOBILE_NAV.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === '/'}
            className={({ isActive }) =>
              cx(
                'flex min-h-14 min-w-0 flex-col items-center justify-center gap-0.5 px-0.5 text-[10.5px] font-medium focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent',
                isActive ? 'text-accent' : 'text-muted',
              )
            }
          >
            <Icon name={item.icon} size={20} />
            <span className="max-w-full truncate">{item.short}</span>
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
