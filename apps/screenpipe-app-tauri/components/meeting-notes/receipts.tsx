"use client";

import React from "react";
import { ExternalLink, FileText, Globe, Layers } from "lucide-react";
import { open as openExternal } from "@tauri-apps/plugin-shell";
import {
  hostFromUrl,
  pathFromUrl,
  pickAppWindows,
  pickReceiptUrls,
  type ActivitySummary,
} from "@/lib/utils/meeting-context";

interface ReceiptsProps {
  activity: ActivitySummary;
}

/** Display-friendly slice of an absolute path: keep the last two segments
 *  ("vault/050526.md") so the bullet stays readable on narrow screens but
 *  unique enough to disambiguate same-named files in different folders. */
function displayPath(p: string): string {
  const parts = p.split("/").filter(Boolean);
  if (parts.length <= 2) return p;
  return parts.slice(-2).join("/");
}

/** Open the file in Finder (or its associated app). Fails silently on
 *  permission errors / deleted files — meeting notes can outlive the
 *  files they reference and we don't want to throw a Tauri permission
 *  toast every time someone clicks an old entry. */
function openFile(absPath: string) {
  // Tauri's shell-plugin requires a file:// scheme to disambiguate from
  // shell command strings.
  const uri = absPath.startsWith("file://") ? absPath : `file://${absPath}`;
  void openExternal(uri).catch(() => {});
}

export function Receipts({ activity }: ReceiptsProps) {
  const urls = pickReceiptUrls(activity.windows, 10);
  const apps = pickAppWindows(activity.windows, 6);
  const files = (activity.edited_files ?? []).slice(0, 12);

  if (urls.length === 0 && apps.length === 0 && files.length === 0) return null;

  return (
    <section className="border-t border-border pt-5">
      <h3 className="text-[11px] uppercase tracking-[0.18em] text-muted-foreground mb-3 flex items-center gap-2">
        <Layers className="h-3 w-3" />
        related during this meeting
      </h3>

      {urls.length > 0 && (
        <ul className="border border-border divide-y divide-border mb-3">
          {urls.map((w) => (
            <li key={w.browser_url}>
              <button
                onClick={() => void openExternal(w.browser_url).catch(() => {})}
                className="group w-full text-left px-3 py-2 flex items-center gap-3 hover:bg-muted/40 transition-colors"
                title={w.browser_url}
              >
                <Globe className="h-3 w-3 text-muted-foreground/60 shrink-0" />
                <div className="flex-1 min-w-0">
                  <div className="text-sm text-foreground truncate">
                    {w.window_name || hostFromUrl(w.browser_url)}
                  </div>
                  <div className="text-[11px] text-muted-foreground truncate">
                    {hostFromUrl(w.browser_url)}
                    {pathFromUrl(w.browser_url) !== "/" && (
                      <span className="text-muted-foreground/60">
                        {pathFromUrl(w.browser_url)}
                      </span>
                    )}
                  </div>
                </div>
                <span className="text-[11px] text-muted-foreground tabular-nums shrink-0">
                  {w.minutes}m
                </span>
                <ExternalLink className="h-3 w-3 text-muted-foreground/40 group-hover:text-foreground transition-colors shrink-0" />
              </button>
            </li>
          ))}
        </ul>
      )}

      {apps.length > 0 && (
        <ul className="flex flex-wrap gap-1.5 mb-3">
          {apps.map((w) => (
            <li
              key={`${w.app_name}::${w.window_name}`}
              className="inline-flex items-center gap-1.5 border border-border px-2 py-1 text-[11px] text-muted-foreground"
              title={`${w.app_name} · ${w.window_name}`}
            >
              <span className="text-foreground/80">{w.app_name.toLowerCase()}</span>
              <span className="text-muted-foreground/60" aria-hidden>·</span>
              <span className="truncate max-w-[180px]">{w.window_name}</span>
              <span className="text-muted-foreground/60" aria-hidden>·</span>
              <span className="tabular-nums">{w.minutes}m</span>
            </li>
          ))}
        </ul>
      )}

      {/* Files edited during meeting — sourced from the focused window's
          AXDocument on macOS. Empty on Windows/Linux until those platforms
          grow equivalent capture, in which case the section just doesn't
          render (length-zero check). */}
      {files.length > 0 && (
        <div>
          <div className="text-[10px] uppercase tracking-[0.18em] text-muted-foreground/60 mb-1.5 px-1">
            files edited
          </div>
          <ul className="border border-border divide-y divide-border">
            {files.map((f) => (
              <li key={f.path}>
                <button
                  onClick={() => openFile(f.path)}
                  className="group w-full text-left px-3 py-2 flex items-center gap-3 hover:bg-muted/40 transition-colors"
                  title={f.path}
                >
                  <FileText className="h-3 w-3 text-muted-foreground/60 shrink-0" />
                  <div className="flex-1 min-w-0">
                    <div className="text-sm text-foreground truncate font-mono">
                      {displayPath(f.path)}
                    </div>
                    <div className="text-[11px] text-muted-foreground truncate">
                      {f.path}
                    </div>
                  </div>
                  <span className="text-[11px] text-muted-foreground tabular-nums shrink-0">
                    {f.frame_count}
                  </span>
                  <ExternalLink className="h-3 w-3 text-muted-foreground/40 group-hover:text-foreground transition-colors shrink-0" />
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}
