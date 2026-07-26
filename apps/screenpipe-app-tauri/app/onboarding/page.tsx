"use client";

import React, { useState, useEffect } from "react";
import PermissionsStep from "@/components/onboarding/permissions-step";
import EngineStartup from "@/components/onboarding/engine-startup";
import { useOnboarding } from "@/lib/hooks/use-onboarding";
import { commands } from "@/lib/utils/tauri";

// litepipe onboarding: grant permissions, start the engine, done. There is no
// account to sign in to and no store to browse, so the flow is two steps and
// the last step marks onboarding complete.
type SlideKey = "permissions" | "engine";

const SLIDE_WINDOW_SIZES: Record<SlideKey, { width: number; height: number }> =
  {
    permissions: { width: 500, height: 560 },
    engine: { width: 500, height: 620 },
  };

const setWindowSizeForSlide = async (slide: SlideKey) => {
  try {
    const { width, height } = SLIDE_WINDOW_SIZES[slide];
    await commands.setWindowSize("Onboarding", width, height);
  } catch {
    // non-critical
  }
};

export default function OnboardingPage() {
  const [currentSlide, setCurrentSlide] = useState<SlideKey>("permissions");
  const [isVisible, setIsVisible] = useState(true);
  const [isTransitioning, setIsTransitioning] = useState(false);
  const { onboardingData, isLoading } = useOnboarding();

  // Restore saved step on mount. Legacy step names from earlier flows all map
  // onto the two remaining steps.
  useEffect(() => {
    const init = async () => {
      const { loadOnboardingStatus } = useOnboarding.getState();
      await loadOnboardingStatus();
      const { onboardingData } = useOnboarding.getState();

      if (onboardingData.currentStep && !onboardingData.isCompleted) {
        const step = onboardingData.currentStep as string;
        const stepMap: Record<string, SlideKey> = {
          permissions: "permissions",
          engine: "engine",
          encrypt: "engine",
          // everything else restarts at permissions
        };
        setCurrentSlide(stepMap[step] ?? "permissions");
      }
    };
    init();
  }, []);

  // Set window size when slide changes
  useEffect(() => {
    setWindowSizeForSlide(currentSlide);
    setIsVisible(true);
  }, [currentSlide]);

  // Redirect if already completed
  useEffect(() => {
    if (onboardingData.isCompleted) {
      commands
        .showWindow({ Home: { page: null } })
        .then(() => window.close())
        .catch(() => {});
    }
  }, [onboardingData.isCompleted]);

  const handleNextSlide = async () => {
    if (isTransitioning) return;
    setIsTransitioning(true);

    if (currentSlide === "permissions") {
      try {
        await commands.setOnboardingStep("engine");
      } catch {
        // non-critical
      }
      setIsVisible(false);
      setTimeout(() => {
        setCurrentSlide("engine");
        setIsVisible(true);
        setIsTransitioning(false);
      }, 300);
      return;
    }

    // "engine" is the terminal step: mark onboarding complete. The
    // isCompleted effect above then opens the Home window and closes this one.
    try {
      const { completeOnboarding } = useOnboarding.getState();
      await completeOnboarding();
    } finally {
      setIsTransitioning(false);
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-black">
        <div className="w-6 h-6 border border-white/70 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="flex flex-col w-full h-screen overflow-hidden bg-black">
      {/* Drag region */}
      <div className="w-full bg-black p-3" data-tauri-drag-region />

      {/* Content */}
      <div className="flex-1 flex items-center justify-center p-6 overflow-auto">
        <div
          className={`w-full max-w-lg mx-auto transition-opacity duration-300 ${
            isVisible ? "opacity-100" : "opacity-0"
          }`}
        >
          {currentSlide === "permissions" && (
            <PermissionsStep handleNextSlide={handleNextSlide} />
          )}
          {currentSlide === "engine" && (
            <EngineStartup handleNextSlide={handleNextSlide} />
          )}
        </div>
      </div>
    </div>
  );
}
