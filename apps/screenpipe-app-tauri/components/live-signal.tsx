"use client";

import { useEffect, useState } from "react";

// Quadrant frames — a square fills clockwise, then empties. Sharp Unicode
// block chars keep the per-DESIGN.md no-curves rule. The full `█` is
// reserved for the static unread glyph, so it's omitted here — otherwise
// a mid-cycle live row is indistinguishable from an unread one.
const LIVE_FRAMES = ["▘", "▀", "▛", "▜", "▐", "▝", "·"] as const;

export function LiveSignal({ ariaLabel = "loading" }: { ariaLabel?: string }) {
  const [frame, setFrame] = useState(0);
  useEffect(() => {
    const id = setInterval(
      () => setFrame((f) => (f + 1) % LIVE_FRAMES.length),
      140
    );
    return () => clearInterval(id);
  }, []);
  return (
    <span
      className="font-mono text-[10px] leading-none text-foreground inline-flex items-center justify-center w-2.5 h-2.5 shrink-0"
      aria-label={ariaLabel}
    >
      {LIVE_FRAMES[frame]}
    </span>
  );
}
