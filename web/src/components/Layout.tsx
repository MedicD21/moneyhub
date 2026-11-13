import { NavLink, Outlet, useLocation } from 'react-router-dom';
import { useState } from 'react';
import { useAuth } from '../hooks/useAuth';
import { Icon, type IconName } from './Icon';
import { cx } from '../lib/cx';
import { EntryProvider, useEntry } from './EntryContext';
import { TransactionSheet } from './TransactionSheet';
import { useVisualViewport } from '../hooks/useVisualViewport';
import { LampField } from './LampField';

const NAV: Array<{ to: string; label: string; short: string; icon: IconName; desktopOnly?: boolean }> = [
  { to: '/', label: 'Dashboard', short: 'Home', icon: 'home' },
  { to: '/transactions', label: 'Transactions', short: 'Activity', icon: 'list' },
  { to: '/bills', label: 'Bills', short: 'Bills', icon: 'calendar' },
  { to: '/paychecks', label: 'Paychecks', short: 'Paychecks', icon: 'wallet' },
  { to: '/spending', label: 'Spending', short: 'Spending', icon: 'chart' },
  { to: '/debts', label: 'Debts', short: 'Debts', icon: 'card' },
  // Reached from the Dashboard card on phones (the dock has room for six tabs).
  { to: '/envelopes', label: 'Envelopes', short: 'Envelopes', icon: 'lock', desktopOnly: true },
];

const MOBILE_NAV = NAV.filter((item) => !item.desktopOnly);

function activeIndex(pathname: string, items: typeof NAV): number {
  return items.findIndex((item) => (item.to === '/' ? pathname === '/' : pathname === item.to || pathname.startsWith(`${item.to}/`)));
}

/** The light behind the glass: an LED wall with a winding ribbon of light, its bloom, one lit line, vignette and grain. */
export function Ambient() {
  return (
    <div className="ambient" aria-hidden="true">
      <div className="ambient-bloom" />
      <LampField />
      <div className="ambient-line" />
      <div className="ambient-vignette" />
      <div className="ambient-grain" />
    </div>
  );
}

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
        'inline-flex min-h-10 items-center gap-2 rounded-xl px-3 text-sm font-medium text-muted transition-colors hover:bg-surface-2 hover:text-ink',
        'focus-visible:outline-2 focus-visible:outline-accent-bright disabled:opacity-50',
        compact ? '' : 'w-full',
      )}
    >
      <Icon name="logout" size={18} />
      {busy ? 'Signing out…' : 'Sign out'}
    </button>
  );
}

export function BrandMark({ size = 'md' }: { size?: 'md' | 'lg' }) {
  const box = size === 'lg' ? 'h-11 w-11 rounded-[14px]' : 'h-9 w-9 rounded-xl';
  return (
    <span className={cx('halo grid shrink-0 place-items-center bg-[var(--surface-solid)] text-accent-bright', box)} aria-hidden="true">
      <svg viewBox="0 0 32 32" width={size === 'lg' ? 26 : 22} height={size === 'lg' ? 26 : 22} style={{ filter: 'drop-shadow(0 0 6px rgba(139,231,197,0.75))' }}>
        <path d="M9 21V11l7 6 7-6v10" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    </span>
  );
}

function Brand() {
  return (
    <div className="flex items-center gap-2.5">
      <BrandMark />
      <span className="text-base font-semibold tracking-tight text-ink">Money Hub</span>
    </div>
  );
}

function AddButton() {
  const { openAdd } = useEntry();
  const { keyboardOpen } = useVisualViewport();
  // On iPhone fixed elements ride up on top of the keyboard and cover the field being typed in.
  if (keyboardOpen) return null;
  return (
    <button
      type="button"
      onClick={openAdd}
      aria-label="Add transaction"
      className="halo orb fixed right-4 bottom-[calc(6rem+env(safe-area-inset-bottom))] z-30 grid h-14 w-14 place-items-center rounded-full text-accent-ink transition-transform duration-300 hover:scale-105 active:scale-95 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-accent-bright md:right-8 md:bottom-8"
    >
      <Icon name="plus" size={26} strokeWidth={2.4} />
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
  const { keyboardOpen } = useVisualViewport();
  const { pathname } = useLocation();
  const dockIndex = activeIndex(pathname, MOBILE_NAV);
  return (
    <div className="min-h-dvh">
      <Ambient />
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:rounded-xl focus:bg-[var(--surface-solid)] focus:px-3 focus:py-2"
      >
        Skip to content
      </a>

      {/* Desktop rail: a floating glass column. */}
      <aside className="glass glass-seam fixed top-3 bottom-3 left-3 hidden w-60 flex-col rounded-[24px] px-3 py-5 md:flex">
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
                  'group flex min-h-11 items-center gap-3 rounded-xl px-3 text-sm font-medium transition-colors duration-200 focus-visible:outline-2 focus-visible:outline-accent-bright',
                  isActive ? 'nav-lit text-ink' : 'text-muted hover:bg-surface-2 hover:text-ink',
                )
              }
            >
              {({ isActive }) => (
                <>
                  <Icon name={item.icon} size={18} className={isActive ? 'text-accent-bright' : 'transition-transform duration-300 group-hover:translate-x-0.5'} />
                  <span className="flex-1">{item.label}</span>
                  {isActive ? <span className="nav-dot" aria-hidden="true" /> : null}
                </>
              )}
            </NavLink>
          ))}
        </nav>
        <div className="border-t border-line pt-3">
          {session?.user.email ? <p className="truncate px-3 pb-2 text-xs text-subtle">{session.user.email}</p> : null}
          <SignOutButton />
        </div>
      </aside>

      {/* Phone top bar */}
      <header className="glass sticky top-0 z-20 flex items-center justify-between rounded-none border-x-0 border-t-0 px-4 py-2 pt-[max(0.5rem,env(safe-area-inset-top))] md:hidden">
        <Brand />
        <SignOutButton compact />
      </header>

      <div className="md:pl-[16.5rem]">
        <main id="main" className="mx-auto w-full max-w-6xl px-4 pt-6 pb-[calc(11rem+env(safe-area-inset-bottom))] sm:px-6 md:pt-9 md:pb-14 lg:px-10">
          <div key={pathname} className="page-enter stagger">
            <Outlet />
          </div>
        </main>
      </div>

      {/* Phone dock: floating glass with a gliding light. */}
      <nav
        aria-label="Main"
        className={cx(
          'glass fixed inset-x-2.5 bottom-[calc(0.625rem+env(safe-area-inset-bottom))] z-20 grid grid-cols-6 rounded-[22px] p-1.5 md:hidden',
          keyboardOpen && 'hidden',
        )}
      >
        {dockIndex >= 0 ? (
          <span
            className="dock-indicator"
            style={{ ['--i' as string]: dockIndex, ['--tabs' as string]: MOBILE_NAV.length }}
            aria-hidden="true"
          />
        ) : null}
        {MOBILE_NAV.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === '/'}
            className={({ isActive }) =>
              cx(
                'relative flex min-h-13 min-w-0 flex-col items-center justify-center gap-0.5 rounded-2xl px-0.5 text-[10.5px] font-medium transition-colors duration-300 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent-bright',
                isActive ? 'text-accent-bright' : 'text-muted',
              )
            }
          >
            {({ isActive }) => (
              <>
                <Icon
                  name={item.icon}
                  size={20}
                  style={isActive ? { filter: 'drop-shadow(0 0 6px rgba(139,231,197,0.7))' } : undefined}
                />
                <span className="max-w-full truncate">{item.short}</span>
              </>
            )}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
