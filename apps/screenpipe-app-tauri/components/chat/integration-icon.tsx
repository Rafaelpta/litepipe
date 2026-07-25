"use client";

import { Plug } from "lucide-react";
import { cn } from "@/lib/utils";

// litepipe: the third party connections stack was removed with the cloud OAuth
// proxy. This is a minimal stand-in with the old component's API so the chat
// keeps compiling: it renders a generic plug glyph, and the empty key set makes
// every connection chip lookup miss, which cleanly disables those code paths.
export const INTEGRATION_ICON_KEYS: ReadonlySet<string> = new Set();

export function IntegrationIcon({
  className,
  fallbackClassName,
}: {
  icon?: string;
  className?: string;
  fallbackClassName?: string;
}) {
  return (
    <span className={cn("inline-flex items-center justify-center", className)}>
      <Plug className={cn("h-3 w-3", fallbackClassName)} aria-hidden />
    </span>
  );
}
