/**
 * Hand-written row types for every view (and the two lookup tables) the web
 * app reads. Column names match supabase/migrations/*.sql exactly.
 *
 * PostgREST JSON mapping:
 *   numeric / int / bigint (count(*))  -> number
 *   date                               -> 'YYYY-MM-DD' string (IsoDate)
 *   timestamptz                        -> ISO timestamp string
 *   jsonb                              -> parsed JSON value
 *
 * These are `type` aliases (not `interface`) so they satisfy supabase-js's
 * `Record<string, unknown>` row constraint in the `Database` type below.
 */

/** A Postgres `date` as PostgREST returns it: 'YYYY-MM-DD'. */
export type IsoDate = string;
/** A Postgres `timestamptz` as PostgREST returns it. */
export type IsoTimestamp = string;
export type Uuid = string;

export type Json = string | number | boolean | null | Json[] | { [key: string]: Json };

export type AccountKind = 'checking' | 'savings' | 'credit_card' | 'loan' | 'cash';
export type CategoryKind = 'expense' | 'income' | 'transfer' | 'debt_payment';
export type TxnStatus = 'pending' | 'posted';
export type BillOccurrenceStatus = 'due' | 'paid' | 'partial' | 'skipped';
export type BillFrequency = 'weekly' | 'biweekly' | 'monthly' | 'quarterly' | 'annual';
export type DebtKind = 'credit_card' | 'auto' | 'student' | 'personal' | 'medical' | 'mortgage' | 'other';
export type DebtStrategy = 'avalanche' | 'snowball' | 'custom' | 'minimums_only';

// ---------------------------------------------------------------------------
// Tables (read for filter dropdowns only)
// ---------------------------------------------------------------------------

/** public.accounts */
export type AccountRow = {
  id: Uuid;
  owner_id: Uuid;
  name: string;
  institution: string | null;
  kind: AccountKind;
  last4: string | null;
  balance_includes_pending: boolean;
  is_active: boolean;
  created_at: IsoTimestamp;
  updated_at: IsoTimestamp;
};

/** public.categories */
export type CategoryRow = {
  id: Uuid;
  owner_id: Uuid;
  name: string;
  parent_name: string | null;
  kind: CategoryKind;
  created_at: IsoTimestamp;
  updated_at: IsoTimestamp;
};

// ---------------------------------------------------------------------------
// 20261112000300_views.sql
// ---------------------------------------------------------------------------

/** public.v_transactions (also the row shape of v_review_queue) */
export type VTransaction = {
  id: Uuid;
  txn_date: IsoDate;
  /** first of the month of txn_date */
  month: IsoDate;
  description_raw: string;
  merchant: string | null;
  /** negative = money out, positive = money in */
  amount: number;
  status: TxnStatus;
  account_id: Uuid;
  account_name: string;
  account_kind: AccountKind;
  category_id: Uuid | null;
  category_name: string | null;
  category_parent: string | null;
  category_kind: CategoryKind | null;
  tags: string[];
  needs_review: boolean;
  review_question: string | null;
  bill_occurrence_id: Uuid | null;
  debt_id: Uuid | null;
  note: string | null;
  import_batch_id: Uuid | null;
  occurrence: number;
  created_at: IsoTimestamp;
  /** you saw it clear at the bank (informational; you can tick it) */
  cleared: boolean;
  /** Claude matched it to a bank screenshot. Only Claude can change this. */
  reconciled: boolean;
  reconciled_at: IsoTimestamp | null;
  /** import = read from a screenshot or chat; manual = typed into the web app */
  entry_source: 'import' | 'manual';
};

/** public.v_account_balances. Snapshot-derived columns are null when the account has no snapshot. */
export type VAccountBalance = {
  account_id: Uuid;
  name: string;
  institution: string | null;
  kind: AccountKind;
  last4: string | null;
  is_active: boolean;
  is_liability: boolean;
  last_snapshot_id: Uuid | null;
  last_snapshot_date: IsoDate | null;
  /** as displayed by the bank (liabilities: positive = owed) */
  last_snapshot_balance: number | null;
  last_snapshot_available: number | null;
  transactions_since_snapshot: number;
  pending_total: number;
  /** signed: positive = you have it, negative = you owe it */
  estimated_balance: number | null;
  /** as the bank would display it (liabilities: positive = owed) */
  estimated_balance_display: number | null;
  days_since_screenshot: number | null;
  is_low_balance: boolean;
};

