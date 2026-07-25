"use client";

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { open as openUrl } from "@tauri-apps/plugin-shell";
import { revealItemInDir } from "@tauri-apps/plugin-opener";
import { commands } from "@/lib/utils/tauri";
import { useFeedbackStore } from "@/lib/stores/feedback-store";

const REPO = "https://github.com/Rafaelpta/litepipe";

// litepipe: the upstream dialog uploaded logs to the vendor's support servers.
// litepipe has no such service; reporting goes to GitHub and logs stay local.
export function FeedbackDialog() {
  const { open, closeFeedback } = useFeedbackStore();

  const openLogsFolder = async () => {
    try {
      const res = await commands.getLogFiles();
      if (res.status === "ok" && res.data.length > 0) {
        await revealItemInDir(res.data[0].path);
      }
    } catch {
      // best effort
    }
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && closeFeedback()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="text-sm font-medium">report an issue</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <p className="text-sm text-muted-foreground">
            Open an issue on GitHub. If it helps, reveal your local logs folder and
            attach a log file. Nothing is uploaded automatically.
          </p>
          <div className="flex gap-2">
            <Button onClick={() => { openUrl(`${REPO}/issues/new`); closeFeedback(); }}>
              Open GitHub issue
            </Button>
            <Button variant="outline" onClick={openLogsFolder}>
              Reveal logs
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
