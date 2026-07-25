import { describe, expect, it } from "vitest";
import {
  extractConversationHistorySyncUserText,
  isConversationHistorySyncPrompt,
} from "../chat-utils";

describe("chat utils conversation-history helpers", () => {
  it("detects injected conversation-history prompts", () => {
    expect(isConversationHistorySyncPrompt("<conversation_history>\nuser: a\n</conversation_history>\n\nb")).toBe(true);
    expect(isConversationHistorySyncPrompt("plain message")).toBe(false);
    expect(isConversationHistorySyncPrompt(null)).toBe(false);
  });

  it("extracts the user-visible message from injected prompts", () => {
    expect(
      extractConversationHistorySyncUserText(
        "<conversation_history>\nuser: a\nassistant: Processing...\n</conversation_history>\n\nb",
      ),
    ).toBe("b");
  });

  it("returns null for normal messages and empty text for malformed wrappers", () => {
    expect(extractConversationHistorySyncUserText("hello")).toBeNull();
    expect(extractConversationHistorySyncUserText("<conversation_history>\nuser: a")).toBe("");
  });
});