/** public.v_balance_check */
export type VBalanceCheck = {
  snapshot_id: Uuid;
  account_id: Uuid;
  account_name: string;
  import_batch_id: Uuid | null;
  prev_snapshot_id: Uuid;
  prev_as_of_date: IsoDate;
  prev_balance: number;
  as_of_date: IsoDate;
  transactions_between: number;
  txn_count: number;
  pending_between: number;
  expected_balance: number;
  actual_balance: number;
  difference: number;
  is_latest: boolean;
  likely_cause: string;
};

/** public.v_month_spending (month x category, transfers excluded) */
export type VMonthSpending = {
  month: IsoDate;
  category_id: Uuid | null;
  /** 'Uncategorized' when category_id is null */
  category_name: string;
  category_parent: string | null;
  category_kind: CategoryKind | null;
  /** positive number (money out) */
  total_out: number;
  total_in: number;
  net: number;
  txn_count: number;
};

/** public.v_cash_flow */
export type VCashFlow = {
  month: IsoDate;
  income: number;
  spending: number;
  net: number;
  uncategorized_count: number;
};

/** public.v_bill_status (also the row shape of v_upcoming_bills) */
export type VBillStatus = {
  occurrence_id: Uuid;
  bill_id: Uuid;
  bill_name: string;
  due_date: IsoDate;
  due_month: IsoDate;
  expected_amount: number;
  paid_amount: number | null;
  paid_date: IsoDate | null;
  status: BillOccurrenceStatus;
  remaining_amount: number;
  days_until_due: number;
  overdue: boolean;
  autopay: boolean;
  is_variable: boolean;
  frequency: BillFrequency;
  /** bills.is_active: occurrences of deactivated bills stay in this view for history */
  bill_is_active: boolean;
  pay_from_account_id: Uuid | null;
  pay_from_account_name: string | null;
  category_id: Uuid | null;
  category_name: string | null;
  transaction_id: Uuid | null;
  /** set when this bill is the payment schedule of a debt (20261112165034) */
  debt_id: Uuid | null;
  /** last due date of an installment plan; null = open-ended (20261112163926) */
  end_date: IsoDate | null;
};

/**
 * public.v_upcoming_bills: v_bill_status rows of active bills that are due/partial and due within 30 days (incl. overdue).
 * Its column list is explicit, so it does not carry the columns appended to v_bill_status later.
 */
export type VUpcomingBill = Omit<VBillStatus, 'debt_id' | 'end_date'>;

/** public.v_monthly_bills_total (one row; normalized monthly run-rate of active bills) */
export type VMonthlyBillsTotal = {
  monthly_total: number;
  autopay_monthly_total: number;
  variable_monthly_total: number;
  active_bill_count: number;
};

/** public.v_debts */
export type VDebt = {
  debt_id: Uuid;
  name: string;
  kind: DebtKind;
  account_id: Uuid | null;
  account_name: string | null;
  apr: number;
  promo_apr: number | null;
  promo_ends: IsoDate | null;
  effective_apr: number;
  min_payment: number;
  due_day: number | null;
  next_due_date: IsoDate | null;
  credit_limit: number | null;
  /** amount owed as a positive number */
  balance: number | null;
  balance_as_of: IsoDate | null;
  balance_source: 'account_snapshot' | 'debt_balances' | null;
  utilization_pct: number | null;
  is_active: boolean;
  /** the bill that schedules this debt's payments, if any (20261112165034) */
  payment_bill_id: Uuid | null;
  /** that bill's end_date: last scheduled payment of an installment plan */
  final_payment_date: IsoDate | null;
  /** unpaid amount of that bill's occurrences already past due */
  overdue_amount: number;
};

/** public.v_review_queue */
export type VReviewQueue = VTransaction;

/** public.v_debt_balance_history */
export type VDebtBalanceHistory = {
  debt_id: Uuid;
  debt_name: string;
  as_of_date: IsoDate;
  /** amount owed as a positive number, as displayed */
  balance: number;
  source: 'debt_balances' | 'account_snapshot';
};

/** public.v_active_debt_plan (0 or 1 row) */
export type VActiveDebtPlan = {
  plan_id: Uuid;
  name: string;
  strategy: DebtStrategy;
  extra_monthly: number;
  assumptions: Json;
  summary: Json;
  balances_as_of: IsoDate;
  created_at: IsoTimestamp;
};

