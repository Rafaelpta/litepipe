"use client";

import { getStore, useSettings } from "@/lib/hooks/use-settings";

import React, { useEffect, useState, useRef, useCallback, ErrorInfo } from "react";
import NotificationHandler from "@/components/notification-handler";
import { useToast } from "@/components/ui/use-toast";
import { useOnboarding } from "@/lib/hooks/use-onboarding";
import { checkFirstRunNotification } from "@/lib/notifications";

import { useHealthCheck } from "@/lib/hooks/use-health-check";

import { commands } from "@/lib/utils/tauri";
import localforage from "localforage";
import { UpdateBanner } from "@/components/update-banner";
import { ModelDownloadTracker } from "@/components/model-download-tracker";
import Timeline from "@/components/rewind/timeline";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { RefreshCw, AlertTriangle, WifiOff, Check, X } from "lucide-react";
import { useFeedbackStore } from "@/lib/stores/feedback-store";

import { PermissionButtons } from "@/components/status/permission-buttons";
import { PermissionBanner } from "@/components/status/permission-banner";
import { usePlatform } from "@/lib/hooks/use-platform";
import SplashScreen from "@/components/splash-screen";
import { useTimelineStore } from "@/lib/hooks/use-timeline-store";
import { hasCachedData } from "@/lib/hooks/use-timeline-cache";

function TimelineErrorFallback({
  error,
  onRetry,
}: {
  error: Error | null;
  onRetry: () => void;
}) {
  const openFeedback = useFeedbackStore((s) => s.openFeedback);
  return (
    <div className="flex items-center justify-center h-screen bg-background">
      <div className="text-center space-y-4 max-w-md">
        <p className="text-lg font-medium">timeline crashed</p>
        <p className="text-sm text-muted-foreground">{error?.message}</p>
        <div className="flex gap-2 justify-center">
          <Button onClick={onRetry} variant="outline">
            <RefreshCw className="h-4 w-4 mr-2" />
            retry
          </Button>
          <Button
            variant="outline"
            onClick={() => openFeedback(`Timeline crashed: ${error?.message || "unknown error"}`)}
          >
            report crash
          </Button>
        </div>
      </div>
    </div>
  );
}

class TimelineErrorBoundary extends React.Component<
  { children: React.ReactNode },
  { hasError: boolean; error: Error | null }
> {
  constructor(props: { children: React.ReactNode }) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("Timeline crashed:", error.message, error.stack, info.componentStack);
  }

  render() {
    if (this.state.hasError) {
      return (
        <TimelineErrorFallback
          error={this.state.error}
          onRetry={() => this.setState({ hasError: false, error: null })}
        />
      );
    }
    return this.props.children;
  }
}

