"use client";

import { useEffect } from "react";
import { useToast } from "@/components/ui/use-toast";
import { useChangelogDialog } from "@/lib/hooks/use-changelog-dialog";
import { useStatusDialog } from "@/lib/hooks/use-status-dialog";
import { useSettings } from "@/lib/hooks/use-settings";
import { commands } from "@/lib/utils/tauri";
import { listen, emit } from "@tauri-apps/api/event";
import { onOpenUrl } from "@tauri-apps/plugin-deep-link";
import { openSettingsWindow } from "@/lib/utils/window";
import { useTimelineStore } from "@/lib/hooks/use-timeline-store";
import {
  openScreenpipeViewerLink,
  screenpipeViewerPathFromHref,
} from "@/components/markdown";

export function DeeplinkHandler() {
  const { toast } = useToast();
  const { setShowChangelogDialog } = useChangelogDialog();
  const { open: openStatusDialog } = useStatusDialog();
  const { reloadStore } = useSettings();
  const setPendingNavigation = useTimelineStore((s) => s.setPendingNavigation);

  useEffect(() => {
    const emitMeetingNoteRouteWithRetries = async (
      meetingId: number,
      transcript: boolean,
    ) => {
      const payload = { meetingId, transcript };
      for (const delayMs of [0, 250, 750, 1500]) {
        if (delayMs > 0) {
          await new Promise((resolve) => setTimeout(resolve, delayMs));
        }
        await emit("navigate", { url: "/home?section=meetings" });
        await emit("open-meeting-note", payload);
      }
    };

    // Shared deep-link URL processor used by both the native plugin callback
    // and the custom Tauri event from single-instance handoff.
    const processDeepLinkUrl = async (url: string) => {
      const parsedUrl = new URL(url);

      // litepipe: no account. The upstream api_key and subscription deep links
      // are gone; only local navigation deep links are handled here.

      // Handle Google Calendar OAuth callback
      if (
        parsedUrl.host === "auth" &&
        parsedUrl.pathname?.includes("google-calendar")
      ) {
        const success = parsedUrl.searchParams.get("success") === "true";
        const error = parsedUrl.searchParams.get("error");
        await emit("google-calendar-auth-result", { success, error });
        // Bring the settings window to the front so the user lands back
        // where they started (instead of staring at the timeline).
        await openSettingsWindow();
        toast({
          title: success
            ? "google calendar connected!"
            : "google calendar connection failed",
          description: success
            ? "your google calendar is now linked"
            : error || "something went wrong",
          variant: success ? undefined : "destructive",
        });
      }

      if (url.includes("settings") || url.includes("home")) {
        await openSettingsWindow();
      }

      if (url.includes("changelog")) {
        setShowChangelogDialog(true);
      }

          if (url.includes("onboarding")) {
            try {
              await commands.showWindow("Onboarding");
              // Forward specific deep link events so onboarding components can react.
              // Use a dedicated event name to avoid re-triggering the main deep-link listener.
              if (url.includes("onboarding-read-complete")) {
                await emit("onboarding-read-complete", url);
              }
            } catch (error) {
              console.error("Failed to show onboarding window:", error);
            }
          }

      if (url.includes("status")) {
        openStatusDialog();
      }

      // Handle timeline deep links:
      //   screenpipe://timeline?timestamp=ISO8601
      //   screenpipe://timeline?start_time=ISO8601&end_time=ISO8601
      if (parsedUrl.pathname === "timeline" || parsedUrl.host === "timeline") {
        const timestamp =
          parsedUrl.searchParams.get("timestamp") ||
          parsedUrl.searchParams.get("start_time");
        if (timestamp) {
          try {
            const date = new Date(timestamp);
            if (!isNaN(date.getTime())) {
              // Write to store (persists across mounts) AND emit event (instant if timeline is mounted)
              setPendingNavigation({ timestamp });
              await commands.showWindow("Main");
              await emit("navigate-to-timestamp", timestamp);
              toast({
                title: "navigating to timestamp",
                description: `jumping to ${date.toLocaleString()}`,
              });
            } else {
              throw new Error("Invalid date");
            }
          } catch (error) {
            console.error("Failed to parse timeline timestamp:", error);
            toast({
              title: "invalid timestamp",
              description: "could not parse the timeline link",
              variant: "destructive",
            });
          }
        }
      }

      // Handle pipe install deep links: screenpipe://install-pipe?url=<encoded-url>
      if (
        parsedUrl.host === "install-pipe" ||
        parsedUrl.pathname === "install-pipe"
      ) {
        const pipeUrl = parsedUrl.searchParams.get("url");
        if (pipeUrl) {
          await emit("install-pipe", { url: pipeUrl, name: parsedUrl.searchParams.get("name") || undefined });
        }
      }

      // Handle in-app file viewer: screenpipe://view?path=<encoded-path>
      // Notification bodies with markdown links to local files are rewritten
      // to this scheme by the /notify route in src-tauri/src/notifications/rewrite.rs
      if (parsedUrl.host === "view" || parsedUrl.pathname === "view") {
        const filePath = screenpipeViewerPathFromHref(url);
        if (filePath) {
          try {
            await openScreenpipeViewerLink(url);
          } catch (error) {
            console.error("Failed to open viewer:", error);
            toast({
              title: "couldn't open file",
              description: filePath,
              variant: "destructive",
            });
          }
        }
      }

      // Handle frame deep links: screenpipe://frame/12345
      if (parsedUrl.pathname?.startsWith("/frame/") || parsedUrl.host === "frame") {
        const frameId = url.split("frame/")[1]?.replace(/^\//, "");
        if (frameId) {
          try {
            // Store frame navigation — timeline will resolve frame → timestamp
            setPendingNavigation({ timestamp: "", frameId });
            await commands.showWindow("Main");
            await emit("navigate-to-frame", frameId);
            toast({
              title: "navigating to frame",
              description: `jumping to frame ${frameId}`,
            });
          } catch (error) {
            console.error("Failed to navigate to frame:", error);
          }
        }
      }

      // Handle meeting note deep links:
      //   screenpipe://meeting/123?live=1
      //   screenpipe://meeting?id=123
      if (parsedUrl.host === "meeting" || parsedUrl.pathname?.startsWith("/meeting/")) {
        const pathId =
          parsedUrl.host === "meeting"
            ? parsedUrl.pathname.replace(/^\/+/, "").split("/")[0]
            : parsedUrl.pathname.replace(/^\/meeting\/?/, "").split("/")[0];
        const meetingId = parsedUrl.searchParams.get("id") || pathId;
        if (meetingId) {
          const numericId = Number(meetingId);
          if (!Number.isFinite(numericId)) return;
          const transcript = parsedUrl.searchParams.get("live") !== "0";
          await commands.showWindowActivated({ Home: { page: "meetings" } });
          await emitMeetingNoteRouteWithRetries(numericId, transcript);
        }
      }
    };

    const setupDeepLink = async () => {
      const unsubscribeDeepLink = await onOpenUrl(async (urls) => {
        console.log("received deep link urls:", urls);
        for (const url of urls) {
          await processDeepLinkUrl(url);
        }
      });
      return unsubscribeDeepLink;
    };

    let deepLinkUnsubscribe: (() => void) | undefined;

    setupDeepLink().then((unsubscribe) => {
      deepLinkUnsubscribe = unsubscribe;
    });

    const unlisten = Promise.all([
      // Listen for deep-link URLs forwarded from single-instance handoff
      // (emitted by the /focus endpoint or the single-instance plugin callback)
      listen<string>("deep-link-received", async (event) => {
        console.log("received deep-link-received event:", event.payload);
        await processDeepLinkUrl(event.payload);
      }),

      listen("shortcut-start-recording", async () => {
        await commands.startCapture();

        toast({
          title: "recording started",
          description: "screen recording has been initiated",
        });
      }),

      listen("shortcut-stop-recording", async () => {
        await commands.stopCapture();

        toast({
          title: "recording paused",
          description: "capture paused — pipes and search still available",
        });
      }),

      listen("shortcut-start-audio", async () => {
        await commands.stopScreenpipe();
        await commands.spawnScreenpipe(null);

        toast({
          title: "audio recording started",
          description: "audio capture has been enabled",
        });
      }),

      listen("shortcut-stop-audio", async () => {
        await commands.stopScreenpipe();
        await commands.spawnScreenpipe(null);

        toast({
          title: "audio recording stopped",
          description: "audio capture has been disabled",
        });
      }),

      listen("cli-login", async (event) => {
        console.log("received cli-login event:", event);
        await reloadStore();
      }),
    ]);

    return () => {
      if (deepLinkUnsubscribe) {
        deepLinkUnsubscribe();
      }
      unlisten.then((unsubscribes) => {
        unsubscribes.forEach((unsubscribe) => unsubscribe());
      });
    };
  }, [toast, setShowChangelogDialog, openStatusDialog, reloadStore, setPendingNavigation]);

  return null; // This component doesn't render anything
} 
