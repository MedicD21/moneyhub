import { useSyncExternalStore } from 'react';

/**
 * The part of the page the user can actually see. On iPhone the on-screen keyboard
 * shrinks only the visual viewport: `position: fixed` elements stay sized to the
 * layout viewport and end up behind the keyboard. Sizing to this fixes that.
 */
export type VisualViewportState = {
  height: number;
  offsetTop: number;
  /** true while an on-screen keyboard (or similar) covers a large part of the screen */
  keyboardOpen: boolean;
};

const KEYBOARD_MIN_PX = 120;

let cache: VisualViewportState = { height: 0, offsetTop: 0, keyboardOpen: false };

function read(): VisualViewportState {
  const vv = window.visualViewport;
  const height = vv?.height ?? window.innerHeight;
  const offsetTop = vv?.offsetTop ?? 0;
  // Pinch zoom also shrinks vv.height; multiplying by scale cancels that out.
  const covered = window.innerHeight - height * (vv?.scale ?? 1);
  const keyboardOpen = covered > KEYBOARD_MIN_PX;
  if (cache.height !== height || cache.offsetTop !== offsetTop || cache.keyboardOpen !== keyboardOpen) {
    cache = { height, offsetTop, keyboardOpen };
  }
  return cache;
}

function subscribe(onChange: () => void): () => void {
  const vv = window.visualViewport;
  if (!vv) return () => {};
  vv.addEventListener('resize', onChange);
  vv.addEventListener('scroll', onChange);
  return () => {
    vv.removeEventListener('resize', onChange);
    vv.removeEventListener('scroll', onChange);
  };
}

const serverSnapshot: VisualViewportState = { height: 0, offsetTop: 0, keyboardOpen: false };

export function useVisualViewport(): VisualViewportState {
  return useSyncExternalStore(subscribe, read, () => serverSnapshot);
}