export default function OverlayPage() {
  const { settings, updateSettings, reloadStore, isSettingsLoaded, loadingError } = useSettings();
  const { toast } = useToast();
  const openFeedback = useFeedbackStore((s) => s.openFeedback);
  const { onboardingData } = useOnboarding();
  const { isServerDown, isLoading: isHealthLoading } = useHealthCheck();
  const { isMac } = usePlatform();
  const [isRestarting, setIsRestarting] = useState(false);
  const isProcessingRef = useRef(false);
  
  // Optimistic UI: track if user has any data (cached or live)
  const { frames, isConnected, loadFromCache } = useTimelineStore();
  const [hasAnyData, setHasAnyData] = useState(false);
  
  // Check for cached data on mount
  useEffect(() => {
    const checkCache = async () => {
      const hasCached = await hasCachedData();
      setHasAnyData(hasCached);
      if (hasCached) {
        // Load cached frames immediately for instant display
        loadFromCache();
      }
    };
    checkCache();
  }, [loadFromCache]);
  
  // Update hasAnyData when frames change
  useEffect(() => {
    if (frames.length > 0) {
      setHasAnyData(true);
    }
  }, [frames.length]);

  // Load onboarding status on mount
  useEffect(() => {
    const { loadOnboardingStatus } = useOnboarding.getState();
    loadOnboardingStatus();
  }, []);

  // Check if first-run notification should fire
  useEffect(() => {
    checkFirstRunNotification();
  }, []);

  useEffect(() => {
    const getAudioDevices = async () => {
      const store = await getStore();
      const devices = (await store.get("audioDevices")) as string[];
      return devices;
    };

    // Cleanup function placeholder if needed
    return () => {
      // Any cleanup logic can go here
    };
  }, []);

  useEffect(() => {
    // add a shortcut to hide overlay window when pressed esc
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        commands.closeWindow("Main");
      }
    };

    window.addEventListener("keydown", handleEscape);
    return () => window.removeEventListener("keydown", handleEscape);
  }, []);

  useEffect(() => {
    const checkScreenPermissionRestart = async () => {
      const restartPending = await localforage.getItem(
        "screenPermissionRestartPending"
      );
      if (restartPending) {
        // Clear the restart pending flag
        await localforage.removeItem("screenPermissionRestartPending");
        try {
          await commands.showWindow("Onboarding");
        } catch (error) {
          console.error("Failed to show onboarding window:", error);
        }
      }
    };

    // Always call this effect, but only execute logic when onboarding data is loaded
    if (onboardingData.isCompleted !== undefined) {
      checkScreenPermissionRestart();
    }
  }, [onboardingData.isCompleted]);

  // litepipe: no cloud sync.

  const handleRestartServer = async () => {
    setIsRestarting(true);
    try {
      toast({
        title: "restarting server",
        description: "stopping litepipe server...",
        duration: 3000,
      });

      // Stop the server first
      await commands.stopScreenpipe();
      
      // Wait for proper cleanup
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      toast({
        title: "restarting server",
        description: "starting litepipe server...",
        duration: 3000,
      });

      // Start the server
      await commands.spawnScreenpipe(null);
      
      toast({
        title: "server restarted",
        description: "litepipe server has been restarted successfully.",
        duration: 3000,
      });
    } catch (error) {
      console.error("failed to restart server:", error);
      toast({
        title: "restart failed",
        description: (
          <span>
            failed to restart litepipe server.{" "}
            <button
              type="button"
              className="underline underline-offset-2 text-inherit opacity-80 hover:opacity-100"
              onClick={() => openFeedback(`Server restart failed: ${error instanceof Error ? error.message : String(error)}`)}
            >
              report issue
            </button>
          </span>
        ),
        variant: "destructive",
        duration: 8000,
      });
    } finally {
      setIsRestarting(false);
    }
  };

  // Determine what to show:
  // 1. If user has data (cached or live) -> always show timeline, even if server is down
  // 2. If no data AND server is down -> show server error screen
  // 3. If no data AND server is starting -> show loading
  const showTimeline = hasAnyData || !isServerDown;
  const showServerError = !hasAnyData && isServerDown;

  return (
    <div className="flex flex-col items-center flex-1 mx-auto relative scrollbar-hide">
      {/* Transparent titlebar area - no drag region to prevent accidental window moves */}
      <div className="h-8 bg-gradient-to-b from-black/15 to-transparent w-full fixed top-0 left-0 z-[1000] pointer-events-none" />

      <NotificationHandler />
      <PermissionBanner />
      {/* Only render content after settings are loaded */}
      {isSettingsLoaded ? (
        <>
          <ModelDownloadTracker />
          <UpdateBanner />
          
          {showTimeline ? (
            <div className="w-full scrollbar-hide bg-background relative">
              {/* Subtle disconnected indicator - only show if we have data but no connection */}
              {hasAnyData && !isConnected && isServerDown && (
                <div className="fixed top-10 right-4 z-50 flex items-center gap-2 px-3 py-1.5 bg-muted/90 backdrop-blur-sm rounded-full text-xs text-muted-foreground border">
                  <WifiOff className="h-3 w-3" />
                  <span>reconnecting...</span>
                </div>
              )}
              
              {/* Show connecting overlay only if NO data and still loading */}
              {!hasAnyData && isHealthLoading && (
                <div className="absolute inset-0 z-50 flex items-center justify-center bg-background/80 backdrop-blur-sm">
                  <div className="flex flex-col items-center gap-3">
                    <RefreshCw className="h-6 w-6 animate-spin text-muted-foreground" />
                    <p className="text-sm text-muted-foreground">connecting to litepipe...</p>
                  </div>
                </div>
              )}
              <TimelineErrorBoundary>
                <Timeline />
              </TimelineErrorBoundary>
            </div>
          ) : showServerError ? (
            <div className="flex items-center justify-center h-screen p-4 bg-background w-full">
              <div className="max-w-lg w-full space-y-6">
                {/* Header */}
                <div className="text-center space-y-4">
                  <div className="flex flex-col items-center gap-3">
                    <div className="w-16 h-16 rounded-full bg-destructive/20 flex items-center justify-center border border-destructive/15">
                      <AlertTriangle className="w-8 h-8 text-destructive" />
                    </div>
                    <div>
                      <h2 className="text-2xl font-bold">Server Not Active</h2>
                      <p className="text-muted-foreground mt-2">
                        The litepipe server is not running. Start the server or check permissions to continue.
                      </p>
                    </div>
                  </div>
                </div>

                {/* Actions Card */}
                <div className="bg-card border border-border rounded-lg p-6 space-y-6">
                  {/* Server Control */}
                  <div className="space-y-4">
                    <div className="flex items-center justify-between">
                      <div>
                        <h3 className="font-semibold">Server Control</h3>
                        <p className="text-sm text-muted-foreground">
                          Start or restart the litepipe server
                        </p>
                      </div>
                      <Button
                        onClick={handleRestartServer}
                        disabled={isRestarting}
                        className="flex items-center gap-2"
                      >
                        <RefreshCw className={`h-4 w-4 ${isRestarting ? 'animate-spin' : ''}`} />
                        {isRestarting ? "Starting..." : "Start Server"}
                      </Button>
                    </div>
                  </div>

                  {/* Permissions Section - Only show on Mac */}
                  {isMac && (
                    <>
                      <Separator />
                      <div className="space-y-4">
                        <div>
                          <h3 className="font-semibold">System Permissions</h3>
                          <p className="text-sm text-muted-foreground">
                            Ensure litepipe has the necessary permissions to function properly
                          </p>
                        </div>
                        <div className="space-y-3">
                          <div className="flex items-center justify-between">
                            <span className="text-sm font-medium">Screen Recording</span>
                            <PermissionButtons type="screen" hideWindowOnClick />
                          </div>
                          <div className="flex items-center justify-between">
                            <span className="text-sm font-medium">Audio Recording</span>
                            <PermissionButtons type="audio" hideWindowOnClick />
                          </div>

                        </div>
                      </div>
                    </>
                  )}
                </div>

                {/* Help Actions */}
                <div className="flex items-center justify-center gap-3">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => commands.closeWindow("Main")}
                    className="text-muted-foreground"
                  >
                    <X className="h-4 w-4 mr-1.5" />
                    close
                  </Button>
                </div>
              </div>
            </div>
          ) : (
            // Fallback loading state
            <div className="flex items-center justify-center h-screen">
              <div className="flex flex-col items-center gap-3">
                <RefreshCw className="h-6 w-6 animate-spin text-muted-foreground" />
                <p className="text-sm text-muted-foreground">starting up...</p>
              </div>
            </div>
          )}
        </>
      ) : (
        <SplashScreen />
      )}
    </div>
  );
}
