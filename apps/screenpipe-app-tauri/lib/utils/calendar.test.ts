import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  localFetch: vi.fn(),
  commands: {
    calendarStatus: vi.fn(),
    icsCalendarGetEntries: vi.fn(),
    icsCalendarGetUpcoming: vi.fn(),
  },
}));

vi.mock("@/lib/api", () => ({
  localFetch: mocks.localFetch,
}));

vi.mock("@/lib/utils/tauri", () => ({
  commands: mocks.commands,
}));

import { fetchUpcomingCalendarSnapshot } from "./calendar";

function jsonResponse(ok: boolean, body: unknown) {
  return {
    ok,
    json: async () => body,
  };
}

// litepipe: only the native (Apple/Windows) and ICS calendar providers remain.
// The upstream Google Calendar provider went through the vendor's OAuth proxy
// and was removed; it must always report disconnected without probing anything.
describe("fetchUpcomingCalendarSnapshot", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.commands.calendarStatus.mockResolvedValue({
      status: "ok",
      data: {
        available: true,
        authorized: false,
        calendarCount: 0,
      },
    });
    mocks.commands.icsCalendarGetEntries.mockResolvedValue({
      status: "ok",
      data: [],
    });
  });

  it("includes ICS events when hoursAhead is 72", async () => {
    mocks.commands.icsCalendarGetEntries.mockResolvedValue({
      status: "ok",
      data: [{ name: "Work", url: "https://example.com/cal.ics", enabled: true }],
    });
    mocks.commands.icsCalendarGetUpcoming.mockResolvedValue({
      status: "ok",
      data: [
        {
          id: "ics-1",
          title: "Three day planning",
          start: "2026-06-05T10:00:00Z",
          end: "2026-06-05T11:00:00Z",
          attendees: [],
          calendarName: "Work",
          isAllDay: false,
          source: "ics",
        },
      ],
    });
    mocks.localFetch.mockImplementation((url: string) => {
      if (url.startsWith("/connections/calendar/events")) {
        return Promise.resolve(
          jsonResponse(false, { error: "AuthorizationDenied" }),
        );
      }

      return Promise.reject(new Error(`unexpected url: ${url}`));
    });

    const snapshot = await fetchUpcomingCalendarSnapshot({
      hoursAhead: 72,
    });

    expect(mocks.commands.icsCalendarGetUpcoming).toHaveBeenCalledWith(0, 72);
    expect(snapshot.connectedSources).toEqual(["ics"]);
    expect(snapshot.events).toHaveLength(1);
    expect(snapshot.events[0]).toMatchObject({
      title: "Three day planning",
      source: "ics",
    });
  });

  it("never reports Google as connected and never fetches Google endpoints", async () => {
    mocks.localFetch.mockImplementation((url: string) => {
      if (url.startsWith("/connections/calendar/events")) {
        return Promise.resolve(
          jsonResponse(false, { error: "AuthorizationDenied" }),
        );
      }
      return Promise.reject(new Error(`unexpected url: ${url}`));
    });

    const snapshot = await fetchUpcomingCalendarSnapshot();

    expect(snapshot.connectedSources).not.toContain("google");
    const googleCalls = mocks.localFetch.mock.calls.filter(([url]) =>
      String(url).includes("google"),
    );
    expect(googleCalls).toHaveLength(0);
  });
});