/** public.v_debt_plan_schedule (active plan only). Numeric fields come from jsonb and may be null. */
export type VDebtPlanSchedule = {
  plan_id: Uuid;
  month: IsoDate;
  debt_id: Uuid;
  debt_name: string | null;
  start_balance: number | null;
  interest: number | null;
  payment: number | null;
  end_balance: number | null;
};

/** public.v_debt_plan_projection (active plan only) */
export type VDebtPlanProjection = {
  month: IsoDate;
  total_end_balance: number | null;
  total_interest: number | null;
  total_payment: number | null;
};

/** public.v_bill_match_candidates (not shown in the web app; typed for completeness) */
export type VBillMatchCandidate = {
  transaction_id: Uuid;
  import_batch_id: Uuid | null;
  txn_date: IsoDate;
  description_raw: string;
  amount: number;
  occurrence_id: Uuid;
  bill_id: Uuid;
  bill_name: string;
  due_date: IsoDate;
  expected_amount: number;
  occurrence_status: 'due' | 'partial';
  would_be_paid_in_full: boolean;
  rank: number;
};

/** public.v_app_info (exactly one row; settings columns are null before bootstrap_owner) */
export type VAppInfo = {
  /** app_today(): today in the owner's timezone */
  today: IsoDate;
  /** first of today's month */
  current_month: IsoDate;
  timezone: string | null;
  stale_after_days: number | null;
  low_balance_threshold: number | null;
};

// ---------------------------------------------------------------------------
// 20261112171106_forecast_levelized_spending.sql
// ---------------------------------------------------------------------------

/**
 * public.v_pay_period_forecast: balance-anchored cash-flow forecast, current period first
 * (period_index 1) then upcoming ones. Starts from the real cash balance and walks every
 * dated paycheck, bill, minimum, set-aside and plan payment over a look-ahead.
 */
export type VPayPeriodForecast = {
  period_index: number;
  period_start: IsoDate;
  period_end: IsoDate;
  next_pay_date: IsoDate;
  is_current: boolean;
  expected_net: number;
  /** paychecks still to arrive in this period (0 once the deposit is recorded) */
  income_in: number;
  /** bills, minimums, set-asides and plan payments still due in this period */
  obligations: number;
  /** cash in checking/savings/cash accounts today (same for every row) */
  starting_cash: number;
  cash_as_of: IsoDate | null;
  /** app_settings.low_balance_threshold: the forecast never plans below this */
  low_balance_floor: number;
  /** levelized: the steady amount you can spend this period (rest of period for the current one) */
  safe_to_spend: number;
  /** ceiling for this period alone if later periods spend nothing extra */
  max_safe_to_spend: number;
  /** left behind for a later low point; negative = this period uses money held earlier */
  hold_for_later: number;
  /** projected cash at the end of the period after spending safe_to_spend */
  carry_out: number;
  /** date of the lowest projected balance from this period onward (before spending) */
  binding_date: IsoDate | null;
  binding_balance: number | null;
  /** current period only: can't stay above the floor even with zero spending */
  shortfall: boolean;
  /** this period's paycheck is already recorded as a deposit */
  income_received: boolean;
  /** cash left when this period ends, before spending this period's safe_to_spend */
  cash_before_spending: number | null;
  /** paycheck(s) still to arrive in the following period (null for the last forecast row) */
  next_income: number | null;
  /** bills, minimums and set-asides due in the following period */
  next_obligations: number | null;
  /** next_obligations minus next_income: what the following period takes from this period's leftover cash */
  next_draw: number | null;
  next_period_end: IsoDate | null;
  /** approx. take-home per extra overtime hour (app_settings.extra_hour_net) */
  extra_hour_net: number | null;
  /** shortfall only: extra overtime hours that would cover it, rounded up to the half hour */
  extra_hours_needed: number | null;
  /** shortfall only: approx. take-home from one extra full shift */
  extra_shift_net: number | null;
  extra_shift_hours: number | null;
};

/** public.v_bill_month_totals (active bills, skipped occurrences excluded; one row per due_month) */
export type VBillMonthTotals = {
  due_month: IsoDate;
  expected_total: number;
  paid_total: number;
  remaining_total: number;
  occurrence_count: number;
  paid_count: number;
  overdue_count: number;
};

/** public.v_tags */
export type VTag = {
  tag: string;
  txn_count: number;
};

/** public.v_transaction_months */
export type VTransactionMonth = {
  /** first of the month */
  month: IsoDate;
  txn_count: number;
};

