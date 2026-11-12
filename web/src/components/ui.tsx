import type { ReactNode } from 'react';
import { formatCurrency, moneyTone } from '../lib/format';
import { cx } from '../lib/cx';
import { Icon, type IconName } from './Icon';

export function PageHeader({ title, description, actions }: { title: string; description?: ReactNode; actions?: ReactNode }) {
  return (
    <header className="mb-5 flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h1 className="text-2xl font-semibold tracking-tight text-ink">{title}</h1>
        {description ? <p className="mt-1 text-sm text-muted">{description}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </header>
  );
}

export function Card({
  title,
  subtitle,
  action,
  children,
  className,
  tone = 'default',
}: {
  title?: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
  tone?: 'default' | 'danger' | 'accent';
}) {
  return (
    <section
      className={cx(
        'min-w-0 rounded-2xl border bg-surface p-4 shadow-[0_1px_2px_rgba(0,0,0,0.04)] sm:p-5',
        tone === 'danger' ? 'border-danger-line' : tone === 'accent' ? 'border-accent' : 'border-line',
        className,
      )}
    >
      {title || action ? (
        <div className="mb-3 flex items-start justify-between gap-3">
          <div className="min-w-0">
            {title ? <h2 className="text-sm font-semibold text-ink">{title}</h2> : null}
            {subtitle ? <p className="mt-0.5 text-xs text-muted">{subtitle}</p> : null}
          </div>
          {action}
        </div>
      ) : null}
      {children}
    </section>
  );
}

/**
 * A money value straight from a view. `signed` colors by the transaction sign
 * convention: positive (money in) green, negative (money out) neutral.
 */
export function Money({
  value,
  signed = false,
  className,
  showPlus = false,
}: {
  value: number | null | undefined;
  signed?: boolean;
  className?: string;
  showPlus?: boolean;
}) {
  const tone = moneyTone(value);
  const text = formatCurrency(value);
  return (
    <span className={cx('tabular-nums', signed && tone === 'in' && 'text-pos', className)}>
      {showPlus && tone === 'in' ? '+' : ''}
      {text}
    </span>
  );
}

export function Stat({
  label,
  value,
  hint,
  emphasis = false,
  tone = 'default',
}: {
  label: ReactNode;
  value: ReactNode;
  hint?: ReactNode;
  emphasis?: boolean;
  tone?: 'default' | 'pos' | 'danger';
}) {
  return (
    <div className="min-w-0">
      <div className="text-xs font-medium text-muted">{label}</div>
      <div
        className={cx(
          'mt-1 truncate font-semibold tracking-tight',
          emphasis ? 'text-3xl' : 'text-xl',
          tone === 'pos' ? 'text-pos' : tone === 'danger' ? 'text-danger' : 'text-ink',
        )}
      >
        {value}
      </div>
      {hint ? <div className="mt-0.5 text-xs text-muted">{hint}</div> : null}
    </div>
  );
}

export type BadgeTone = 'neutral' | 'ok' | 'warn' | 'danger' | 'accent' | 'muted';

const BADGE: Record<BadgeTone, string> = {
  neutral: 'bg-surface-2 text-ink border-line',
  ok: 'bg-ok-bg text-pos border-ok-line',
  warn: 'bg-warn-bg text-warn border-warn-line',
  danger: 'bg-danger-bg text-danger border-danger-line',
  accent: 'bg-accent-soft text-ink border-accent',
  muted: 'bg-surface-2 text-muted border-line',
};

export function Badge({ tone = 'neutral', children, className }: { tone?: BadgeTone; children: ReactNode; className?: string }) {
  return (
    <span
      className={cx(
        'inline-flex shrink-0 items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-medium leading-4 whitespace-nowrap',
        BADGE[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}

export function Banner({
  tone,
  title,
  children,
  icon,
}: {
  tone: 'warn' | 'danger' | 'info';
  title: ReactNode;
  children?: ReactNode;
  icon?: IconName;
}) {
  const styles =
    tone === 'danger'
      ? 'bg-danger-bg border-danger-line text-danger'
      : tone === 'warn'
        ? 'bg-warn-bg border-warn-line text-warn'
        : 'bg-surface-2 border-line text-ink';
  return (
    <div role={tone === 'info' ? 'status' : 'alert'} className={cx('flex gap-3 rounded-xl border px-4 py-3', styles)}>
      <Icon name={icon ?? (tone === 'info' ? 'info' : 'alert')} className="mt-0.5 shrink-0" size={18} />
      <div className="min-w-0 text-sm">
        <div className="font-semibold">{title}</div>
        {children ? <div className="mt-0.5 text-ink/80">{children}</div> : null}
      </div>
    </div>
  );
}

export function Button({
  children,
  onClick,
  type = 'button',
  variant = 'secondary',
  disabled,
  ariaLabel,
  className,
}: {
  children: ReactNode;
  onClick?: () => void;
  type?: 'button' | 'submit';
  variant?: 'primary' | 'secondary' | 'ghost';
  disabled?: boolean;
  ariaLabel?: string;
  className?: string;
}) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      aria-label={ariaLabel}
      className={cx(
        'inline-flex min-h-10 items-center justify-center gap-1.5 rounded-lg px-3 text-sm font-medium transition-colors',
        'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:cursor-not-allowed disabled:opacity-50',
        variant === 'primary' && 'bg-accent text-accent-ink hover:opacity-90',
        variant === 'secondary' && 'border border-line bg-surface text-ink hover:bg-surface-2',
        variant === 'ghost' && 'text-muted hover:bg-surface-2 hover:text-ink',
        className,
      )}
    >
      {children}
    </button>
  );
}

export function Field({ label, children, className }: { label: string; children: ReactNode; className?: string }) {
  return (
    <label className={cx('flex min-w-0 flex-col gap-1 text-xs font-medium text-muted', className)}>
      {label}
      {children}
    </label>
  );
}

export const inputClass =
  'min-h-10 w-full min-w-0 rounded-lg border border-line bg-surface px-3 text-sm text-ink focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent';

/** Definition-list row: label left, value right. */
export function Row({ label, children, strong = false }: { label: ReactNode; children: ReactNode; strong?: boolean }) {
  return (
    <div className={cx('flex items-baseline justify-between gap-3 py-1.5 text-sm', strong && 'font-semibold')}>
      <span className={cx('min-w-0', strong ? 'text-ink' : 'text-muted')}>{label}</span>
      <span className="shrink-0 text-right text-ink tabular-nums">{children}</span>
    </div>
  );
}
