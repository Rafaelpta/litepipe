"use client";

// litepipe: there is no enterprise tier. The upstream hook fetched a managed
// policy (and sent a heartbeat) from the vendor's servers every few minutes;
// this stub keeps the hook's shape so preset UIs compile, reports a plain
// consumer build, and never touches the network.

import type { EnterpriseAiPresetPolicy } from "@/lib/enterprise-ai-preset-policy";

export interface EnterprisePolicy {
  aiPresetPolicy?: EnterpriseAiPresetPolicy;
}

const EMPTY_POLICY: EnterprisePolicy = {};

export function useEnterprisePolicy(): {
  isEnterprise: boolean;
  policy: EnterprisePolicy;
} {
  return { isEnterprise: false, policy: EMPTY_POLICY };
}