// ---------------------------------------------------------------------------
// 20261112000400_paycheck_and_dashboard.sql
// ---------------------------------------------------------------------------

export type PaycheckIncomeItem = {
  type: 'income';
  id: Uuid;
  name: string;
  date: IsoDate;
  amount: number;
};

export type PaycheckBillItem = {
  type: 'bill';
  /** bill id */
  id: Uuid;
  /** null for projected occurrences not yet generated */
  occurrence_id: Uuid | null;
  name: string;
  date: IsoDate;
  /** unpaid remainder */
  amount: number;
  status: 'due' | 'partial' | 'projected';
  overdue: boolean;
  projected: boolean;
};

export type PaycheckDebtMinimumItem = {
  type: 'debt_minimum';
  id: Uuid;
  name: string;
  date: IsoDate;
  amount: number;
  already_paid: number;
};

export type PaycheckSetAsideItem = {
  type: 'set_aside';
  id: Uuid;
  name: string;
  /** contribution this payday (reduced when the cap is reached) */
  amount: number;
  per_paycheck: number;
  cap: number | null;
  /** envelope balance after this payday's contribution (assumes no further spending) */
  balance_after: number;
  /** contribution was reduced or stopped by the cap */
  capped: boolean;
};

/** public.v_set_asides: set-asides with their running (rollover) balance */
export type VSetAside = {
  id: Uuid;
  name: string;
  per_paycheck: number;
  cap: number | null;
  is_active: boolean;
  start_date: IsoDate;
  category_id: Uuid | null;
  category_name: string | null;
  balance: number;
  current_contribution: number;
  room_left: number | null;
  at_cap: boolean;
};

export type EnvelopeKind = 'rainy_day' | 'locked_savings';

/** public.v_envelopes (20261113000000). Virtual savings: no real money moves. */
export type VEnvelope = {
  id: Uuid;
  kind: EnvelopeKind;
  name: string;
  is_active: boolean;
  balance: number;
  last_move_date: IsoDate | null;
  move_count: number;
};

/** public.v_envelope_moves: positive = set aside into the envelope, negative = moved back to spendable cash. */
export type VEnvelopeMove = {
  id: Uuid;
  envelope_id: Uuid;
  kind: EnvelopeKind;
  envelope_name: string;
  move_date: IsoDate;
  amount: number;
  note: string | null;
  created_at: IsoTimestamp;
  balance_after: number;
};

/**
 * public.v_rainy_day_suggestion: one row. When the current pay period's low point sits below the minimum
 * balance, suggested_draw is how much of the rainy-day fund would close the gap. Nothing moves on its own.
 */
export type VRainyDaySuggestion = {
  envelope_id: Uuid;
  rainy_balance: number;
  binding_date: IsoDate | null;
  binding_balance: number | null;
  low_balance_floor: number;
  gap_to_floor: number;
  suggested_draw: number;
  remaining_gap: number;
};

export type PaycheckExtraDebtItem = {
  type: 'extra_debt';
  name: string;
  amount: number;
  extra_monthly: number;
  paydays_per_year: number;
};

export type PaycheckItem =
  | PaycheckIncomeItem
  | PaycheckBillItem
  | PaycheckDebtMinimumItem
  | PaycheckSetAsideItem
  | PaycheckExtraDebtItem;

/** public.v_pay_periods (offset 0 = current period; 2 before, 6 after) */
export type VPayPeriod = {
  period_offset: number;
  period_start: IsoDate;
  period_end: IsoDate;
  next_pay_date: IsoDate;
  is_current: boolean;
  expected_net: number;
  bills_total: number;
  minimums_total: number;
  set_asides_total: number;
  extra_debt: number;
  safe_to_spend: number;
  shortfall: boolean;
  spent_so_far: number;
  remaining_safe_to_spend: number;
  /** remaining_safe_to_spend < 0 */
  overspent: boolean;
  items: PaycheckItem[];
};

/** public.v_dashboard (exactly one row). Period/payday columns are null when no income source is active. */
export type VDashboard = {
  today: IsoDate;
  total_cash: number;
  total_debt: number;
  net: number;
  bills_due_7d_count: number;
  bills_due_7d_total: number;
  overdue_bills_count: number;
  overdue_bills_total: number;
  next_payday: IsoDate | null;
  next_payday_amount: number | null;
  period_start: IsoDate | null;
  period_end: IsoDate | null;
  period_expected_net: number | null;
  safe_to_spend: number | null;
  spent_so_far: number | null;
  remaining_safe_to_spend: number | null;
  shortfall: boolean | null;
  overspent: boolean | null;
  review_queue_count: number;
  oldest_data_days: number | null;
  accounts_without_snapshot: number;
  balance_check_issues: number;
  low_balance_accounts: number;
  stale_after_days: number | null;
  low_balance_threshold: number | null;
};

