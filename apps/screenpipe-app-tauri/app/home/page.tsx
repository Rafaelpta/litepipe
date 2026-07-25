"use client";

import React, { useEffect, useState, useRef, Suspense, useCallback } from "react";
import {
  Settings as SettingsIcon,
  Clock,
  HelpCircle,
  Monitor,
  Mic,
  MicOff,
  Volume2,
  VolumeX,
  PanelLeftClose,
  PanelLeftOpen,
  Search,
} from "lucide-react";
import { useOverlayData } from "@/app/shortcut-reminder/use-overlay-data";
import { cn } from "@/lib/utils";
import { AppSidebar, SidebarProvider, useSidebarContext } from "@/components/app-sidebar";
import { UpdateBanner } from "@/components/update-banner";
import { usePlatform } from "@/lib/hooks/use-platform";
import { useIsFullscreen } from "@/lib/hooks/use-is-fullscreen";
import { FeedbackSection } from "@/components/settings/feedback-section";
import Timeline from "@/components/rewind/timeline";
import { useQueryState } from "nuqs";
import { listen } from "@tauri-apps/api/event";
import { useSettings } from "@/lib/hooks/use-settings";
import { commands } from "@/lib/utils/tauri";
import { formatShortcutDisplay } from "@/lib/chat-utils";
import { useRouter } from "next/navigation";
import { localFetch } from "@/lib/api";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";

// All valid URL sections for the home page
// litepipe: reduced to the capture Timeline + Help. Chat, memories, meetings,
// pipes and connections were removed with the frontend feature cull.
const ALL_SECTIONS = [
  "timeline", "help",
  "feedback", // backwards compat → maps to "help"
];

// Settings sections that should redirect to /settings
const SETTINGS_SECTIONS = new Set<string>([
  "account", "recording", "ai", "general", "display", "shortcuts", "notifications",
  "privacy", "storage", "usage", "speakers",
  "disk-usage", "cloud-archive", "cloud-sync", // backwards compat → maps to "storage"
]);

