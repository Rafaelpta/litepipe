/**
 * `useUpcomingPipes` — one-off pipes scheduled to fire in the future.
 *
 * Drives the chat sidebar's "upcoming" section. A one-off pipe has
 * `schedule: at <RFC3339 timestamp>` in its frontmatter; it fires once
 * at that instant, then auto-disables. We list only enabled pipes whose
 * run_at is still in the future — once they fire and get auto-disabled,
 * they drop off this list naturally.
 *
 * Polled, not event-driven: one-offs change shape rarely (an install or
 * a fire), so a 30s poll is enough — no need to wire to the agent-event
 * bus.
 */

import { useCallback, useEffect, useState } from "react";
import { localFetch } from "@/lib/api";
import { useSettings } from "@/lib/hooks/use-settings";

export interface UpcomingPipe {
  pipeName: string;
  title: string;
  runAt: string;   // ISO8601, future
  schedule: string; // raw "at <iso>" — kept for cancel/edit handlers
}

const ONE_OFF_PREFIX = /^\s*at\s+/i;

function parseUpcoming(raw: any[]): UpcomingPipe[] {
  const now = Date.now();
  const out: UpcomingPipe[] = [];
  for (const p of raw) {
    const cfg = p?.config;
    if (!cfg?.enabled) continue;
    const sched: string | undefined = cfg?.schedule;
    if (!sched || !ONE_OFF_PREFIX.test(sched)) continue;
    const runAtRaw = sched.replace(ONE_OFF_PREFIX, "").trim();
    const runAtMs = Date.parse(runAtRaw);
    if (Number.isNaN(runAtMs) || runAtMs <= now) continue; // past/invalid
    out.push({
      pipeName: cfg.name,
      title: (cfg.config?.title as string) || cfg.name,
      runAt: new Date(runAtMs).toISOString(),
      schedule: sched,
    });
  }
  out.sort((a, b) => Date.parse(a.runAt) - Date.parse(b.runAt));
  return out;
}

export interface UseUpcomingPipesResult {
  pipes: UpcomingPipe[];
  /** Force a refetch — call after a mutation (cancel/install) so the
   *  sidebar reflects the change without waiting up to 30s for the
   *  next poll. */
  refetch: () => Promise<void>;
  /** Optimistically remove a pipe from the list. Used by cancel-handlers
   *  to make the row disappear instantly while the disable API call is
   *  in flight; the next refetch reconciles either way. */
  dismiss: (pipeName: string) => void;
}

export function useUpcomingPipes(): UseUpcomingPipesResult {
  const [pipes, setPipes] = useState<UpcomingPipe[]>([]);
  const { isSettingsLoaded } = useSettings();

  const refetch = useCallback(async () => {
    try {
      const res = await localFetch("/pipes");
      if (!res.ok) return;
      const json = await res.json();
      setPipes(parseUpcoming(json.data || []));
    } catch {
      // best-effort — silent failure, retry next tick
    }
  }, []);

  const dismiss = useCallback((pipeName: string) => {
    setPipes((prev) => prev.filter((p) => p.pipeName !== pipeName));
  }, []);

  useEffect(() => {
    if (!isSettingsLoaded) return;
    let cancelled = false;
    const poll = async () => {
      if (cancelled) return;
      await refetch();
    };
    void poll();
    const id = setInterval(poll, 30_000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [isSettingsLoaded, refetch]);

  return { pipes, refetch, dismiss };
}
