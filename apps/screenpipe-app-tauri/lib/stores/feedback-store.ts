import { create } from "zustand";

interface FeedbackStore {
  open: boolean;
  prefillText: string;
  openFeedback: (prefill?: string) => void;
  closeFeedback: () => void;
}

export const useFeedbackStore = create<FeedbackStore>((set) => ({
  open: false,
  prefillText: "",
  openFeedback: (prefill = "") => set({ open: true, prefillText: prefill }),
  closeFeedback: () => set({ open: false, prefillText: "" }),
}));
