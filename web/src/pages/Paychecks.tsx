import { useState, type ReactNode } from "react";
import { useView } from "../hooks/useView";
import { useEntry } from "../components/EntryContext";
import { RainyDayHint } from "../components/RainyDayHint";
import type {
  PaycheckBillItem,
  PaycheckDebtMinimumItem,
  PaycheckExtraDebtItem,
  PaycheckIncomeItem,
  PaycheckSetAsideItem,
  VPayPeriod,
  VPayPeriodForecast,
  VSetAside,
} from "../types/db";
import {
  formatCount,
  formatCurrency,
  formatDate,
  formatDateRange,
} from "../lib/format";
import { Badge, Money, PageHeader, Row } from "../components/ui";
import { Icon } from "../components/Icon";
import { cx } from "../lib/cx";
import { QueryState } from "../components/QueryState";
import { billStatusBadge } from "../components/billStatus";

export default function Paychecks() {
  const { version } = useEntry();
  const periods = useView<VPayPeriod>(`v_pay_periods:${version}`, (sb) =>
    sb.from("v_pay_periods").select("*").order("period_offset"),
  );
  const forecast = useView<VPayPeriodForecast>(`v_pay_period_forecast:${version}`, (sb) =>
    sb.from("v_pay_period_forecast").select("*").order("period_index"),
  );
  const setAsides = useView<VSetAside>(`v_set_asides:${version}`, (sb) =>
    sb.from("v_set_asides").select("*").eq("is_active", true).order("name"),
  );
  // Join on period_start (lookup only, no arithmetic). Missing forecast rows simply hide the forecast box.
  const forecastByStart = new Map(
    (forecast.data ?? []).map((f) => [f.period_start, f]),
  );

  return (
    <>
      <PageHeader
        title="Paychecks"
        description="What each paycheck has to cover, and how much to hold back so short paychecks and bill clusters are covered."
      />
      {setAsides.data && setAsides.data.length > 0 ? (
        <SetAsidePanel rows={setAsides.data} />
      ) : null}
      <QueryState
        state={periods}
        label="pay periods"
        loadingLines={10}
        empty="No pay periods. Add an active income source to plan paychecks."
      >
        {(rows) => {
          const past = rows.filter((p) => p.period_offset < 0);
          const rest = rows.filter((p) => p.period_offset >= 0);
          const card = (p: VPayPeriod) => (
            <PeriodCard
              key={p.period_start}
              p={p}
              f={forecastByStart.get(p.period_start) ?? null}
            />
          );
          return (
            <ol className="relative space-y-4 border-l-2 border-line pl-4 sm:pl-6">
              {past.length > 0 ? (
                <li className="relative">
                  <PastFolder count={past.length}>
                    <ol className="space-y-3">{past.map(card)}</ol>
                  </PastFolder>
                </li>
              ) : null}
              {rest.map(card)}
            </ol>
          );
        }}
      </QueryState>
    </>
  );
}

