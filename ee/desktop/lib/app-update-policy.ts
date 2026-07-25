// Non-enterprise build stub for the removed proprietary enterprise app-update policy.
// Provides permissive defaults (no enterprise restrictions). Written from scratch; it
// contains none of the removed proprietary code. The enterprise consumers are slated
// for removal in the slimming pass.

export type EnterpriseAppUpdatePolicy = {
  mode: string;
  channel: string;
  default_auto_update: boolean;
  allow_employee_override: boolean;
  [key: string]: unknown;
};

export type EnterpriseInstallMetadata = {
  install_source: string;
  update_manager: string;
  managed: boolean;
  detected_by: string[];
};

export const DEFAULT_ENTERPRISE_APP_UPDATE_POLICY: EnterpriseAppUpdatePolicy = {
  mode: "consumer",
  channel: "stable",
  default_auto_update: true,
  allow_employee_override: true,
};

export function normalizeEnterpriseAppUpdatePolicy(
  policy?: unknown,
): EnterpriseAppUpdatePolicy {
  const p =
    policy && typeof policy === "object"
      ? (policy as Partial<EnterpriseAppUpdatePolicy>)
      : {};
  return { ...DEFAULT_ENTERPRISE_APP_UPDATE_POLICY, ...p };
}

export function describeEnterpriseUpdateMode(
  _policy?: EnterpriseAppUpdatePolicy | null,
): string {
  return "Automatic";
}
