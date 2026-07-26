"use client";

import React, { useState, useEffect, useRef, useCallback } from "react";
import { Monitor, Mic, Keyboard, Globe, Settings, X } from "lucide-react";
import { commands } from "@/lib/utils/tauri";
import { requestPermissionWithFlow } from "@/lib/utils/permission-flow";
import { usePlatform } from "@/lib/hooks/use-platform";
import { motion, AnimatePresence } from "framer-motion";

interface PermissionsStepProps {
  handleNextSlide: () => void;
}

interface PermissionDef {
  id: string;
  icon: React.ReactNode;
  title: string;
  // one short line, stated where the fear is: what it does + that it stays local
  why: string;
  action: string;
  check: () => Promise<string | boolean>;
  request: () => Promise<void>;
  // drag-into-list capable perms show the "drag me into the list" hint
  dragHint?: boolean;
  macOnly?: boolean;
  optional?: boolean;
  skippable?: boolean;
}

export default function PermissionsStep({
  handleNextSlide,
}: PermissionsStepProps) {
  const { isMac, isLoading: isPlatformLoading } = usePlatform();
  const [statuses, setStatuses] = useState<Record<string, boolean>>({});
  const [skipped, setSkipped] = useState<Record<string, boolean>>({});
  const [installedBrowsers, setInstalledBrowsers] = useState<string[]>([]);
  const [requesting, setRequesting] = useState(false);
  const [celebrateId, setCelebrateId] = useState<string | null>(null);
  const [showEscape, setShowEscape] = useState(false);
  const hasAdvancedRef = useRef(false);
  const prevStatusesRef = useRef<Record<string, boolean>>({});

  // Order matters: the important one (screen) first, then the text layer,
  // then the softer / skippable ones. One is shown at a time.
  const permissions: PermissionDef[] = [
    {
      id: "screen",
      icon: <Monitor className="w-5 h-5" strokeWidth={1.5} />,
      title: "Let me see your screen",
      why: "So I can capture and rewind what you were doing. Recorded only to your Mac.",
      action: "Open Screen Recording settings",
      check: () => commands.checkScreenRecordingPermission(),
      request: () => requestPermissionWithFlow("screenRecording"),
      dragHint: true,
    },
    {
      id: "accessibility",
      icon: <Keyboard className="w-5 h-5" strokeWidth={1.5} />,
      title: "Let me read the screen",
      why: "To turn what's on screen into searchable text. Processed locally.",
      action: "Open Accessibility settings",
      check: () => commands.checkAccessibilityPermissionCmd(),
      request: () => requestPermissionWithFlow("accessibility"),
      dragHint: true,
      macOnly: true,
    },
    {
      id: "mic",
      icon: <Mic className="w-5 h-5" strokeWidth={1.5} />,
      title: "Can I hear you too?",
      why: "To capture what you say alongside your screen. Skip if you only want screen.",
      action: "Allow microphone",
      check: () => commands.checkMicrophonePermission(),
      request: () => commands.requestPermission("microphone"),
      skippable: true,
    },
    {
      id: "browsers",
      icon: <Globe className="w-5 h-5" strokeWidth={1.5} />,
      title: "Capture browser URLs",
      why: "So I know what you were reading, not just what the pixels say. Optional.",
      action: "Enable browser URLs",
      check: async () => {
        const granted = await commands.checkBrowsersAutomationPermission();
        return granted ? "granted" : "denied";
      },
      request: async () => {
        await commands.requestBrowsersAutomationPermission();
      },
      macOnly: true,
      optional: true,
      skippable: true,
    },
  ];

  const activePermissions = permissions.filter((p) => {
    if (p.macOnly && !isMac) return false;
    if (p.id === "browsers" && installedBrowsers.length === 0) return false;
    return true;
  });

  const isDone = (p: PermissionDef) =>
    statuses[p.id] === true || skipped[p.id] === true;

  // First permission that is neither granted nor skipped. While a permission is
  // "celebrating" (just turned green), keep showing it so the check is visible.
  const undone = activePermissions.filter((p) => !isDone(p));
  const current = celebrateId
    ? activePermissions.find((p) => p.id === celebrateId)
    : undone[0];
  const currentGranted = current ? statuses[current.id] === true : false;

  const doneCount = activePermissions.filter((p) => isDone(p)).length;

  // Poll every 1s (drag-flow also watches, but this keeps optional/mic honest)
  const pollPermissions = useCallback(async () => {
    if (!isMac) return;
    const results: Record<string, boolean> = {};
    await Promise.all(
      activePermissions.map(async (p) => {
        try {
          const status = await p.check();
          results[p.id] =
            status === "granted" || status === "notNeeded" || status === true;
        } catch {
          // keep previous status on error
        }
      })
    );
    setStatuses((prev) => {
      const changed = Object.keys(results).some((k) => prev[k] !== results[k]);
      return changed ? { ...prev, ...results } : prev;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isMac, installedBrowsers.length]);

  useEffect(() => {
    if (isPlatformLoading) return;
    commands.getInstalledBrowsers().then(setInstalledBrowsers).catch(() => {});
  }, [isPlatformLoading]);

  // Non-mac has no permission gates — move on
  useEffect(() => {
    if (isPlatformLoading) return;
    if (!isMac && !hasAdvancedRef.current) {
      hasAdvancedRef.current = true;
      handleNextSlide();
    }
  }, [isMac, isPlatformLoading, handleNextSlide]);

  useEffect(() => {
    if (isPlatformLoading || !isMac) return;
    pollPermissions();
    const interval = setInterval(pollPermissions, 1000);
    return () => clearInterval(interval);
  }, [isPlatformLoading, isMac, pollPermissions]);

  // When a permission newly flips to granted, flash a check for a beat.
  useEffect(() => {
    const prev = prevStatusesRef.current;
    const newlyGranted = activePermissions.find(
      (p) => statuses[p.id] === true && !prev[p.id]
    );
    prevStatusesRef.current = { ...statuses };
    if (newlyGranted) {
      setCelebrateId(newlyGranted.id);
      const t = setTimeout(() => setCelebrateId(null), 850);
      return () => clearTimeout(t);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [statuses]);

  // When nothing is left undone (and we're not mid-celebration), advance.
  useEffect(() => {
    if (isPlatformLoading || !isMac) return;
    if (undone.length === 0 && !celebrateId && !hasAdvancedRef.current) {
      hasAdvancedRef.current = true;
      setTimeout(() => handleNextSlide(), 500);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [undone.length, celebrateId, isPlatformLoading, isMac, handleNextSlide]);

  // Escape hatch appears after a while, in case a grant won't take
  useEffect(() => {
    const t = setTimeout(() => setShowEscape(true), 12000);
    return () => clearTimeout(t);
  }, []);

  const handleGrant = async (perm: PermissionDef) => {
    if (requesting) return;
    setRequesting(true);
    try {
      await perm.request();
      await pollPermissions();
    } catch (err) {
      console.error("failed to request permission:", err);
    } finally {
      setRequesting(false);
    }
  };

  const handleSkip = (perm: PermissionDef) => {
    setSkipped((prev) => ({ ...prev, [perm.id]: true }));
  };

  if (isPlatformLoading || !isMac || !current) return null;

  return (
    <motion.div
      className="w-full flex flex-col items-center text-[#f2f4f2] px-5 pt-3 pb-8"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.3 }}
    >
      {/* chrome: progress dashes + gear/close, like the notch panel */}
      <div className="w-full flex items-center h-6 mb-9">
        <div className="flex gap-1.5 mx-auto pl-10">
          {activePermissions.map((p) => (
            <span
              key={p.id}
              className={`h-1 w-5 rounded-full transition-all duration-300 ${
                isDone(p) || p.id === current.id
                  ? "bg-[#f2f4f2]"
                  : "bg-white/20"
              }`}
            />
          ))}
        </div>
        <div className="flex items-center gap-2.5 text-[#6b706e]">
          <Settings className="w-3 h-3" strokeWidth={2} />
          <button
            onClick={() => {
              hasAdvancedRef.current = true;
              handleNextSlide();
            }}
            aria-label="skip setup"
            className="hover:text-[#f2f4f2] transition-colors"
          >
            <X className="w-3 h-3" strokeWidth={2.5} />
          </button>
        </div>
      </div>

      <AnimatePresence mode="wait">
        <motion.div
          key={current.id}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -8 }}
          transition={{ duration: 0.25 }}
          className="flex flex-col items-center text-center px-6 max-w-[380px]"
        >
          <h1
            className={`text-base font-semibold mb-1.5 transition-colors ${
              currentGranted ? "text-emerald-400" : "text-[#f2f4f2]"
            }`}
          >
            {currentGranted ? "Granted." : current.title}
          </h1>
          <p className="text-[12.5px] text-[#9aa0a0] leading-relaxed mb-5 max-w-[320px]">
            {current.why}
          </p>

          {!currentGranted && (
            <>
              <button
                onClick={() => handleGrant(current)}
                disabled={requesting}
                className="rounded-full bg-[#f2f2f2] text-[#141414] text-[13px] font-semibold px-7 py-2 transition hover:brightness-105 active:scale-[0.97] disabled:opacity-60"
              >
                {current.action}
              </button>

              {current.dragHint && (
                <p className="text-[10.5px] text-[#6b706e] mt-3">
                  drag litepipe into the list when Settings opens
                </p>
              )}

              {current.skippable && (
                <button
                  onClick={() => handleSkip(current)}
                  className="text-[11px] text-[#6b706e] hover:text-[#f2f4f2] transition-colors mt-3"
                >
                  skip for now
                </button>
              )}
            </>
          )}
        </motion.div>
      </AnimatePresence>

      {/* escape hatch if a grant refuses to register */}
      {showEscape && !currentGranted && (
        <motion.button
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          onClick={() => {
            hasAdvancedRef.current = true;
            handleNextSlide();
          }}
          className="mt-8 text-[10px] text-[#6b706e]/70 hover:text-[#f2f4f2] transition-colors"
        >
          continue without all permissions
        </motion.button>
      )}
    </motion.div>
  );
}
