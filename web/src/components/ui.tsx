import { useState, type ReactNode } from 'react';
import { formatCurrency, moneyTone } from '../lib/format';
import { cx } from '../lib/cx';
import { Icon, type IconName } from './Icon';

export function PageHeader({ title, description, actions }: { title: string; description?: ReactNode; actions?: ReactNode }) {
  return (
    <header className="mb-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-[1.75rem] leading-tight font-semibold tracking-tight text-ink sm:text-[2rem]">{title}</h1>
          {description ? <p className="mt-1 text-sm text-muted">{description}</p> : null}
        </div>
        {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
      </div>
      <div className="title-rule mt-4" aria-hidden="true" />
    </header>
  );
}

export type CardTone = 'default' | 'danger' | 'accent' | 'warn';
export type ChipTone = 'accent' | 'pos' | 'warn' | 'danger' | 'blue' | 'muted';

const CHIP_COLOR: Record<ChipTone, string> = {
  accent: 'var(--accent)',
  pos: 'var(--pos)',
  warn: 'var(--warn)',
  danger: 'var(--danger)',
  blue: 'var(--series-1)',
  muted: 'var(--subtle)',
};

/** Small lit icon tile (styles: .chip in index.css). */
export function Chip({ icon, tone = 'accent', size = 'md' }: { icon: IconName; tone?: ChipTone; size?: 'md' | 'lg' }) {
  return (
    <span
      className={cx('chip shrink-0', size === 'lg' ? 'h-10 w-10 rounded-xl' : 'h-8 w-8')}
      style={{ ['--chip' as string]: CHIP_COLOR[tone] }}
      aria-hidden="true"
    >
      <Icon name={icon} size={size === 'lg' ? 20 : 16} />
    </span>
  );
}

/**
 * The glass panel. `tone` lights its seam and edge; `beacon` places a slow pool of light behind
 * the panel's headline figure (use it on the one panel per screen that matters most).
 */
export function Card({
  title,
  subtitle,
  action,
  children,
  className,
  tone = 'default',
  beacon = false,
  icon,
  iconTone = 'accent',
}: {
  title?: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
  tone?: CardTone;
  beacon?: boolean;
  /** a lit chip before the title naming the panel's subject */
  icon?: IconName;
  iconTone?: ChipTone;
}) {
  return (
    <section
      data-tone={tone === 'default' ? undefined : tone}
      className={cx('glass glass-seam rise min-w-0 rounded-[20px] p-4 sm:p-5', beacon && 'overflow-hidden', className)}
    >
      {beacon ? <span className="beacon" data-tone={tone === 'danger' ? 'danger' : undefined} aria-hidden="true" /> : null}
      {title || action ? (
        <div className="mb-3 flex items-start justify-between gap-3">
          <div className="flex min-w-0 items-start gap-2.5">
            {icon ? <Chip icon={icon} tone={iconTone} /> : null}
            <div className="min-w-0">
              {title ? <h2 className="text-sm font-semibold tracking-tight text-ink">{title}</h2> : null}
              {subtitle ? <p className="mt-0.5 text-xs text-muted">{subtitle}</p> : null}
            </div>
          </div>
          {action}
        </div>
      ) : null}
      {children}
    </section>
  );
}

/**
 * A Card whose body can be collapsed. Native <details>/<summary> for keyboard and screen-reader
 * support; children render only while open, so hidden charts never measure a 0-width container.
 */
export function CollapsibleCard({
  title,
  subtitle,
  meta,
  children,
  className,
  defaultOpen = false,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  /** short right-aligned text shown in the header, e.g. a count */
  meta?: ReactNode;
  children: ReactNode;
  className?: string;
  defaultOpen?: boolean;
}) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <details
      open={open}
      onToggle={(e) => setOpen(e.currentTarget.open)}
      className={cx('glass glass-seam rise group min-w-0 rounded-[20px]', className)}
    >
      <summary
        className={cx(
          'flex min-h-12 cursor-pointer list-none items-center justify-between gap-3 rounded-[20px] px-4 py-3 sm:px-5',
          '[&::-webkit-details-marker]:hidden glass-hover hover:bg-surface-2',
          'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent',
        )}
      >
        <span className="flex min-w-0 items-start gap-2">
          <span className="mt-px grid h-5 w-5 shrink-0 place-items-center rounded-md border border-line bg-surface-2 text-muted transition-colors group-open:border-accent/40 group-open:text-accent-bright">
            <Icon name="chevronRight" size={14} className="transition-transform duration-300 group-open:rotate-90 motion-reduce:transition-none" />
          </span>
          <span className="min-w-0">
            <span className="block text-sm font-semibold tracking-tight text-ink">{title}</span>
            {subtitle ? <span className="mt-0.5 block text-xs text-muted">{subtitle}</span> : null}
          </span>
        </span>
        {meta ? <span className="shrink-0 rounded-full border border-line bg-surface-2 px-2 py-0.5 text-xs text-muted tabular-nums">{meta}</span> : null}
      </summary>
      {open ? <div className="page-enter px-4 pb-4 sm:px-5 sm:pb-5">{children}</div> : null}
    </details>
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
  large = false,
  reticle = false,
  tone = 'default',
}: {
  label: ReactNode;
  value: ReactNode;
  hint?: ReactNode;
  /** the screen's hero figure: largest size and lit. Use once per screen. */
  emphasis?: boolean;
  /** a secondary headline figure: large but unlit */
  large?: boolean;
  /** frame the figure in a ring of light with corner brackets (hero figure only) */
  reticle?: boolean;
  tone?: 'default' | 'pos' | 'danger';
}) {
  const figure = (
    <span
      className={cx(
        'figure-in block truncate font-semibold tracking-tight tabular-nums',
        emphasis ? 'lit text-[2.25rem] leading-[1.1] sm:text-[2.5rem] lg:text-[3.25rem]' : large ? 'text-[1.75rem] leading-tight' : 'text-xl',
        tone === 'pos' ? 'text-pos' : tone === 'danger' ? 'text-danger' : 'text-ink',
      )}
    >
      {value}
    </span>
  );
  return (
    <div className="min-w-0">
      <div className="text-xs font-medium text-muted">{label}</div>
      <div className="mt-1">
        {reticle ? (
          <span className="reticle" data-tone={tone === 'danger' ? 'danger' : undefined}>
            <span className="hud-bracket" data-c="tl" aria-hidden="true" />
            <span className="hud-bracket" data-c="tr" aria-hidden="true" />
            <span className="hud-bracket" data-c="bl" aria-hidden="true" />
            <span className="hud-bracket" data-c="br" aria-hidden="true" />
            {figure}
          </span>
        ) : (
          figure
        )}
      </div>
      {hint ? <div className="mt-1 text-xs text-muted">{hint}</div> : null}
    </div>
  );
}

