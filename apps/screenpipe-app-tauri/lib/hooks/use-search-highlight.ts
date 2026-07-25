import { create } from "zustand";

export interface SearchHighlightState {
	/** Search terms to highlight (split from query) */
	highlightTerms: string[];
	/** Frame ID that was navigated to from search */
	highlightFrameId: number | null;
	/** Whether the user has scrolled away (triggers fade-out) */
	dismissed: boolean;

	/** Called when user picks a search result */
	setHighlight: (terms: string[], frameId: number) => void;
	/** Called on scroll/frame-change to trigger fade-out */
	dismiss: () => void;
	/** Full reset (on search close, new search, etc.) */
	clear: () => void;
}

export const useSearchHighlight = create<SearchHighlightState>((set) => ({
	highlightTerms: [],
	highlightFrameId: null,
	dismissed: false,

	setHighlight: (terms, frameId) =>
		set({ highlightTerms: terms, highlightFrameId: frameId, dismissed: false }),

	dismiss: () => set({ dismissed: true }),

	clear: () =>
		set({ highlightTerms: [], highlightFrameId: null, dismissed: false }),
}));
