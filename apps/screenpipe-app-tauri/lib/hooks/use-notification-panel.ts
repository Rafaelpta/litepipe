import { commands } from "@/lib/utils/tauri";

export interface NotificationAction {
  label: string;
  action: string;
  primary?: boolean;
  // New fields for pipe notification actions
  id?: string;
  type?: "pipe" | "api" | "deeplink" | "dismiss";
  pipe?: string;
  context?: Record<string, unknown>;
  url?: string;
  method?: string;
  body?: Record<string, unknown>;
  toast?: string;
  open_in_chat?: boolean;
}

export interface NotificationPayload {
  id: string;
  type: string;
  title: string;
  body: string;
  actions: NotificationAction[];
  autoDismissMs?: number;
  pipe_name?: string;
}

export async function showNotificationPanel(
  payload: NotificationPayload
): Promise<void> {
  await commands.showNotificationPanel(JSON.stringify(payload));
}

export async function hideNotificationPanel(): Promise<void> {
  await commands.hideNotificationPanel();
}
