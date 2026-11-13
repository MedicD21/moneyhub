import { useEffect, useRef, useState } from 'react';

/**
 * True once the element has come within `margin` of the viewport, and stays true.
 * Lets long pages mount heavy content (charts) on approach instead of all at once,
 * which is what kept the Debts page from exhausting mobile Safari's memory.
 * Without IntersectionObserver (old browsers, tests) content mounts immediately.
 */
export function useNearViewport<T extends Element>(margin = '400px') {
  const ref = useRef<T>(null);
  const [near, setNear] = useState(() => typeof IntersectionObserver === 'undefined');

  useEffect(() => {
    const el = ref.current;
    if (near || !el) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setNear(true);
          observer.disconnect();
        }
      },
      { rootMargin: `${margin} 0px` },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [near, margin]);

  return { ref, near };
}
