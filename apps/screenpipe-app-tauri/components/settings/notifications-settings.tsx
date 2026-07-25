"use client";

import React from "react";
import { useSettings, Settings } from "@/lib/hooks/use-settings";
import { Switch } from "@/components/ui/switch";
import type { SettingsField } from "./settings-search";

/** Settings search index for this section. Co-located with the component so adding a field here means updating one file. See `SettingsField` in `./settings-search` for the schema. */
export const searchIndex: SettingsField[] = [
  { label: "Capture stalls" },
  { label: "App updates" },
  { label: "Pipe notifications" },
  { label: "Display changes" },
  { label: "Meeting live notes" },
  { label: "Meeting audio not capturing" },
  { label: "Live transcript not flowing" },
];
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { commands } from "@/lib/utils/tauri";

const defaultPrefs = {
  captureStalls: true,
  appUpdates: true,
  pipeSuggestions: true,
  pipeNotifications: true,
  displayChanges: true,
  meetingLiveNotes: true,
  audioCaptureStalled: true,
  liveTranscriptStalled: true,
  mutedPipes: [] as string[],
};

export function NotificationsSettings() {
  const { settings, updateSettings } = useSettings();

  if (!settings) return null;

  const prefs = settings.notificationPrefs || defaultPrefs;

  const updatePref = (key: string, value: boolean) => {
    updateSettings({
      notificationPrefs: { ...prefs, [key]: value },
    } as Partial<Settings>);
  };

  return (
    <div className="space-y-6">
      <div>
        <p className="text-muted-foreground text-sm">
          Control which notifications litepipe sends you.
        </p>
      </div>

      <div className="space-y-1">
        {/* Capture stalls */}
        <div className="flex items-center justify-between py-3 border-b border-border">
          <div>
            <p className="text-sm font-medium">Capture stalls <span className="text-[10px] font-normal text-muted-foreground/70 ml-1">experimental</span></p>
            <p className="text-xs text-muted-foreground">
              Alert when audio or screen capture stops — may send false positives
            </p>
          </div>
          <Switch
            data-testid="notification-pref-capture-stalls"
            checked={prefs.captureStalls ?? true}
            onCheckedChange={(v) => {
              updateSettings({
                notificationPrefs: { ...prefs, captureStalls: v },
                showRestartNotifications: v,
              } as Partial<Settings>);
            }}
          />
        </div>

        {/* App updates */}
        <div className="flex items-center justify-between py-3 border-b border-border">
          <div>
            <p className="text-sm font-medium">App updates</p>
            <p className="text-xs text-muted-foreground">
              New version available
            </p>
          </div>
          <Switch
            data-testid="notification-pref-app-updates"
            checked={prefs.appUpdates ?? true}
            onCheckedChange={(v) => updatePref("appUpdates", v)}
          />
        </div>

        {/* Pipe notifications */}
        <div className="flex items-center justify-between py-3 border-b border-border">
          <div>
            <p className="text-sm font-medium">Pipe notifications</p>
            <p className="text-xs text-muted-foreground">
              Alerts from installed pipes
            </p>
          </div>
          <Switch
            data-testid="notification-pref-pipe-notifications"
            checked={prefs.pipeNotifications ?? true}
            onCheckedChange={(v) => updatePref("pipeNotifications", v)}
          />
        </div>

        {/* Display changes */}
        <div className="flex items-center justify-between py-3 border-b border-border">
          <div>
            <p className="text-sm font-medium">Display changes</p>
            <p className="text-xs text-muted-foreground">
              Toast when a monitor is plugged, unplugged, or switched (clamshell, dock)
            </p>
          </div>
          <Switch
            data-testid="notification-pref-display-changes"
            checked={prefs.displayChanges ?? true}
            onCheckedChange={(v) => updatePref("displayChanges", v)}
          />
        </div>

        {/* Meeting live notes */}
        <div className="flex items-center justify-between py-3 border-b border-border">
          <div>
            <p className="text-sm font-medium">Meeting live notes</p>
            <p className="text-xs text-muted-foreground">
              Prompt to open a live note when a meeting is detected
            </p>
          </div>
          <Switch
            data-testid="notification-pref-meeting-live-notes"
            checked={prefs.meetingLiveNotes ?? true}
            onCheckedChange={(v) => updatePref("meetingLiveNotes", v)}
          />
        </div>

        {/* Meeting audio stall */}
        <div className="flex items-center justify-between py-3 border-b border-border">
          <div>
            <p className="text-sm font-medium">Meeting audio not capturing</p>
            <p className="text-xs text-muted-foreground">
              OS notification when a meeting is detected but no audio reaches the recorder within 60s
            </p>
          </div>
          <Switch
            data-testid="notification-pref-audio-capture-stalled"
            checked={prefs.audioCaptureStalled ?? true}
            onCheckedChange={(v) => updatePref("audioCaptureStalled", v)}
          />
        </div>

        {/* Meeting transcript stall */}
        <div className="flex items-center justify-between py-3 border-b border-border">
          <div>
            <p className="text-sm font-medium">Live transcript not flowing</p>
            <p className="text-xs text-muted-foreground">
              In-app alert when audio is captured but no live transcript arrives within 60s
            </p>
          </div>
          <Switch
            data-testid="notification-pref-live-transcript-stalled"
            checked={prefs.liveTranscriptStalled ?? true}
            onCheckedChange={(v) => updatePref("liveTranscriptStalled", v)}
          />
        </div>
      </div>

      {/* Muted pipes */}
      {(prefs.mutedPipes?.length ?? 0) > 0 && (
        <div className="space-y-2">
          <p className="text-xs font-medium text-muted-foreground uppercase tracking-wider">
            Muted pipes
          </p>
          <div className="flex flex-wrap gap-1.5">
            {prefs.mutedPipes.map((pipe) => (
              <span
                key={pipe}
                className="inline-flex items-center gap-1.5 px-2 py-1 bg-muted rounded text-xs text-muted-foreground"
              >
                {pipe}
                <button
                  className="hover:text-foreground transition-colors"
                  onClick={() => {
                    const updated = { ...prefs };
                    updated.mutedPipes = updated.mutedPipes.filter(
                      (p) => p !== pipe
                    );
                    updateSettings({ notificationPrefs: updated } as Partial<Settings>);
                  }}
                >
                  ✕
                </button>
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
