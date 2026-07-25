"use client";

import React from "react";
import type { SettingsField } from "./settings-search";
import { Github, FileText, FolderOpen } from "lucide-react";
import { open } from "@tauri-apps/plugin-shell";
import { revealItemInDir } from "@tauri-apps/plugin-opener";
import { commands } from "@/lib/utils/tauri";
import { useToast } from "@/components/ui/use-toast";

/** Settings search index for this section. */
export const searchIndex: SettingsField[] = [
  { label: "Documentation", keywords: ["docs", "readme", "help"] },
  { label: "Report an issue", keywords: ["bug", "github", "issue"] },
  { label: "Open logs folder", keywords: ["logs", "debug", "diagnostics"] },
];

const REPO = "https://github.com/Rafaelpta/litepipe";

// litepipe: the upstream help panel linked to the vendor's docs, video
// tutorials, feature-request board, Discord, and a "send logs" button that
// uploaded the user's logs to their support servers. litepipe is a local,
// community project, so support lives on GitHub and logs stay on the machine:
// the button below just opens the local logs folder so a user can attach a
// file to an issue themselves.
export function FeedbackSection() {
  const { toast } = useToast();

  const openLogsFolder = async () => {
    try {
      const res = await commands.getLogFiles();
      if (res.status === "ok" && res.data.length > 0) {
        await revealItemInDir(res.data[0].path);
      } else {
        toast({ title: "no log files found yet" });
      }
    } catch (e) {
      toast({ title: "couldn't open logs folder", description: String(e), variant: "destructive" });
    }
  };

  return (
    <div className="space-y-5" data-testid="section-help">
      <p className="text-muted-foreground text-sm mb-4">
        Get help, report a bug, or grab your logs
      </p>

      <div className="space-y-2">
        <div className="px-3 py-2.5 bg-card border border-border rounded-md">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5">
              <FileText className="h-4 w-4 text-muted-foreground shrink-0" />
              <div>
                <h3 className="text-sm font-medium text-foreground">Documentation</h3>
                <p className="text-xs text-muted-foreground">readme, build, and design notes</p>
              </div>
            </div>
            <button
              onClick={() => open(`${REPO}#readme`)}
              className="text-xs text-muted-foreground hover:text-foreground transition-colors duration-150"
            >
              open →
            </button>
          </div>
        </div>

        <div className="px-3 py-2.5 bg-card border border-border rounded-md">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5">
              <Github className="h-4 w-4 text-muted-foreground shrink-0" />
              <div>
                <h3 className="text-sm font-medium text-foreground">Report an issue</h3>
                <p className="text-xs text-muted-foreground">bugs and feature requests</p>
              </div>
            </div>
            <button
              data-testid="help-github-issues"
              onClick={() => open(`${REPO}/issues`)}
              className="text-xs text-muted-foreground hover:text-foreground transition-colors duration-150"
            >
              open →
            </button>
          </div>
        </div>

        <div className="px-3 py-2.5 bg-card border border-border rounded-md">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5">
              <FolderOpen className="h-4 w-4 text-muted-foreground shrink-0" />
              <div>
                <h3 className="text-sm font-medium text-foreground">Open logs folder</h3>
                <p className="text-xs text-muted-foreground">attach a log file to your issue</p>
              </div>
            </div>
            <button
              onClick={openLogsFolder}
              className="text-xs text-muted-foreground hover:text-foreground transition-colors duration-150"
            >
              reveal →
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