function SetAsidePanel({ rows }: { rows: VSetAside[] }) {
  return (
    <section
      aria-label="Set-aside balances"
      className="mb-4 rounded-2xl border border-line bg-surface p-4 sm:p-5"
    >
      <h2 className="text-sm font-semibold text-ink">Set-asides</h2>
      <p className="mt-0.5 text-xs text-muted">
        Money held back each paycheck. Balances roll over, up to the cap, and
        spending in the linked category draws them down.
      </p>
      <ul className="mt-3 grid gap-3 sm:grid-cols-2">
        {rows.map((r) => {
          const pct =
            r.cap && r.cap > 0
              ? Math.min(Math.max(r.balance / r.cap, 0), 1)
              : null;
          return (
            <li
              key={r.id}
              className="rounded-xl border border-line bg-surface-2 p-3"
            >
              <div className="flex items-baseline justify-between gap-3">
                <span className="min-w-0 truncate text-sm font-medium text-ink">
                  {r.name}
                </span>
                <span
                  className={cx(
                    "text-base font-semibold tabular-nums",
                    r.balance < 0 ? "text-danger" : "text-ink",
                  )}
                >
                  <Money value={r.balance} />
                </span>
              </div>
              {pct !== null ? (
                <div
                  className="mt-2 h-1.5 overflow-hidden rounded-full bg-line"
                  role="img"
                  aria-label={`${Math.round(pct * 100)}% of cap`}
                >
                  <div
                    className="h-full rounded-full bg-accent"
                    style={{ width: `${pct * 100}%` }}
                  />
                </div>
              ) : null}
              <p className="mt-1.5 text-xs text-muted">
                {formatCurrency(r.per_paycheck)} per paycheck
                {r.cap !== null
                  ? ` · cap ${formatCurrency(r.cap)}${r.at_cap ? " (full)" : ""}`
                  : " · no cap"}
                {r.category_name ? ` · draws from ${r.category_name}` : ""}
              </p>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

function PastFolder({
  count,
  children,
}: {
  count: number;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  return (
    <details
      open={open}
      onToggle={(e) => setOpen(e.currentTarget.open)}
      className="group"
    >
      <summary className="flex min-h-12 cursor-pointer list-none items-center gap-2 rounded-2xl border border-line bg-surface px-4 py-3 text-sm font-semibold text-ink hover:bg-surface-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent [&::-webkit-details-marker]:hidden">
        <Icon
          name="chevronRight"
          size={16}
          className="shrink-0 text-muted transition-transform group-open:rotate-90 motion-reduce:transition-none"
        />
        Past paychecks
        <span className="text-xs font-normal text-muted">{count}</span>
      </summary>
      {open ? <div className="mt-3">{children}</div> : null}
    </details>
  );
}

function PeriodCard({ p, f }: { p: VPayPeriod; f: VPayPeriodForecast | null }) {
  const current = p.period_offset === 0;
  const [open, setOpen] = useState(current);
  const past = p.period_offset < 0;
  const items = Array.isArray(p.items) ? p.items : [];
  const income = items.filter(
    (i): i is PaycheckIncomeItem => i.type === "income",
  );
  const bills = items.filter((i): i is PaycheckBillItem => i.type === "bill");
  const mins = items.filter(
    (i): i is PaycheckDebtMinimumItem => i.type === "debt_minimum",
  );
  const sets = items.filter(
    (i): i is PaycheckSetAsideItem => i.type === "set_aside",
  );
  const extra = items.filter(
    (i): i is PaycheckExtraDebtItem => i.type === "extra_debt",
  );
  // A period that only works because earlier paychecks held money back is covered, not a shortfall.
  const uncovered = f ? f.shortfall : p.shortfall;

  return (
    <li className="relative" aria-current={current ? "step" : undefined}>
      <span
        aria-hidden="true"
        className={cx(
          "absolute top-6 -left-[23px] h-3 w-3 rounded-full border-2 sm:-left-[31px]",
          current
            ? "border-accent bg-accent"
            : past
              ? "border-line bg-surface-2"
              : "border-subtle bg-surface",
        )}
      />
      <details
        open={open}
        onToggle={(e) => setOpen(e.currentTarget.open)}
        className={cx(
          "group rounded-2xl border bg-surface",
          uncovered
            ? "border-danger-line ring-1 ring-danger-line"
            : current
              ? "border-accent ring-1 ring-accent"
              : "border-line",
          past && !current && "opacity-85",
        )}
      >
        <summary className="flex cursor-pointer list-none items-start gap-2 rounded-2xl p-4 hover:bg-surface-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent sm:p-5 [&::-webkit-details-marker]:hidden">
          <Icon
            name="chevronRight"
            size={16}
            className="mt-1 shrink-0 text-muted transition-transform group-open:rotate-90 motion-reduce:transition-none"
          />
          <div className="flex min-w-0 flex-1 flex-wrap items-start justify-between gap-x-4 gap-y-2">
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-1.5">
                <h2 className="text-base font-semibold text-ink">
                  Payday {formatDate(p.period_start, "weekday")}
                </h2>
                {current ? (
                  <Badge tone="accent">Current</Badge>
                ) : past ? (
                  <Badge tone="muted">Past</Badge>
                ) : (
                  <Badge tone="neutral">Upcoming</Badge>
                )}
                {uncovered ? <Badge tone="danger">Shortfall</Badge> : null}
                {!uncovered && f && f.hold_for_later < 0 ? (
                  <Badge tone="warn">Covered by earlier paychecks</Badge>
                ) : null}
                {current && p.overspent ? (
                  <Badge tone="danger">Overspent</Badge>
                ) : null}
              </div>
              <p className="mt-0.5 text-xs text-muted">
                Covers {formatDateRange(p.period_start, p.period_end)} · next
                payday {formatDate(p.next_pay_date, "short")}
              </p>
            </div>
            <dl className="grid w-full grid-cols-3 gap-x-3 text-left text-sm sm:w-auto sm:gap-x-4 sm:text-right">
              <div>
                <dt className="text-xs text-muted">Paycheck</dt>
                <dd className="font-semibold text-pos">
                  <Money value={p.expected_net} />
                </dd>
              </div>
              <div>
                <dt className="text-xs text-muted">Bills</dt>
                <dd className="font-semibold text-ink">
                  <Money value={p.bills_total} />
                </dd>
              </div>
              <div>
                <dt className="text-xs text-muted">Safe to spend</dt>
                <dd
                  className={cx(
                    "font-semibold",
                    (f ? f.shortfall : p.shortfall)
                      ? "text-danger"
                      : "text-ink",
                  )}
                >
                  <Money value={f ? f.safe_to_spend : p.safe_to_spend} />
                </dd>
              </div>
            </dl>
          </div>
        </summary>

        {open ? (
          <div className="grid gap-4 px-4 pb-4 sm:px-5 sm:pb-5 md:grid-cols-2">
            <div className="space-y-4">
              {income.length > 1 ? (
                <ItemGroup title="Income">
                  {income.map((i) => (
                    <ItemLine
                      key={`${i.id}-${i.date}`}
                      name={i.name}
                      meta={formatDate(i.date, "short")}
                      amount={i.amount}
                    />
                  ))}
                </ItemGroup>
              ) : null}
              <ItemGroup
                title="Bills"
                total={p.bills_total}
                empty="No bills due this period."
              >
                {bills.map((b) => {
                  const badge = billStatusBadge(
                    b.projected ? "projected" : b.status,
                    b.overdue,
                  );
                  return (
                    <ItemLine
                      key={`${b.id}-${b.date}`}
                      name={b.name}
                      meta={formatDate(b.date, "short")}
                      amount={b.amount}
                      badge={
                        badge.label !== "Due" ? (
                          <Badge tone={badge.tone}>{badge.label}</Badge>
                        ) : null
                      }
                    />
                  );
                })}
              </ItemGroup>
              <ItemGroup
                title="Debt minimums"
                total={p.minimums_total}
                empty="No minimums due this period."
              >
                {mins.map((m) => (
                  <ItemLine
                    key={`${m.id}-${m.date}`}
                    name={m.name}
                    meta={`${formatDate(m.date, "short")}${m.already_paid > 0 ? ` · ${formatCurrency(m.already_paid)} already paid` : ""}`}
                    amount={m.amount}
                  />
                ))}
              </ItemGroup>
            </div>
            <div className="space-y-4">
              <ItemGroup
                title="Set-asides"
                total={p.set_asides_total}
                empty="No set-asides."
              >
                {sets.map((s) => (
                  <ItemLine
                    key={s.id}
                    name={s.name}
                    meta={
                      s.capped
                        ? s.amount > 0
                          ? `Reduced from ${formatCurrency(s.per_paycheck)}: reaches the ${formatCurrency(s.cap ?? 0)} cap`
                          : `At the ${formatCurrency(s.cap ?? 0)} cap, nothing added`
                        : `Balance after: ${formatCurrency(s.balance_after)}`
                    }
                    amount={s.amount}
                  />
                ))}
              </ItemGroup>
              <ItemGroup
                title="Extra debt payment"
                total={p.extra_debt}
                empty="No rollover or extra payment this period."
              >
                {extra.map((x) => (
                  <ItemLine
                    key={x.name}
                    name={x.name}
                    meta={`${formatCurrency(x.extra_monthly)} this month (rollover + extra) over ${formatCount(x.paydays_per_year)} paydays a year`}
                    amount={x.amount}
                  />
                ))}
              </ItemGroup>

              {f ? <ForecastBox f={f} /> : null}

              <div
                className={cx(
                  "rounded-xl border p-3",
                  p.shortfall
                    ? "border-warn-line bg-warn-bg"
                    : "border-line bg-surface-2",
                )}
              >
                <Row
                  label={
                    f ? "This paycheck minus its own bills" : "Safe to spend"
                  }
                  strong={!f}
                >
                  <span
                    className={cx(
                      f ? "text-ink" : "text-base",
                      p.shortfall
                        ? f
                          ? "text-warn"
                          : "text-danger"
                        : "text-ink",
                    )}
                  >
                    <Money value={p.safe_to_spend} />
                  </span>
                </Row>
                {current ? (
                  <>
                    <Row label="Spent so far">
                      <Money value={p.spent_so_far} />
                    </Row>
                    {!f ? (
                      <Row label="Remaining" strong>
                        <span
                          className={cx(
                            p.overspent ? "text-danger" : "text-ink",
                          )}
                        >
                          <Money value={p.remaining_safe_to_spend} />
                        </span>
                      </Row>
                    ) : null}
                  </>
                ) : null}
              </div>
            </div>
          </div>
        ) : null}
      </details>
    </li>
  );
}

function ForecastBox({ f }: { f: VPayPeriodForecast }) {
  const holding = f.hold_for_later > 0;
  const drawing = f.hold_for_later < 0;
  // The next-period figures come straight from the view (database does the math).
  const hasNext =
    f.next_income !== null &&
    f.next_obligations !== null &&
    f.next_draw !== null &&
    f.next_period_end !== null;
  const nextRange = f.next_period_end
    ? `${formatDate(f.next_pay_date, "short")} – ${formatDate(f.next_period_end, "short")}`
    : "";
  return (
    <div
      className={cx(
        "rounded-xl border p-3",
        f.shortfall
          ? "border-danger-line bg-danger-bg"
          : "border-accent bg-accent-soft",
      )}
    >
      <Row
        label={
          f.is_current ? "Safe to spend (rest of period)" : "Safe to spend"
        }
        strong
      >
        <span
          className={cx("text-base", f.shortfall ? "text-danger" : "text-ink")}
        >
          <Money value={f.safe_to_spend} />
        </span>
      </Row>
      {holding ? (
        <Row label="Held back for later paychecks">
          <Money value={f.hold_for_later} />
        </Row>
      ) : null}
      {drawing ? (
        <Row label="Taken from money held back earlier">
          <Money value={-f.hold_for_later} />
        </Row>
      ) : null}
      {f.cash_before_spending !== null ? (
        <Row
          label={
            f.is_current
              ? "Cash left when this period ends"
              : "Cash at end of period (before spending)"
          }
        >
          <Money value={f.cash_before_spending} />
        </Row>
      ) : (
        <Row label="Projected cash at period end">
          <Money value={f.carry_out} />
        </Row>
      )}
      {hasNext && (f.next_draw ?? 0) > 0 ? (
        <Row label={`Next period's bills not covered by its paycheck (${nextRange})`}>
          <Money value={f.next_draw} />
        </Row>
      ) : null}
      {hasNext ? (
        <p className="mt-1.5 text-xs text-muted">
          Next period ({nextRange}): {formatCurrency(f.next_obligations)} in
          bills
          {(f.next_income ?? 0) > 0
            ? `, ${formatCurrency(f.next_income)} paycheck`
            : ""}
          .{" "}
          {(f.next_draw ?? 0) > 0
            ? `${formatCurrency(f.next_draw)} of it has to come from the cash left over from this period.`
            : "Its paycheck covers it."}
        </p>
      ) : null}
      <p className="mt-1.5 text-xs text-muted">
        {f.shortfall && f.binding_date && f.binding_balance !== null
          ? `Even if you spend nothing extra, cash is projected to reach ${formatCurrency(f.binding_balance)} on ${formatDate(f.binding_date, "short")}, which is below your ${formatCurrency(f.low_balance_floor)} minimum balance. Any spending now makes that gap bigger.`
          : `Keeps your balance above ${formatCurrency(f.low_balance_floor)} through the next paychecks${
              f.binding_date
                ? `; tightest point ${formatDate(f.binding_date, "short")}`
                : ""
            }. Up to ${formatCurrency(f.max_safe_to_spend)} this period if later periods spend nothing extra.`}
        {f.is_current
          ? ` Based on cash as of ${formatDate(f.cash_as_of, "short")}.`
          : ""}
      </p>
      {f.shortfall && f.is_current ? <RainyDayHint /> : null}
      {f.shortfall && f.extra_hours_needed !== null ? (
        <p className="mt-1.5 text-xs text-ink">
          Rough fix: about {f.extra_hours_needed} extra overtime hours (about{" "}
          {formatCurrency(f.extra_hour_net)} per hour after taxes). One extra{" "}
          {f.extra_shift_hours}-hour shift would bring in about{" "}
          {formatCurrency(f.extra_shift_net)}. The extra pay has to be deposited
          before {formatDate(f.binding_date, "short")} to help.
        </p>
      ) : null}
    </div>
  );
}

function ItemGroup({
  title,
  total,
  empty,
  children,
}: {
  title: string;
  total?: number;
  empty?: string;
  children: ReactNode[] | ReactNode;
}) {
  const list = Array.isArray(children) ? children : [children];
  const hasItems = list.some(Boolean);
  return (
    <div>
      <div className="flex items-baseline justify-between gap-2 border-b border-line pb-1">
        <h3 className="text-xs font-semibold tracking-wide text-muted uppercase">
          {title}
        </h3>
        {total !== undefined ? (
          <span className="text-sm font-semibold text-ink">
            <Money value={total} />
          </span>
        ) : null}
      </div>
      {hasItems ? (
        <ul className="mt-1">{children}</ul>
      ) : empty ? (
        <p className="mt-1.5 text-xs text-subtle">{empty}</p>
      ) : null}
    </div>
  );
}

function ItemLine({
  name,
  meta,
  amount,
  badge,
}: {
  name: string;
  meta?: string;
  amount: number;
  badge?: ReactNode;
}) {
  return (
    <li className="flex items-start justify-between gap-3 py-1.5 text-sm">
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="text-ink">{name}</span>
          {badge}
        </div>
        {meta ? <div className="text-xs text-muted">{meta}</div> : null}
      </div>
      <Money value={amount} className="shrink-0 text-ink" />
    </li>
  );
}
