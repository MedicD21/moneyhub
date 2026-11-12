/**
 * Static guard: the web app is read-only (SPEC hard rule 1). Fails CI if any
 * source file under src/ calls a PostgREST write method or rpc.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const SRC = fileURLToPath(new URL('../src', import.meta.url));
const FORBIDDEN = /\.\s*(insert|update|upsert|delete|rpc)\s*\(/g;
const SCANNED_EXT = /\.(ts|tsx|js|jsx|mjs|cjs)$/;

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    return statSync(full).isDirectory() ? walk(full) : SCANNED_EXT.test(name) ? [full] : [];
  });
}

function findViolations(source: string): string[] {
  const hits: string[] = [];
  source.split('\n').forEach((line, i) => {
    for (const m of line.matchAll(FORBIDDEN)) hits.push(`${i + 1}: ${m[0]} -> ${line.trim()}`);
  });
  return hits;
}

describe('read-only guard', () => {
  it('detects forbidden calls (self-check)', () => {
    const samples = [
      "supabase.from('t').insert({})",
      "supabase.from('t').update({ a: 1 })",
      "supabase.from('t').upsert([])",
      "supabase.from('t').delete()",
      "supabase.rpc('fn')",
      "supabase\n  .from('t')\n  . delete ()",
    ];
    for (const s of samples) expect(findViolations(s).length, s).toBeGreaterThan(0);
    expect(findViolations("supabase.from('v_dashboard').select('*').eq('a', 1)")).toEqual([]);
  });

  it('scans a non-empty src/ tree', () => {
    expect(walk(SRC).length).toBeGreaterThan(5);
  });

  it('finds no insert/update/upsert/delete/rpc calls in src/', () => {
    const violations = walk(SRC).flatMap((file) =>
      findViolations(readFileSync(file, 'utf8')).map((v) => `${relative(SRC, file)}:${v}`),
    );
    expect(violations, `Read-only rule violated:\n${violations.join('\n')}`).toEqual([]);
  });
});
