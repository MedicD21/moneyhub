import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react';
import type { VTransaction } from '../types/db';

type Sheet = { open: boolean; editing: VTransaction | null; session: number };

export type EntryApi = {
  /** Bumped after every successful write. Include it in useView keys so pages reload. */
  version: number;
  bump: () => void;
  sheet: Sheet;
  openAdd: () => void;
  openEdit: (t: VTransaction) => void;
  closeSheet: () => void;
};

const Ctx = createContext<EntryApi | null>(null);

/** Shared state for the add/edit transaction sheet and the "data changed" counter. */
export function EntryProvider({ children }: { children: ReactNode }) {
  const [version, setVersion] = useState(0);
  const [sheet, setSheet] = useState<Sheet>({ open: false, editing: null, session: 0 });

  const bump = useCallback(() => setVersion((v) => v + 1), []);
  const openAdd = useCallback(() => setSheet((s) => ({ open: true, editing: null, session: s.session + 1 })), []);
  const openEdit = useCallback((t: VTransaction) => setSheet((s) => ({ open: true, editing: t, session: s.session + 1 })), []);
  const closeSheet = useCallback(() => setSheet((s) => ({ ...s, open: false })), []);

  const value = useMemo<EntryApi>(
    () => ({ version, bump, sheet, openAdd, openEdit, closeSheet }),
    [version, bump, sheet, openAdd, openEdit, closeSheet],
  );
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

// eslint-disable-next-line react-refresh/only-export-components
export function useEntry(): EntryApi {
  const v = useContext(Ctx);
  if (!v) throw new Error('useEntry must be used inside <EntryProvider>');
  return v;
}