function HomeContent() {
  const router = useRouter();
  const { isMac } = usePlatform();
  // In fullscreen, macOS hides the traffic lights — collapse the
  // reservation that keeps the top-left action icons clear of them.
  const isFullscreen = useIsFullscreen();
  const reserveTrafficLights = isMac && !isFullscreen;
  const [activeSection, setActiveSection] = useQueryState("section", {
    defaultValue: "timeline",
    parse: (value) => {
      if (value === "feedback") return "help"; // backwards compat
      // Settings sections redirect to /settings page
      if (SETTINGS_SECTIONS.has(value)) return value; // handled by redirect effect below
      return ALL_SECTIONS.includes(value) ? value : "timeline";
    },
    serialize: (value) => value,
  });

  const { settings } = useSettings();
  const { isTranslucent } = useSidebarContext();

  // Redirect settings sections to the standalone settings page
  useEffect(() => {
    if (SETTINGS_SECTIONS.has(activeSection)) {
      const section = activeSection === "disk-usage" || activeSection === "cloud-archive" || activeSection === "cloud-sync"
        ? "storage"
        : activeSection;
      router.push(`/settings?section=${section}`);
    }
  }, [activeSection, router]);

  // Timeline can be turned off in Display settings. When it is, the nav item is
  // gone, so bounce out of the (now unreachable) timeline section to help.
  useEffect(() => {
    if ((settings.disableTimeline ?? false) && activeSection === "timeline") {
      setActiveSection("help");
    }
  }, [settings.disableTimeline, activeSection, setActiveSection]);

  // Sidebar collapse state (persisted in localStorage)
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

  useEffect(() => {
    const stored = localStorage.getItem("sidebar-collapsed");
    if (stored === "true") setSidebarCollapsed(true);
  }, []);

  const toggleSidebar = useCallback(() => {
    setSidebarCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem("sidebar-collapsed", String(next));
      return next;
    });
  }, []);

  // Cmd+B / Ctrl+B to toggle sidebar
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "b") {
        e.preventDefault();
        toggleSidebar();
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [toggleSidebar]);

  const overlayData = useOverlayData({
    includeDeviceLevels: false,
    includeOcrPulse: false,
    minIntervalMs: 1000,
    quantize: true,
  });

  // Fetch actual recording devices. Audio comes from /audio/device/status so
  // user-paused devices stay visible and can be resumed from the same control.
  interface RecordingDevice {
    name: string;
    fullName: string;
    kind: "monitor" | "input" | "output";
    active: boolean;
  }
  interface AudioDeviceStatus {
    name: string;
    is_running: boolean;
    is_user_disabled?: boolean;
  }
  const [recordingDevices, setRecordingDevices] = useState<RecordingDevice[]>([]);
  const recordingDevicesSnapshotRef = useRef("");

  useEffect(() => {
    let cancelled = false;
    const fetchDevices = () => {
      Promise.all([
        localFetch("/health")
          .then((r) => r.ok ? r.json() : null)
          .catch(() => null),
        localFetch("/audio/device/status")
          .then((r) => r.ok ? r.json() : null)
          .catch(() => null),
      ])
        .then(([health, audioStatus]: [
          { monitors?: string[]; device_status_details?: string } | null,
          AudioDeviceStatus[] | null,
        ]) => {
          if (cancelled) return;
          const devices: RecordingDevice[] = [];
          // Parse monitors — filter to only those actually being recorded
          if (health?.monitors) {
            const monitorIds: string[] = settings.monitorIds ?? ["default"];
            const useAll = settings.useAllMonitors ?? true;
            for (const name of health.monitors) {
              // If user selected specific monitors, filter to only those
              if (!useAll && monitorIds.length > 0 && monitorIds[0] !== "default") {
                // Health format: "Display 3 (1920x1080)"
                // Stable ID format: "Display 3_1920x1080_0,0"
                const healthName = name.split(" (")[0];
                const matched = monitorIds.some((id) => {
                  const idName = id.split("_")[0];
                  return healthName === idName;
                });
                if (!matched) continue;
              }
              devices.push({ name, fullName: name, kind: "monitor", active: true });
            }
          }

          const visibleAudioDevices = Array.isArray(audioStatus)
            ? audioStatus.filter((d) => d.is_running || d.is_user_disabled)
            : [];

          if (visibleAudioDevices.length > 0) {
            for (const device of visibleAudioDevices) {
              const kind = device.name.includes("(output)") ? "output" as const : "input" as const;
              const name = device.name.replace(/\s*\((input|output)\)\s*/gi, "").trim();
              devices.push({
                name,
                fullName: device.name,
                kind,
                active: device.is_running,
              });
            }
          } else if (health?.device_status_details) {
            // Fallback for older sidecars that do not expose /audio/device/status.
            // Format: "DeviceName (input): active (last activity: 2s ago)"
            for (const part of health.device_status_details.split(", ")) {
              const match = part.split(": ");
              if (match.length < 2) continue;
              const nameAndType = match[0];
              const active = match[1].startsWith("active");
              const kind = nameAndType.includes("(input)") ? "input" as const
                : nameAndType.includes("(output)") ? "output" as const
                : "input" as const;
              const name = nameAndType.replace(/\s*\((input|output)\)\s*/gi, "").trim();
              const suffix = kind === "input" ? "input" : "output";
              devices.push({ name, fullName: `${name} (${suffix})`, kind, active });
            }
          }
          const snapshot = JSON.stringify(devices);
          if (snapshot !== recordingDevicesSnapshotRef.current) {
            recordingDevicesSnapshotRef.current = snapshot;
            setRecordingDevices(devices);
          }
        })
        .catch(() => {});
    };
    fetchDevices();
    const interval = setInterval(fetchDevices, 10000);
    return () => { cancelled = true; clearInterval(interval); };
  }, [settings.monitorIds, settings.useAllMonitors]);

  const openSettings = useCallback((section: string = "general") => {
    router.push(`/settings?section=${section}`);
  }, [router]);

  // Listen for open-settings events from child components
  useEffect(() => {
    const handler = (e: Event) => {
      const detail = (e as CustomEvent).detail;
      const section = detail?.section ?? "general";
      openSettings(section);
    };
    window.addEventListener("open-settings", handler);
    return () => window.removeEventListener("open-settings", handler);
  }, [openSettings]);

  const renderMainSection = () => {
    switch (activeSection) {
      case "timeline":
        // Timeline can be disabled in Display settings; when it is, fall through
        // to the placeholder (the redirect effect also resets activeSection).
        if (settings.disableTimeline) break;
        return <Timeline embedded />;
      case "help":
        return <FeedbackSection />;
    }
    return (
      <div className="flex flex-col items-center justify-center h-full text-muted-foreground">
        <img src="/128x128.png" alt="litepipe" className="w-16 h-16 opacity-30 mb-4" />
        <p className="text-sm font-mono">litepipe</p>
      </div>
    );
  };

  // Top-level nav items
  // litepipe: reduced to Timeline. Chat, meetings, memories, pipes and
  // connections entries were removed with the frontend feature cull.
  const mainSections = [
    { id: "timeline", label: "Timeline", icon: <Clock className="h-3.5 w-3.5" /> },
  ]
    // Timeline can be turned off in Display settings — when it is, drop it from
    // the sidebar entirely (the "Timeline Disabled" placeholder was poor UX).
    .filter((s) => !(s.id === "timeline" && (settings.disableTimeline ?? false)));

  // Listen for navigation events from other windows (e.g. tray, Rust-side links)
  useEffect(() => {
    const unlisten = listen<{ url: string }>("navigate", (event) => {
      const url = new URL(event.payload.url, window.location.origin);
      const section = url.searchParams.get("section");
      if (!section) return;
      if (SETTINGS_SECTIONS.has(section)) {
        const mapped = section === "disk-usage" || section === "cloud-archive" || section === "cloud-sync"
          ? "storage" : section;
        router.push(`/settings?section=${mapped}`);
      } else {
        const mapped = section === "feedback" ? "help" : section;
        if (ALL_SECTIONS.includes(mapped)) setActiveSection(mapped);
      }
    });
    return () => { unlisten.then((fn) => fn()); };
  }, [setActiveSection, router]);

  const isFullHeight = activeSection === "timeline";

  return (
    <div className={cn("bg-transparent", isFullHeight ? "h-screen overflow-hidden" : "min-h-screen")} data-testid="home-page">
      {/* Drag region — always absolute so it works with full-bleed translucent layout */}
      <div className="absolute top-0 left-0 right-0 h-8 z-10" data-tauri-drag-region />

      <div className="h-screen flex min-h-0">
          {/* Sidebar */}
          <TooltipProvider delayDuration={0}>
          {/* Top-left action buttons — pinned next to the macOS traffic
              lights when the sidebar is EXPANDED. When collapsed these
              live as the first two rows of the icon column instead (see
              below), so the title bar stays clean and the column has a
              single icon per line. Fixed positioning anchors them to the
              viewport so they aren't clipped by AppSidebar's overflow. */}
          {!sidebarCollapsed && (
            <>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={toggleSidebar}
                    aria-label="collapse sidebar"
                    className={cn(
                      // top-1 + p-1 puts the 14px icon's center at y≈15px, matching the
                      // vertical center of the macOS traffic lights (which sit at y≈14).
                      "fixed top-1 z-20 p-1 rounded-md transition-colors",
                      reserveTrafficLights ? "left-[78px]" : "left-2",
                      isTranslucent ? "vibrant-nav-item" : "text-muted-foreground hover:text-foreground hover:bg-muted/50"
                    )}
                  >
                    <PanelLeftClose className="h-3.5 w-3.5" />
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom" className="text-xs">
                  collapse sidebar <kbd className="ml-1 px-1 py-0.5 bg-muted rounded text-[10px]">⌘B</kbd>
                </TooltipContent>
              </Tooltip>

              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={() => {
                      void commands.showWindow({ Search: { query: null } });
                    }}
                    aria-label="search"
                    className={cn(
                      "fixed top-1 z-20 p-1 rounded-md transition-colors",
                      // 28px right of the collapse icon (icon 16 + gap 8 + small breathing).
                      reserveTrafficLights ? "left-[110px]" : "left-9",
                      isTranslucent ? "vibrant-nav-item" : "text-muted-foreground hover:text-foreground hover:bg-muted/50"
                    )}
                  >
                    <Search className="h-3.5 w-3.5" />
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom" className="text-xs">
                  search
                  {!settings.disabledShortcuts.includes("searchShortcut") &&
                  settings.searchShortcut ? (
                    <kbd className="ml-1 px-1 py-0.5 bg-muted rounded text-[10px]">
                      {formatShortcutDisplay(settings.searchShortcut, isMac)}
                    </kbd>
                  ) : null}
                </TooltipContent>
              </Tooltip>
            </>
          )}

          <AppSidebar collapsed={sidebarCollapsed} className="pl-4">
            {!sidebarCollapsed && (
            <div className={cn(isTranslucent ? "vibrant-sidebar-border" : "", "border-b", sidebarCollapsed ? "px-2 py-3" : "px-4 py-3")}>
              {/* Row 1: name (collapse moved out — pinned top-left next
                  to the traffic lights, see above). */}
              <div className={cn("flex items-center", sidebarCollapsed ? "justify-center" : "justify-between")}>
                {!sidebarCollapsed && <h1 className={cn("text-lg font-bold", isTranslucent ? "vibrant-heading" : "text-foreground")}>litepipe</h1>}
              </div>
              {/* Row 2: device status */}
              {!sidebarCollapsed && (() => {
                const monitors = recordingDevices.filter((d) => d.kind === "monitor");
                const inputs = recordingDevices.filter((d) => d.kind === "input");
                const outputs = recordingDevices.filter((d) => d.kind === "output");
                const screenOpacity = overlayData.screenActive ? 0.5 + Math.min(overlayData.captureFps / 2, 0.5) : 0.2;
                const audioOpacity = overlayData.audioActive ? 0.5 + Math.min(overlayData.speechRatio, 0.5) : 0.2;

                const groups: {
                  key: "monitor" | "mic" | "output";
                  icon: typeof Monitor;
                  pausedIcon?: typeof Monitor;
                  count: number;
                  title: string;
                  opacity: number;
                  devices: RecordingDevice[];
                }[] = [];
                if (monitors.length > 0) groups.push({ key: "monitor", icon: Monitor, count: monitors.length, title: monitors.map((d) => d.name).join(", "), opacity: screenOpacity, devices: monitors });
                if (inputs.length > 0) groups.push({ key: "mic", icon: Mic, pausedIcon: MicOff, count: inputs.length, title: inputs.map((d) => d.name).join(", "), opacity: audioOpacity, devices: inputs });
                if (outputs.length > 0) groups.push({ key: "output", icon: Volume2, pausedIcon: VolumeX, count: outputs.length, title: outputs.map((d) => d.name).join(", "), opacity: audioOpacity, devices: outputs });

                return (
                  <div className="flex items-center gap-2 mt-1.5">
                    {groups.map(({ key, icon: ActiveIcon, pausedIcon: PausedIcon, count, title, opacity, devices: groupDevices }) => {
                      const activeCount = groupDevices.filter((d: RecordingDevice) => d.active).length;
                      const allActive = groupDevices.every((d: RecordingDevice) => d.active);
                      const isAudioGroup = key !== "monitor";
                      const Icon = isAudioGroup && !allActive && PausedIcon ? PausedIcon : ActiveIcon;
                      const iconOpacity = isAudioGroup && !allActive ? 0.45 : opacity;
                      const actionLabel = key === "monitor"
                        ? title
                        : allActive
                          ? `${title} — click to pause capture`
                          : activeCount === 0
                            ? `${title} paused — click to resume capture`
                            : `${title} partially paused — click to resume paused devices`;
                      return (
                        <Tooltip key={key}>
                          <TooltipTrigger asChild>
                            <button
                              type="button"
                              aria-label={actionLabel}
                              className={cn(
                                "flex items-center gap-0.5 rounded px-0.5 transition-all",
                                key === "monitor"
                                  ? "cursor-default"
                                  : cn(
                                      "cursor-pointer",
                                      isTranslucent ? "hover:bg-white/10" : "hover:bg-muted"
                                    )
                              )}
                              onClick={key === "monitor" ? undefined : async () => {
                                const endpoint = allActive
                                  ? "/audio/device/stop"
                                  : "/audio/device/start";
                                const targetFullNames = new Set(
                                  groupDevices
                                    .filter((d) => allActive || !d.active)
                                    .map((d) => d.fullName)
                                );
                                if (targetFullNames.size === 0) return;

                                const previousDevices = recordingDevices;
                                setRecordingDevices((prev) =>
                                  prev.map((device) =>
                                    targetFullNames.has(device.fullName)
                                      ? {
                                          ...device,
                                          active: !allActive,
                                        }
                                      : device
                                  )
                                );

                                const results = await Promise.allSettled(
                                  Array.from(targetFullNames).map((deviceName) =>
                                    localFetch(endpoint, {
                                      method: "POST",
                                      headers: { "Content-Type": "application/json" },
                                      body: JSON.stringify({ device_name: deviceName }),
                                    }).then((response) => {
                                      if (!response.ok) {
                                        throw new Error(`audio device toggle failed: ${response.status}`);
                                      }
                                      return response;
                                    })
                                  )
                                );

                                if (results.some((result) => result.status === "rejected")) {
                                  setRecordingDevices(previousDevices);
                                }
                              }}
                            >
                              <Icon
                                aria-hidden="true"
                                focusable="false"
                                className={cn("h-3 w-3 transition-colors", isTranslucent ? "vibrant-sidebar-fg" : "text-foreground")}
                                style={{ opacity: iconOpacity }}
                              />
                              {count > 1 && (
                                <span className={cn("text-[9px] font-medium leading-none", isTranslucent ? "vibrant-sidebar-fg-muted" : "text-foreground/50")}>{count}</span>
                              )}
                            </button>
                          </TooltipTrigger>
                          <TooltipContent side="bottom" className="text-xs">
                            {actionLabel}
                          </TooltipContent>
                        </Tooltip>
                      );
                    })}
                  </div>
                );
              })()}
            </div>
            )}

            {/* Navigation. */}
            <div className="p-2 flex-1 flex flex-col min-h-0">
              {/* Main sections — when collapsed, the column is prefixed
                  with the collapse + search icons (one-per-line, with a
                  divider) so they sit just below the traffic lights. */}
              <div className="space-y-0.5 shrink-0">
                {sidebarCollapsed && (
                  <>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <button
                          onClick={toggleSidebar}
                          aria-label="expand sidebar"
                          className={cn(
                            "w-full flex items-center justify-center px-2.5 py-1.5 rounded-lg transition-all duration-150 text-left group",
                            isTranslucent
                              ? "vibrant-nav-item vibrant-nav-hover"
                              : "hover:bg-card/50 text-muted-foreground hover:text-foreground",
                          )}
                        >
                          <PanelLeftOpen className={cn(
                            "h-3.5 w-3.5 transition-colors flex-shrink-0",
                            isTranslucent ? "vibrant-sidebar-fg-muted" : "text-muted-foreground group-hover:text-foreground"
                          )} />
                        </button>
                      </TooltipTrigger>
                      <TooltipContent side="right" className="text-xs">
                        expand sidebar <kbd className="ml-1 px-1 py-0.5 bg-muted rounded text-[10px]">⌘B</kbd>
                      </TooltipContent>
                    </Tooltip>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <button
                          onClick={() => {
                            void commands.showWindow({ Search: { query: null } });
                          }}
                          aria-label="search"
                          className={cn(
                            "w-full flex items-center justify-center px-2.5 py-1.5 rounded-lg transition-all duration-150 text-left group",
                            isTranslucent
                              ? "vibrant-nav-item vibrant-nav-hover"
                              : "hover:bg-card/50 text-muted-foreground hover:text-foreground",
                          )}
                        >
                          <Search className={cn(
                            "h-3.5 w-3.5 transition-colors flex-shrink-0",
                            isTranslucent ? "vibrant-sidebar-fg-muted" : "text-muted-foreground group-hover:text-foreground"
                          )} />
                        </button>
                      </TooltipTrigger>
                      <TooltipContent side="right" className="text-xs">
                        search
                        {!settings.disabledShortcuts.includes("searchShortcut") &&
                        settings.searchShortcut ? (
                          <kbd className="ml-1 px-1 py-0.5 bg-muted rounded text-[10px]">
                            {formatShortcutDisplay(settings.searchShortcut, isMac)}
                          </kbd>
                        ) : null}
                      </TooltipContent>
                    </Tooltip>
                    {/* Divider between the search affordance and the
                        primary nav. */}
                    <div className={cn("my-1 border-t", isTranslucent ? "vibrant-sidebar-border" : "border-border/50")} />
                  </>
                )}
                {mainSections.map((section) => {
                  const isActive = activeSection === section.id;
                  const btn = (
                    <button
                      key={section.id}
                      data-testid={`nav-${section.id}`}
                      onClick={() => {
                        setActiveSection(section.id);
                      }}
                      className={cn(
                        "relative w-full flex items-center px-2.5 py-1.5 rounded-lg transition-all duration-150 text-left group",
                        sidebarCollapsed ? "justify-center" : "gap-2.5",
                        isActive
                          ? isTranslucent
                            ? "vibrant-nav-active"
                            : "bg-card shadow-sm border border-border text-foreground"
                          : isTranslucent
                            ? "vibrant-nav-item vibrant-nav-hover"
                            : "hover:bg-card/50 text-muted-foreground hover:text-foreground",
                      )}
                    >
                      <div className={cn(
                        "transition-colors flex-shrink-0",
                        isActive
                          ? isTranslucent ? "vibrant-sidebar-fg" : "text-primary"
                          : isTranslucent ? "vibrant-sidebar-fg-muted" : "text-muted-foreground group-hover:text-foreground"
                      )}>
                        {section.icon}
                      </div>
                      {!sidebarCollapsed && <span className={cn("text-xs truncate", isActive && isTranslucent ? "font-semibold vibrant-sidebar-fg" : "font-medium")}>{section.label}</span>}
                    </button>
                  );
                  if (sidebarCollapsed) {
                    return (
                      <Tooltip key={section.id}>
                        <TooltipTrigger asChild>{btn}</TooltipTrigger>
                        <TooltipContent side="right" className="text-xs">{section.label}</TooltipContent>
                      </Tooltip>
                    );
                  }
                  return btn;
                })}
              </div>

              <div className="flex-1" />

              {!sidebarCollapsed && <UpdateBanner variant="sidebar" className="mb-2" />}

              {/* Bottom items */}
              <div className={cn("space-y-0.5 border-t pt-2", isTranslucent ? "vibrant-sidebar-border" : "border-border")}>
                {/* Settings */}
                {(() => {
                  const btn = (
                    <button
                      data-testid="nav-settings"
                      onClick={() => openSettings("general")}
                      className={cn(
                        "w-full flex items-center px-2.5 py-1.5 rounded-lg transition-all duration-150 text-left group",
                        sidebarCollapsed ? "justify-center" : "space-x-2.5",
                        isTranslucent
                          ? "vibrant-nav-item vibrant-nav-hover"
                          : "hover:bg-card/50 text-muted-foreground hover:text-foreground",
                      )}
                    >
                      <div className={cn(
                        "transition-colors flex-shrink-0",
                        isTranslucent ? "" : "text-muted-foreground group-hover:text-foreground"
                      )}>
                        <SettingsIcon className="h-3.5 w-3.5" />
                      </div>
                      {!sidebarCollapsed && <span className="font-medium text-xs truncate">Settings</span>}
                    </button>
                  );
                  if (sidebarCollapsed) {
                    return (
                      <Tooltip>
                        <TooltipTrigger asChild>{btn}</TooltipTrigger>
                        <TooltipContent side="right" className="text-xs">Settings</TooltipContent>
                      </Tooltip>
                    );
                  }
                  return btn;
                })()}

                {/* Help */}
                {(() => {
                  const isActive = activeSection === "help";
                  const btn = (
                    <button
                      data-testid="nav-help"
                      onClick={() => {
                        setActiveSection("help");
                      }}
                      className={cn(
                        "w-full flex items-center px-2.5 py-1.5 rounded-lg transition-all duration-150 text-left group",
                        sidebarCollapsed ? "justify-center" : "space-x-2.5",
                        isActive
                          ? isTranslucent
                            ? "vibrant-nav-active"
                            : "bg-card shadow-sm border border-border text-foreground"
                          : isTranslucent
                            ? "vibrant-nav-item vibrant-nav-hover"
                            : "hover:bg-card/50 text-muted-foreground hover:text-foreground",
                      )}
                    >
                      <div className={cn(
                        "transition-colors flex-shrink-0",
                        isActive
                          ? isTranslucent ? "" : "text-primary"
                          : isTranslucent ? "" : "text-muted-foreground group-hover:text-foreground"
                      )}>
                        <HelpCircle className="h-3.5 w-3.5" />
                      </div>
                      {!sidebarCollapsed && <span className="font-medium text-xs truncate">Help</span>}
                    </button>
                  );
                  if (sidebarCollapsed) {
                    return (
                      <Tooltip>
                        <TooltipTrigger asChild>{btn}</TooltipTrigger>
                        <TooltipContent side="right" className="text-xs">Help</TooltipContent>
                      </Tooltip>
                    );
                  }
                  return btn;
                })()}
              </div>
            </div>
          </AppSidebar>
          </TooltipProvider>

          {/* Content */}
          <div className={cn("flex-1 flex flex-col h-full bg-background min-h-0 relative", isTranslucent ? "rounded-none" : "rounded-tr-lg")}>
            {isFullHeight ? (
              <div className="flex-1 min-h-0 overflow-hidden">
                {renderMainSection()}
              </div>
            ) : (
              <div className="flex-1 overflow-y-auto overflow-x-hidden min-h-0">
                <div className="p-6 pb-12 max-w-4xl mx-auto">
                  {renderMainSection()}
                </div>
              </div>
            )}
          </div>
      </div>

    </div>
  );
}

export default function HomePage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-background flex items-center justify-center">
      <div className="text-muted-foreground">Loading...</div>
    </div>}>
      <SidebarProvider>
        <HomeContent />
      </SidebarProvider>
    </Suspense>
  );
}