export type BadgeTone = 'neutral' | 'ok' | 'warn' | 'danger' | 'accent' | 'muted';

const BADGE: Record<BadgeTone, string> = {
  neutral: 'bg-surface-2 text-ink border-line',
  ok: 'bg-ok-bg text-pos border-ok-line badge-glow',
  warn: 'bg-warn-bg text-warn border-warn-line badge-glow',
  danger: 'bg-danger-bg text-danger border-danger-line badge-glow',
  accent: 'bg-accent-soft text-accent-bright border-accent/40 badge-glow',
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
        : 'bg-surface-2 border-line text-accent-bright';
  return (
    <div
      role={tone === 'info' ? 'status' : 'alert'}
      className={cx('rise flex gap-3 rounded-2xl border px-4 py-3 backdrop-blur-md', styles)}
    >
      <span className="badge-glow mt-px grid h-7 w-7 shrink-0 place-items-center rounded-lg border border-current/30 bg-current/10">
        <Icon name={icon ?? (tone === 'info' ? 'info' : 'alert')} size={16} />
      </span>
      <div className="min-w-0 text-sm">
        <div className="font-semibold">{title}</div>
        {children ? <div className="mt-0.5 text-ink/85">{children}</div> : null}
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
        'inline-flex min-h-10 items-center justify-center gap-1.5 rounded-xl px-3.5 text-sm font-medium',
        'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-bright disabled:cursor-not-allowed disabled:opacity-45',
        variant === 'primary' && 'btn-lit font-semibold',
        variant === 'secondary' && 'btn-glass text-ink',
        variant === 'ghost' && 'text-muted transition-colors hover:bg-surface-2 hover:text-ink',
        className,
      )}
    >
      {children}
    </button>
  );
}

export function Field({ label, children, className }: { label: string; children: ReactNode; className?: string }) {
  return (
    <label className={cx('flex min-w-0 flex-col gap-1.5 text-xs font-medium text-muted', className)}>
      {label}
      {children}
    </label>
  );
}

/** 16px on phones: iOS Safari zooms the page when a focused field is smaller. */
export const inputClass =
  'field-well min-h-11 w-full min-w-0 rounded-xl px-3 text-base text-ink sm:min-h-10 sm:text-sm';

const METER_FILL: Record<'accent' | 'pos' | 'warn' | 'danger', string> = {
  accent: 'var(--accent)',
  pos: 'var(--pos)',
  warn: 'var(--warn)',
  danger: 'var(--danger)',
};

/**
 * A lit HUD meter (styles in index.css). `percent` is display scaling of a value the view already
 * computed (0–100, clamped here); the meter does no math of its own.
 */
export function Meter({
  percent,
  tone = 'accent',
  thickness = 'sm',
  label,
  className,
}: {
  percent: number;
  tone?: 'accent' | 'pos' | 'warn' | 'danger';
  thickness?: 'sm' | 'md';
  /** accessible name; omit when the figure is already shown as text next to the meter */
  label?: string;
  className?: string;
}) {
  const width = `${Math.min(100, Math.max(0, percent))}%`;
  return (
    <div
      className={cx('hud-track', thickness === 'md' ? 'h-2' : 'h-1.5', className)}
      {...(label ? { role: 'img', 'aria-label': label } : { 'aria-hidden': true })}
    >
      <div className="hud-fill" style={{ width, ['--fill' as string]: METER_FILL[tone] }} />
    </div>
  );
}

/** Definition-list row: label left, value right. */
export function Row({ label, children, strong = false }: { label: ReactNode; children: ReactNode; strong?: boolean }) {
  return (
    <div className={cx('flex items-baseline justify-between gap-3 py-2 text-sm', strong && 'font-semibold')}>
      <span className={cx('min-w-0', strong ? 'text-ink' : 'text-muted')}>{label}</span>
      <span className="shrink-0 text-right text-ink tabular-nums">{children}</span>
    </div>
  );
}
