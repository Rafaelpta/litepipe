import { describe, expect, it } from "vitest";
import { validatePresetName } from "./validation";

const visiblePresets = [
  { id: "Daily Summary" },
  { id: "Research Helper" },
] as any[];

describe("validatePresetName", () => {
  it("rejects duplicates that only differ by surrounding whitespace", () => {
    expect(validatePresetName("  Daily Summary  ", visiblePresets)).toEqual({
      isValid: false,
      error: "A preset with this name already exists",
    });
  });

  it("allows the current preset to keep its name with surrounding whitespace", () => {
    expect(
      validatePresetName("  Daily Summary  ", visiblePresets, "Daily Summary"),
    ).toEqual({ isValid: true });
  });
});
