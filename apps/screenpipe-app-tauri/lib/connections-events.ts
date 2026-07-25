import { apiCache } from "@/lib/cache";

export const CONNECTIONS_UPDATED_EVENT = "connections-updated";

export function notifyConnectionsUpdated({ invalidateCache = true }: { invalidateCache?: boolean } = {}) {
  if (invalidateCache) {
    apiCache.invalidate("connections/list");
  }
  if (typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent(CONNECTIONS_UPDATED_EVENT));
  }
}
