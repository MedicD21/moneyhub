/**
 * Helpers for the review inbox and the classification sheet. Text and ordering only: no money math.
 */
import type { CategoryRow, Uuid, VTransaction } from '../types/db';

/** Rows from the bank (imported) or matched by Claude (reconciled) can only be reclassified from the web app. */
export function isBankLocked(t: Pick<VTransaction, 'entry_source' | 'reconciled'>): boolean {
  return t.entry_source !== 'manual' || t.reconciled;
}

/**
 * Starting text for a merchant rule. Rules match a case-insensitive substring of the bank description,
 * so prefer the merchant name when the description contains it, else the description itself without a
 * trailing ellipsis (banks truncate long names).
 */
export function suggestRulePattern(merchant: string | null, descriptionRaw: string): string {
  const name = (merchant ?? '').trim();
  const desc = descriptionRaw.trim();
  if (name && desc.toLowerCase().includes(name.toLowerCase())) return name;
  const trimmed = desc.replace(/(\.\.\.|…)+$/u, '').trim();
  return trimmed || name;
}

/** Does the bank description contain the pattern (the same test match_merchant_rule uses)? */
export function patternMatches(pattern: string, descriptionRaw: string): boolean {
  const p = pattern.trim().toLowerCase();
  return p.length > 0 && descriptionRaw.toLowerCase().includes(p);
}

/**
 * Categories in chip order: the most used recently first (ties keep name order), then the rest by name.
 * `recentCategoryIds` is one entry per recent transaction. Income categories are left out for money out,
 * matching the database rule that an income category needs money coming in.
 */
export function rankCategories(
  categories: CategoryRow[],
  recentCategoryIds: Array<Uuid | null>,
  moneyIn: boolean,
): { frequent: CategoryRow[]; rest: CategoryRow[] } {
  const allowed = categories.filter((c) => moneyIn || c.kind !== 'income');
  const uses = new Map<Uuid, number>();
  for (const id of recentCategoryIds) if (id) uses.set(id, (uses.get(id) ?? 0) + 1);
  const frequent = allowed
    .filter((c) => uses.has(c.id))
    .sort((a, b) => (uses.get(b.id) ?? 0) - (uses.get(a.id) ?? 0) || a.name.localeCompare(b.name))
    .slice(0, 6);
  const shown = new Set(frequent.map((c) => c.id));
  const rest = allowed.filter((c) => !shown.has(c.id)).sort((a, b) => a.name.localeCompare(b.name));
  return { frequent, rest };
}