// ---------------------------------------------------------------------------
// supabase-js Database type. Insert/Update are `never`-keyed so any attempt to
// write through the typed client fails to compile (belt and braces with the
// read-only guard test and RLS).
// ---------------------------------------------------------------------------

/** Arguments of public.add_manual_transaction. amount is signed: negative = money out. */
export type ManualTransactionArgs = {
  p_amount: number;
  p_txn_date: IsoDate;
  p_merchant: string;
  p_account_id?: Uuid | null;
  p_category_id?: Uuid | null;
  p_note?: string | null;
  p_cleared?: boolean;
  p_bill_occurrence_id?: Uuid | null;
  p_debt_id?: Uuid | null;
};

/** Arguments of public.update_manual_transaction (the account cannot be changed). */
export type ManualTransactionUpdateArgs = Omit<ManualTransactionArgs, 'p_account_id'> & { p_id: Uuid };

type NoWrite = { [_ in never]: never };
type ReadOnlyTable<R> = { Row: R; Insert: NoWrite; Update: NoWrite; Relationships: [] };
type ReadOnlyView<R> = { Row: R; Relationships: [] };

export type Database = {
  public: {
    Tables: {
      accounts: ReadOnlyTable<AccountRow>;
      categories: ReadOnlyTable<CategoryRow>;
    };
    Views: {
      v_transactions: ReadOnlyView<VTransaction>;
      v_account_balances: ReadOnlyView<VAccountBalance>;
      v_balance_check: ReadOnlyView<VBalanceCheck>;
      v_month_spending: ReadOnlyView<VMonthSpending>;
      v_cash_flow: ReadOnlyView<VCashFlow>;
      v_bill_status: ReadOnlyView<VBillStatus>;
      v_upcoming_bills: ReadOnlyView<VUpcomingBill>;
      v_monthly_bills_total: ReadOnlyView<VMonthlyBillsTotal>;
      v_debts: ReadOnlyView<VDebt>;
      v_review_queue: ReadOnlyView<VReviewQueue>;
      v_debt_balance_history: ReadOnlyView<VDebtBalanceHistory>;
      v_active_debt_plan: ReadOnlyView<VActiveDebtPlan>;
      v_debt_plan_schedule: ReadOnlyView<VDebtPlanSchedule>;
      v_debt_plan_projection: ReadOnlyView<VDebtPlanProjection>;
      v_bill_match_candidates: ReadOnlyView<VBillMatchCandidate>;
      v_app_info: ReadOnlyView<VAppInfo>;
      v_bill_month_totals: ReadOnlyView<VBillMonthTotals>;
      v_tags: ReadOnlyView<VTag>;
      v_transaction_months: ReadOnlyView<VTransactionMonth>;
      v_pay_periods: ReadOnlyView<VPayPeriod>;
      v_dashboard: ReadOnlyView<VDashboard>;
      v_pay_period_forecast: ReadOnlyView<VPayPeriodForecast>;
      v_set_asides: ReadOnlyView<VSetAside>;
      v_envelopes: ReadOnlyView<VEnvelope>;
      v_envelope_moves: ReadOnlyView<VEnvelopeMove>;
      v_rainy_day_suggestion: ReadOnlyView<VRainyDaySuggestion>;
    };
    /**
     * The only writes the web app can make: narrow, owner-checked SECURITY DEFINER functions
     * (20261113000000). They are called from src/lib/writes.ts and nowhere else.
     */
    Functions: {
      add_manual_transaction: { Args: ManualTransactionArgs; Returns: Uuid };
      update_manual_transaction: { Args: ManualTransactionUpdateArgs; Returns: Uuid };
      delete_manual_transaction: { Args: { p_id: Uuid }; Returns: undefined };
      set_transaction_cleared: { Args: { p_id: Uuid; p_cleared: boolean }; Returns: undefined };
      move_envelope_money: {
        Args: { p_envelope_id: Uuid; p_amount: number; p_note?: string | null; p_move_date?: IsoDate | null };
        Returns: number;
      };
    };
    Enums: { [_ in never]: never };
    CompositeTypes: { [_ in never]: never };
  };
};
