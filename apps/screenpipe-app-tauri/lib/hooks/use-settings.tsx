import { homeDir } from "@tauri-apps/api/path";
import { getVersion } from "@tauri-apps/api/app";
import { commands } from "@/lib/utils/tauri";
import { platform } from "@tauri-apps/plugin-os";
import { Store } from "@tauri-apps/plugin-store";
import { emit, listen } from "@tauri-apps/api/event";
import React, { createContext, useContext, useEffect, useRef, useState } from "react";
import posthog from "posthog-js";
import { User } from "../utils/tauri";
import { SettingsStore } from "../utils/tauri";
import type { SourceCitation } from "@/lib/source-citations";
import type {
	EnterpriseAppUpdatePolicy,
	EnterpriseInstallMetadata,
} from "@ee/lib/app-update-policy";
import { type FontSize, applyFontSize } from "@/lib/utils/font-size";
export type VadSensitivity = "low" | "medium" | "high";

export type AIProviderType =
	| "native-ollama"
	| "openai"
	| "openai-chatgpt"
	| "anthropic"
	| "custom"
	| "embedded"
	| "pi";

export type EmbeddedLLMConfig = {
	enabled: boolean;
	model: string;
	port: number;
};

export enum Shortcut {
	SHOW_SCREENPIPE = "show_screenpipe",
	START_RECORDING = "start_recording",
	STOP_RECORDING = "stop_recording",
}

export type AIPreset = {
	id: string;
	maxContextChars: number;
	maxTokens?: number;
	url: string;
	model: string;
	defaultPreset: boolean;
	prompt: string;
} & (
	| {
			provider: "openai";
			apiKey: string;
	  }
	| {
			provider: "native-ollama";
	  }
	| {
			provider: "anthropic";
			apiKey: string;
	  }
	| {
			provider: "custom";
			apiKey: string;
	  }
	| {
			provider: "pi";
	  }
	| {
			provider: "openai-chatgpt";
	  }
);

export type UpdateChannel = "stable" | "beta";

// Chat history types
export interface ChatMessage {
	id: string;
	role: "user" | "assistant";
	content: string;
	intent?: "steer";
	turnIntentId?: string;
	timestamp: number;
	contentBlocks?: any[];
	sourceCitations?: SourceCitation[];
	model?: string;
	provider?: string;
	/** UI override — when set, the sidebar / panel header renders this
	 *  instead of `content` for compact display (e.g. "pipe executed
	 *  10:24 – 10:26" for synthetic prompts). Doesn't affect persistence
	 *  or what's sent to the model. */
	displayContent?: string;
	images?: any[];
	/** Non-image attachments (PDF/DOCX/XLSX/text) extracted to text. Only
	 *  metadata is stored here — the actual extracted text already lives
	 *  inside `content` (folded in at send time so the model sees it).
	 *  The renderer reads this to draw attachment cards above the bubble. */
	attachments?: Array<{
		name: string;
		ext: string;
		charCount: number;
		truncated: boolean;
	}>;
	interruptedBySteer?: boolean;
	steeredResponse?: boolean;
	/** Wall-clock work duration for coalesced assistant messages (pipe
	 *  runs). Used by the chat renderer as a fallback when no thinking
	 *  blocks contributed a duration, so the work-group can still show
	 *  "Worked for X min" even when the agent emitted no thinking. */
	workDurationMs?: number;
}

/** What kind of session a conversation represents.
 *
 *  - `chat`        — a normal Pi chat session. The default; assumed when
 *                    `kind` is missing on disk.
 *  - `pipe-watch`  — a live pipe execution the user is currently
 *                    watching. The chat panel renders pipe events in
 *                    real time; the conversation is volatile (not
 *                    persisted unless the user opts to keep it).
 *  - `pipe-run`    — a completed pipe execution kept around as
 *                    history. Lives under "Pipe runs" in the sidebar
 *                    rather than "Recents". */
export type ConversationKind = "chat" | "pipe-watch" | "pipe-run";

/** Pipe-specific context attached to `pipe-watch` / `pipe-run`
 *  conversations. Drives the in-panel banner and the sidebar
 *  grouping. */
export interface PipeContext {
	pipeName: string;
	executionId: number;
	startedAt?: string;
}

export interface ChatConversation {
	id: string;
	title: string;
	messages: ChatMessage[];
	createdAt: number;
	updatedAt: number;
	/** User pinned this conversation in the chat sidebar — keeps it at the top.
	 *  Persists across app restarts via the on-disk conversation file. */
	pinned?: boolean;
	/** User closed this conversation from the chat sidebar — keeps the file on
	 *  disk (so deleting via close is non-destructive) but excludes it from the
	 *  sidebar listing. Re-surface via a future "show hidden" UI; meanwhile a
	 *  dedicated delete-forever action is the only way to actually remove. */
	hidden?: boolean;
	/** ms since epoch of the most recent USER-SENT message. Drives the
	 *  sidebar sort order. Persisted so that order survives app restart;
	 *  derived from messages on first hydration if not set on disk yet. */
	lastUserMessageAt?: number;
	/** Conversation type — defaults to "chat" when missing (back-compat
	 *  with older on-disk files). See `ConversationKind`. */
	kind?: ConversationKind;
	/** Pipe metadata for `pipe-watch` / `pipe-run` conversations.
	 *  Undefined for plain chats. */
	pipeContext?: PipeContext;
	/** Last URL the agent navigated the embedded browser sidebar to.
	 *  Drives the right-side `<BrowserSidebar />` panel: when the user
	 *  re-opens this conversation the panel restores to this URL.
	 *  Cleared (set to undefined) when the user closes the sidebar. */
	browserState?: {
		url: string;
		updatedAt: number;
		/** User-chosen panel width in CSS pixels. Defaults to 480 if unset.
		 *  Persisted so re-opening the chat restores the same layout. */
		width?: number;
		/** User has hidden the panel (still has a saved URL — a small
		 *  "re-open" button is shown in the chat header). */
		collapsed?: boolean;
	};
	/** Title source priority: user > ai > fallback. Used to prevent
	 *  lower-priority titles from overwriting higher-priority ones. */
	titleSource?: "user" | "ai" | "fallback";
}

export interface ChatHistoryStore {
	conversations: ChatConversation[];
	activeConversationId: string | null;
	historyEnabled: boolean;
}

// Extend SettingsStore with fields added before Rust types are regenerated
export type Settings = SettingsStore & {
	deviceId?: string;
	updateChannel?: UpdateChannel;
	chatHistory?: ChatHistoryStore;
	ignoredUrls?: string[];
	searchShortcut?: string;
	lockVaultShortcut?: string;
	/** When true, audio devices follow system default and auto-switch on changes */
	useSystemDefaultAudio?: boolean;
	/** Enable AI workflow event detection (cloud, triggers event-based pipes) */
	enableWorkflowEvents?: boolean;
	/** Audio transcription scheduling: "realtime" (default) or "batch" (longer chunks for quality) */
	transcriptionMode?: "realtime" | "smart" | "batch";
	/** Live notes for manually-started meetings. Separate from background 24/7 transcription. */
	meetingLiveTranscriptionEnabled?: boolean;
	/** Provider for manually-started live notes. Defaults to the selected transcription engine. */
	meetingLiveTranscriptionProvider?: "selected-engine" | "disabled" | "deepgram-live";
	/** When true, the user's typed text (and edited files) captured during a meeting is auto-appended to the meeting note when the meeting stops. Default true. */
	appendTypedTextToMeetingNote?: boolean;
	/** User's name for speaker identification — input device audio will be labeled with this name */
	userName?: string;
	/** Filters pushed from team — merged with local filters for recording */
	teamFilters?: {
		ignoredWindows: string[];
		includedWindows: string[];
		ignoredUrls: string[];
	};
	/** Custom vocabulary entries for transcription biasing and word replacement */
	vocabularyWords?: Array<{ word: string; replacement?: string }>;
	/** Cloud archive: auto-upload and delete data older than retention period */
	cloudArchiveEnabled?: boolean;
	/** Days to keep data locally before archiving (default: 7) */
	cloudArchiveRetentionDays?: number;
	/** Sync pipe configurations across devices (requires cloud sync subscription) */
	pipeSyncEnabled?: boolean;
	/** Slug of the pipe used to summarize meetings. Drives both the manual
	 * "Summarize with AI" button (its body becomes the chat prompt) and the
	 * auto-fire on meeting_ended (the picked pipe owns the trigger). Default:
	 * "meeting-summary" (the built-in pipe). */
	meetingSummaryPipeSlug?: string;
	/** Sync memories (facts, preferences, decisions, insights) across devices.
	 * Independent of pipeSyncEnabled — a user might want their memories on
	 * every device but keep pipes device-local, or vice versa. Pro-gated. */
	memoriesSyncEnabled?: boolean;
	/** Sync connected-account credentials (OAuth tokens + manual API keys)
	 * across devices. Off by default and kept separate from pipes/memories on
	 * purpose: it syncs secrets, so enabling it is a distinct informed choice.
	 * Credentials are end-to-end encrypted in the sync blob. Pro-gated. */
	connectionsSyncEnabled?: boolean;
	/** Font size for the entire app UI */
	fontSize?: FontSize;
	/** OpenAI-compatible transcription endpoint URL */
	openaiCompatibleEndpoint?: string;
	/** OpenAI-compatible transcription API key */
	openaiCompatibleApiKey?: string;
	/** OpenAI-compatible transcription model name */
	openaiCompatibleModel?: string;
	/** Custom HTTP headers for OpenAI-compatible transcription (JSON object) */
	openaiCompatibleHeaders?: Record<string, string>;
	/** Send raw WAV audio instead of MP3 to OpenAI-compatible endpoint */
	openaiCompatibleRawAudio?: boolean;
	/** Let Pi / Claude Code call the confidential cloud enclave
	 * (Gemma 4 E4B inside an attested Tinfoil CVM) to analyze audio,
	 * video frames, and images from screenpipe data. Default true. When
	 * false, the "Cloud audio + video + image analysis" section is
	 * stripped from `~/.claude/skills/screenpipe-api/SKILL.md` so agents
	 * literally cannot see the endpoint and won't try to call it. */
	cloudMediaAnalysisEnabled?: boolean;
	/** Filter music-dominant audio before transcription (reduces Spotify/YouTube music noise) */
	filterMusic?: boolean;
	/** Maximum batch transcription duration in seconds (0 = engine default: Deepgram 5000s, OpenAI 3000s, Whisper 600s) */
	batchMaxDurationSecs?: number;
	/** Show periodic notifications suggesting pipe ideas based on user's data (default: true) */
	pipeSuggestionsEnabled?: boolean;
	/** Hours between pipe suggestion notifications (default: 24) */
	pipeSuggestionFrequencyHours?: number;
	/** User's power mode preference — persisted so it survives app restarts */
	powerMode?: "auto" | "performance" | "battery_saver";
	/** Show restart notifications when audio/vision capture stalls (default: false for now) */
	showRestartNotifications?: boolean;
	/** Pause all screen capture when a DRM-protected streaming app (Netflix, Disney+, etc.) or a remote-desktop client (Omnissa/VMware Horizon) is focused — they blank their windows during screen recording */
	pauseOnDrmContent?: boolean;
	/** Skip clipboard capture in the UI recorder (events + content). Defaults to true (clipboard capture OFF) — passwords / API keys often pass through the clipboard, so it's opt-in. */
	disableClipboardCapture?: boolean;
	/** Skip keyboard / typed-text capture in the UI recorder. Defaults to true (keyboard capture OFF) — the a11y tree + OCR still capture on-screen text, this only drops the raw keystroke stream where secrets get typed. */
	disableKeyboardCapture?: boolean;
	/** Experimental: capture System Audio via CoreAudio Process Tap (macOS 14.4+) instead of ScreenCaptureKit.
	 *  Off by default. Ignored on macOS <14.4 and non-macOS — falls back to SCK. */
	experimentalCoreaudioSystemAudio?: boolean;
	/** Experimental: request Windows WASAPI microphone AEC when supported. */
	windowsInputAecEnabled?: boolean;
	/** Experimental: request Apple VoiceProcessingIO AEC on the default macOS microphone. */
	macosInputVpioEnabled?: boolean;
	/** Continue recording audio when the screen is locked (default: false) */
	recordWhileLocked?: boolean;
	/** Auto-delete local data older than retention days (free alternative to cloud archive) */
	localRetentionEnabled?: boolean;
	/** Days to keep data locally before auto-deleting (default: 14) */
	localRetentionDays?: number;
	/** What gets deleted past the cutoff: "media" keeps DB rows (search/timeline still
	 * work), only reclaims mp4/wav/jpeg files. "all" wipes everything. Default: "media". */
	localRetentionMode?: "media" | "all";
	/** Apply macOS vibrancy effect to sidebar for a translucent glass look */
	translucentSidebar?: boolean;
	/** Hide model "thinking" reasoning blocks in chat (default: true) */
	hideThinkingBlocks?: boolean;
	/** Auto-generate chat titles with the LLM after the first message.
	 *  Costs one extra inference per new chat. Disable to save tokens —
	 *  chats fall back to a title derived from the first message (default: true) */
	autoGenerateChatTitles?: boolean;
	/** Notification preferences — which notification sources are enabled */
	notificationPrefs?: {
		captureStalls: boolean;
		appUpdates: boolean;
		pipeSuggestions: boolean;
		pipeNotifications: boolean;
		/** Toast when a monitor is plugged, unplugged, or switched (clamshell, dock). Default true. */
		displayChanges?: boolean;
		/** Live-note prompt when a meeting is detected. Default true. */
		meetingLiveNotes?: boolean;
		/** OS notification when a meeting starts but no audio frames arrive within 60s. Default true. */
		audioCaptureStalled?: boolean;
		/** In-app /notify when audio is captured but no live transcript arrives within 60s. Default true. */
		liveTranscriptStalled?: boolean;
		mutedPipes: string[];
	};
	/** Remote devices to monitor pipes on (LAN addresses) */
		monitorDevices?: Array<{
			address: string;
			label?: string;
		}>;
		/** Enterprise app-update policy fetched from the admin dashboard. */
		enterpriseAppUpdatePolicy?: EnterpriseAppUpdatePolicy;
		/** Local install/update-manager detection for enterprise fleet reporting. */
		enterpriseInstallMetadata?: EnterpriseInstallMetadata;
		/** Enable recording schedule — when on, recording only runs during defined time ranges */
		scheduleEnabled?: boolean;
	/** Per-day-of-week time ranges defining when recording is active */
	scheduleRules?: Array<{
		dayOfWeek: number;
		startTime: string;
		endTime: string;
		recordMode: string;
	}>;
	apiAuth?: boolean;
	apiKey?: string;
	/** Default behavior when a meeting is detected.
	 * - `"ask"` (default): the existing meeting-start notification grows
	 *   a "+ HD" action. Click → starts a meeting-bound session that
	 *   auto-stops when the call ends.
	 * - `"always"`: every detected meeting auto-starts a session.
	 * - `"never"`: no auto-action; only the manual tray timer can start
	 *   one.
	 * Indefinite manual mode does not exist — every session is bound to
	 * either a meeting or a timer, both with hard-cap safety nets. */
	hdRecordingDefault?: "ask" | "always" | "never";
	/** Capture debounce (ms) installed while an HD session is active.
	 * Default 100 ≈ 10 fps. Clamped to >= 33 ms (30 fps ceiling). */
	hdRecordingIntervalMs?: number;
	/**
	 * When true the backend binds the HTTP API to 0.0.0.0 instead of 127.0.0.1
	 * so other devices on the LAN can reach it. api_auth is force-enabled
	 * whenever this is true — the backend mirrors the guard in
	 * RecordingConfig::from_settings so the two flags stay consistent even
	 * if someone edits the settings file by hand.
	 */
	listenOnLan?: boolean;
	encryptStore?: boolean;
	/** Global blanket permission: allow screenpipe to copy browser cookies
	 *  into the owned browser so the agent can browse sites the user is
	 *  logged into. Revocable from the owned-browser cookie menu.
	 *  Undefined = not decided yet, false = disabled, true = enabled. */
	browserCookieAccessGranted?: boolean;
	/** Windows-only: when true, closing the Home window hides it to the system
	 * tray (and removes it from the taskbar) instead of minimizing. The Rust
	 * close handler in src-tauri/src/main.rs reads this directly. Default off. */
	minimizeToTrayOnClose?: boolean;
}

export function getEffectiveFilters(settings: Settings) {
	const team = settings.teamFilters || { ignoredWindows: [], includedWindows: [], ignoredUrls: [] };
	return {
		ignoredWindows: [...new Set([...settings.ignoredWindows, ...team.ignoredWindows])],
		includedWindows: [...new Set([...settings.includedWindows, ...team.includedWindows])],
		ignoredUrls: [...new Set([...(settings.ignoredUrls || []), ...team.ignoredUrls])],
	};
}

export const DEFAULT_PROMPT = `Rules:
- Media: use standard markdown with angle-bracket local paths, like ![description](</path/to/file.mp4>) for videos and ![description](</path/to/image.jpg>) for images
- Always wrap local file paths in angle brackets because screenpipe paths often contain spaces or parentheses
- Diagrams: use \`\`\`mermaid blocks for visual summaries (flowchart, gantt, mindmap, graph)
- Activity summaries: gantt charts with apps/duration
- Workflows: flowcharts showing steps taken
- Knowledge sources: graph diagrams showing where info came from (apps, times, conversations)
- Meetings: extract speakers, decisions, action items
- Stay factual, use only provided data
`;

const DEFAULT_IGNORED_WINDOWS_IN_ALL_OS = [
	"bit",
	"VPN",
	"Trash",
	"Private",
	"Incognito",
	"Wallpaper",
	"Settings",
	"Keepass",
	"Recorder",
	"vault",
	"OBS Studio",
	"screenpipe",
];

const DEFAULT_IGNORED_WINDOWS_PER_OS: Record<string, string[]> = {
	macos: [
		".env",
		"Item-0",
		"App Icon Window",
		"Battery",
		"Shortcuts",
		"WiFi",
		"BentoBox",
		"Clock",
		"Dock",
		"DeepL",
		"Control Center",
	],
	windows: ["Nvidia", "Control Panel", "System Properties"],
	linux: ["Info center", "Discover", "Parted"],
};

// litepipe ships with no AI preset. There is no hosted provider; the user adds
// a local (Ollama) or bring-your-own-key provider in Settings before using chat.
export function makeDefaultPresets(_isPro: boolean): AIPreset[] {
	return [];
}

const DEFAULT_AUDIO_ENGINE = "whisper-large-v3-turbo-quantized";

let DEFAULT_SETTINGS: Settings = {
			aiPresets: [] as any,
			deviceId: crypto.randomUUID(),
			deepgramApiKey: "",
			isLoading: false,
			userId: "",
			analyticsId: "",
			devMode: false,
			audioTranscriptionEngine: "whisper-large-v3-turbo-quantized",
			meetingLiveTranscriptionEnabled: true,
			meetingLiveTranscriptionProvider: "selected-engine",
			appendTypedTextToMeetingNote: true,
			ocrEngine: "default",
			monitorIds: ["default"],
			audioDevices: ["default"],
			useSystemDefaultAudio: true,
			usePiiRemoval: false,
			port: 3030,
			dataDir: "default",
			disableAudio: false,
			ignoredWindows: [
			],
			includedWindows: [],
			ignoredUrls: [],
			ignoredMeetingApps: [],
			teamFilters: { ignoredWindows: [], includedWindows: [], ignoredUrls: [] },

			// litepipe: analytics off by default and permanently uninitialized.
			analyticsEnabled: false,
			audioChunkDuration: 30,
			useChineseMirror: false,
			languages: [],
			embeddedLLM: {
				enabled: false,
				model: "ministral-3:latest",
				port: 11434,
			},
		updateChannel: "stable",
			autoUpdate: false,
			autoUpdatePipes: true,
			autoStartEnabled: true,
			platform: "unknown",
			disabledShortcuts: [],
			user: {
				id: null,
				name: null,
				email: null,
				image: null,
				token: null,
				clerk_id: null,
				api_key: null,
				credits: null,
				stripe_connected: null,
				stripe_account_status: null,
				github_username: null,
				bio: null,
				website: null,
				contact: null,
				cloud_subscribed: null,
				credits_balance: null,
				app_entitled: null,
				subscription_plan: null,
				entitlement: null
			},
			showScreenpipeShortcut: "Control+Super+S",
			startRecordingShortcut: "Super+Alt+U",
			stopRecordingShortcut: "Super+Alt+X",
			startAudioShortcut: "Control+Super+A",
			stopAudioShortcut: "Control+Super+Z",
			showChatShortcut: "Control+Super+L",
			searchShortcut: "Control+Super+K",
			lockVaultShortcut: "Super+Shift+L",
			disableVision: false,
			useAllMonitors: true,
			showShortcutOverlay: true,
			chatHistory: {
				conversations: [],
				activeConversationId: null,
				historyEnabled: true,
			},
			overlayMode: "fullscreen",
			showOverlayInScreenRecording: false,
			disableTimeline: false,
			videoQuality: "balanced",
			transcriptionMode: "batch",
			cloudArchiveEnabled: false,
			cloudArchiveRetentionDays: 7,
			meetingSummaryPipeSlug: "meeting-summary",
			filterMusic: false,
			ignoreIncognitoWindows: true,
			pauseOnDrmContent: false,
			disableClipboardCapture: true,
			disableKeyboardCapture: true,
			experimentalCoreaudioSystemAudio: false,
			windowsInputAecEnabled: false,
			macosInputVpioEnabled: false,
			recordWhileLocked: false,
			localRetentionEnabled: true,
			localRetentionDays: 30,
			localRetentionMode: "media",
			encryptStore: true,
			hdRecordingDefault: "ask",
			hdRecordingIntervalMs: 100,
			fontSize: "16px",
		};

export function createDefaultSettingsObject(): Settings {
	try {
		const p = platform();
		DEFAULT_SETTINGS.platform = p;
		DEFAULT_SETTINGS.ignoredWindows = [...DEFAULT_IGNORED_WINDOWS_IN_ALL_OS];
		DEFAULT_SETTINGS.ignoredWindows.push(...(DEFAULT_IGNORED_WINDOWS_PER_OS[p] ?? []));
		DEFAULT_SETTINGS.ocrEngine = p === "macos" ? "apple-native" : p === "windows" ? "windows-native" : "tesseract";
		DEFAULT_SETTINGS.showScreenpipeShortcut = p === "windows" ? "Alt+S" : "Control+Super+S";
		DEFAULT_SETTINGS.showChatShortcut = p === "windows" ? "Alt+L" : "Control+Super+L";
		DEFAULT_SETTINGS.searchShortcut = p === "windows" ? "Alt+K" : "Control+Super+K";
		DEFAULT_SETTINGS.startAudioShortcut = p === "windows" ? "Alt+Shift+A" : "Control+Super+A";
		DEFAULT_SETTINGS.stopAudioShortcut = p === "windows" ? "Alt+Shift+Z" : "Control+Super+Z";
		DEFAULT_SETTINGS.lockVaultShortcut = p === "windows" ? "Ctrl+Shift+L" : "Super+Shift+L";

		if (p === "windows") {
			DEFAULT_SETTINGS.overlayMode = "window";
		}

		if (p === "linux") {
			DEFAULT_SETTINGS.overlayMode = "window";
		}

		return DEFAULT_SETTINGS;
	} catch (e) {
		// Fallback if platform detection fails
		return DEFAULT_SETTINGS;
	}
}

// Store singleton
let _store: Promise<Store> | undefined;

export const getStore = async () => {
	if (!_store) {
		// Use homeDir to match Rust backend's get_base_dir which uses $HOME/.screenpipe
		const dir = await homeDir();
		_store = Store.load(`${dir}/.screenpipe/store.bin`, {
			autoSave: false,
			defaults: {},
		});
	}
	return _store;
};

/** Save the store and re-encrypt store.bin on disk (keychain encryption). */
export const saveAndEncrypt = async (store: Store) => {
	await store.save();
	await commands.reencryptStore().catch(() => {});
};

// Store utilities similar to Cap's implementation
function createSettingsStore() {
	const get = async (): Promise<Settings> => {
		const store = await getStore();
		const settings = await store.get<Settings>("settings");
		if (!settings) {
			return createDefaultSettingsObject();
		}

		// Migration: Ensure existing users have deviceId for free tier tracking
		let needsUpdate = false;
		if (!settings.deviceId) {
			settings.deviceId = crypto.randomUUID();
			needsUpdate = true;
		}

		// Temporary one-time migration: force restart notifications off for all
		// existing users until the stall detector is more reliable. Users can
		// still manually opt back in afterward; the marker prevents re-overriding.
		if (!(settings as any).restartNotificationsDefaultedOff) {
			settings.showRestartNotifications = false;
			(settings as any).restartNotificationsDefaultedOff = true;
			needsUpdate = true;
		}

		// One-time migration (V2 — supersedes V1): flip the CoreAudio Process
		// Tap toggle OFF for every existing install, keeping SCK as the System
		// Audio backend. V1 (run a few days earlier) had flipped it ON by
		// default, but the Process Tap can't capture audio rendered through a
		// VoiceProcessing AudioUnit — Zoom/Meet/Teams all use one for echo
		// cancellation — so the tap silently captured zeroed buffers on every
		// meeting. Users who explicitly want the tap (e.g. to dodge SCK's
		// sleep/wake display-enumeration bug) can re-enable it in Settings.
		// Reported on 2026-04-24 after v2.4.46 calls kept dropping
		// other participants.
		if (!(settings as any).coreaudioTapMigrationV2) {
			settings.experimentalCoreaudioSystemAudio = false;
			(settings as any).coreaudioTapMigrationV2 = true;
			needsUpdate = true;
		}

		if (settings.meetingLiveTranscriptionEnabled === undefined) {
			settings.meetingLiveTranscriptionEnabled = true;
			needsUpdate = true;
		}
		if (!settings.meetingLiveTranscriptionProvider) {
			settings.meetingLiveTranscriptionProvider = "selected-engine";
			needsUpdate = true;
		}
		if (settings.appendTypedTextToMeetingNote === undefined) {
			settings.appendTypedTextToMeetingNote = true;
			needsUpdate = true;
		}

		// litepipe: no default AI preset and no hosted-provider migrations.

		// Migration: Add chat history for existing users
		if (!settings.chatHistory) {
			settings.chatHistory = {
				conversations: [],
				activeConversationId: null,
				historyEnabled: true,
			};
			needsUpdate = true;
		}

		// Migration: Fill empty showChatShortcut with platform default
		if (!settings.showChatShortcut || settings.showChatShortcut.trim() === "") {
			const p = platform();
			settings.showChatShortcut = p === "windows" ? "Alt+L" : "Control+Super+L";
			needsUpdate = true;
		}

		// Migration: Fill empty audio shortcuts with platform defaults
		if (!settings.startAudioShortcut || settings.startAudioShortcut.trim() === "") {
			const p = platform();
			settings.startAudioShortcut = p === "windows" ? "Alt+Shift+A" : "Control+Super+A";
			needsUpdate = true;
		}
		if (!settings.stopAudioShortcut || settings.stopAudioShortcut.trim() === "") {
			const p = platform();
			settings.stopAudioShortcut = p === "windows" ? "Alt+Shift+Z" : "Control+Super+Z";
			needsUpdate = true;
		}

		// Always override platform with runtime detection — never trust persisted value.
		// Platform can be "unknown" if it was saved during SSR or before Tauri was ready.
		try {
			const detectedPlatform = platform();
			if (settings.platform !== detectedPlatform) {
				settings.platform = detectedPlatform;
				needsUpdate = true;
			}
		} catch {
			// platform() unavailable (SSR/tests) — keep existing value
		}

		// Mark pro migration as done so the old migration doesn't re-trigger
		if (!(settings as any)._proCloudMigrationDone) {
			(settings as any)._proCloudMigrationDone = true;
			needsUpdate = true;
		}

		// Migration: Set default transcription engine (one-time only)
		// - macOS → whisper-large-v3-turbo-quantized
		// - Windows/Linux → parakeet
		if (!(settings as any)._parakeetDefaultMigrationDone) {
			const engine = settings.audioTranscriptionEngine;
			const isWhisperVariant = engine?.includes("whisper");
			if (isWhisperVariant || engine === "screenpipe-cloud" || engine === "parakeet") {
				const { platform: getPlatform } = await import("@tauri-apps/plugin-os");
				const os = getPlatform();
				settings.audioTranscriptionEngine = os === "macos"
					? "whisper-large-v3-turbo-quantized"
					: "parakeet";
				needsUpdate = true;
			}
			(settings as any)._parakeetDefaultMigrationDone = true;
			needsUpdate = true;
		}

		// Save migrations if needed
		if (needsUpdate) {
			await store.set("settings", settings);
			await saveAndEncrypt(store);
		}

		return settings;
	};

	const set = async (value: Partial<Settings>) => {
		const store = await getStore();
		const current = await get();
		let newSettings = { ...current, ...value } as Settings;
		await store.set("settings", newSettings);
		await saveAndEncrypt(store);
	};

	const reset = async () => {
		const store = await getStore();
		await store.set("settings", createDefaultSettingsObject());
		await saveAndEncrypt(store);
	};

	const resetSetting = async <K extends keyof Settings>(key: K) => {
		const current = await get();
		const defaultValue = createDefaultSettingsObject()[key];
		await set({ [key]: defaultValue } as Partial<Settings>);
	};

	const listen = (callback: (settings: Settings) => void) => {
		return getStore().then((store) => {
			return store.onKeyChange("settings", (newValue: Settings | null | undefined) => {
				callback(newValue || createDefaultSettingsObject());
			});
		});
	};

	return {
		get,
		set,
		reset,
		resetSetting,
		listen,
	};
}

const settingsStore = createSettingsStore();

// Context for React
interface SettingsContextType {
	settings: Settings;
	updateSettings: (updates: Partial<Settings>) => Promise<void>;
	resetSettings: () => Promise<void>;
	resetSetting: <K extends keyof Settings>(key: K) => Promise<void>;
	reloadStore: () => Promise<void>;
	getDataDir: () => Promise<string>;
	isSettingsLoaded: boolean;
	loadingError: string | null;
}

const SettingsContext = createContext<SettingsContextType | undefined>(undefined);

export const SettingsProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
	const [settings, setSettings] = useState<Settings>(createDefaultSettingsObject());
	const [isSettingsLoaded, setIsSettingsLoaded] = useState(false);
	const [loadingError, setLoadingError] = useState<string | null>(null);

	// Load settings on mount
	useEffect(() => {
		const loadSettings = async () => {
			try {
				const loadedSettings = await settingsStore.get();
				setSettings(loadedSettings);
				setIsSettingsLoaded(true);
				setLoadingError(null);

				// Configure the API module — single source of truth for port + auth.
				// `apiKey` is intentionally NOT passed: `ensureInitialized` in
				// lib/api.ts loads the canonical key from the server via IPC
				// (`get_local_api_config`). settings.apiKey is a user preference
				// fed to the server's auth resolver; the server then exposes the
				// resolved key via that IPC. Passing it here would race with the
				// IPC and overwrite a good key with `null` for the majority of
				// users (who never set a custom api key) — which silently breaks
				// every WebSocket auth path.
				const { configureApi } = await import("@/lib/api");
				configureApi({
					port: loadedSettings.port ?? 3030,
					authEnabled: loadedSettings.apiAuth ?? true,
				});

				// Hydrate Rust's owned-browser runtime cache from persisted settings.
				// This prevents the cookie-access prompt from reappearing after restart.
				await commands
					.setBrowserCookieAccessState(
						loadedSettings.browserCookieAccessGranted === true,
						loadedSettings.browserCookieAccessGranted === false,
					)
					.catch(() => {});
			} catch (error) {
				console.error("Failed to load settings:", error);
				setLoadingError(error instanceof Error ? error.message : "Unknown error");
				setIsSettingsLoaded(true);
			}
		};

		loadSettings();

		// Listen for changes
		const unsubscribe = settingsStore.listen((newSettings) => {
			setSettings(newSettings);
		});

		return () => {
			unsubscribe.then((unsub) => unsub());
		};
	}, []);

	// Install global fetch interceptor to catch 401s from screenpi.pe
	const settingsRef = useRef(settings);
	settingsRef.current = settings;

	// Monotonic auth generation, bumped on every explicit sign-out. A
	// loadUser() call snapshots this at entry; if a sign-out bumps it while the
	// network request is still in flight, loadUser refuses to write the user
	// back. Without this, a slow refresh that started before the user clicked
	// "logout" resurrects the just-cleared session — the user had to click
	// logout twice. Regression test: e2e/specs/zz-logout-resurrect.spec.ts.
	const authGenerationRef = useRef(0);

	// litepipe: no auth layer. The global fetch auth interceptor from the
	// upstream project is gone; there is no account, so nothing to intercept.

	// Cross-window sign-out: when any window broadcasts a sign-out (logout
	// button or 401 interceptor), bump THIS window's auth generation so an
	// in-flight loadUser here also aborts instead of writing the user back
	// into the shared store. Pairs with the emit() in updateSettings.
	useEffect(() => {
		const unlistenPromise = listen("screenpipe-auth-signout", () => {
			authGenerationRef.current += 1;
		});
		return () => {
			unlistenPromise.then((un) => un()).catch(() => {});
		};
	}, []);

	// litepipe: no account, so there is no user auto-refresh from a server.

	// Identify the user in PostHog. When a Clerk-authenticated user is present,
	// we identify by clerk_id (matches the web's identify call), so PostHog
	// merges the web profile (carrying UTM/gclid from ad attribution) with the
	// desktop-app profile. Before switching, alias the machine analyticsId to
	// the clerk_id so prior anonymous app events also merge forward.
	useEffect(() => {
		if (!settings.analyticsId) return;

		const clerkId = settings.user?.clerk_id || undefined;
		const distinctId = clerkId || settings.analyticsId;

		if (clerkId) {
			try { posthog.alias(clerkId); } catch {}
		}

		const baseProps = {
			email: settings.user?.email,
			name: settings.user?.name,
			user_id: settings.user?.id,
			clerk_id: clerkId,
			github_username: settings.user?.github_username,
			website: settings.user?.website,
			contact: settings.user?.contact,
			cloud_subscribed: !!settings.user?.cloud_subscribed,
			app_entitled: !!(settings.user as any)?.app_entitled,
			subscription_plan: (settings.user as any)?.subscription_plan,
			machine_analytics_id: settings.analyticsId,
		};

		getVersion()
			.then((appVersion) => {
				posthog.identify(distinctId, { ...baseProps, app_version: appVersion });
			})
			.catch(() => {
				posthog.identify(distinctId, baseProps);
			});
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [settings.analyticsId, settings.user?.id, settings.user?.clerk_id, settings.user?.cloud_subscribed, (settings.user as any)?.app_entitled, (settings.user as any)?.subscription_plan]);

	// When user becomes a Pro subscriber, default to cloud transcription (one-time)
	useEffect(() => {
		if (!isSettingsLoaded) return;
		if ((settings as any)._proCloudMigrationDone) return;

		// Mark migration as done — we no longer force cloud transcription for Pro users.
		// Local engines (whisper/qwen3) are now the default for all users.
		settingsStore.set({ _proCloudMigrationDone: true } as any);
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [settings.user?.cloud_subscribed, isSettingsLoaded]);

	useEffect(() => {
		applyFontSize(settings.fontSize);
	}, [settings.fontSize]);

	const updateSettings = async (updates: Partial<Settings>) => {
		// Sign-out (user → null) must invalidate any loadUser() request that is
		// currently in flight so the cleared session can't be resurrected when a
		// slow refresh resolves afterwards. Bump synchronously — before the first
		// await — so even the logout button's fire-and-forget call wins the race.
		if ("user" in updates && !updates.user) {
			authGenerationRef.current += 1;
			// Broadcast to the other windows. Each non-overlay window has its own
			// SettingsProvider + DeeplinkHandler, so a login's deep-link fires a
			// loadUser in EVERY window. Without this, a logout in this window
			// wouldn't invalidate an in-flight loadUser in another window, which
			// would write the user back into the shared store and resurrect the
			// session. Fire-and-forget; the listener above bumps each window's ref.
			emit("screenpipe-auth-signout").catch(() => {});
		}
		await settingsStore.set(updates);
		// Settings will be updated via the listener

		// Only update the port in the API module immediately — auth changes
		// (apiAuth / apiKey) must NOT be applied until after the server restarts.
		// Calling configureApi({ authEnabled: false }) before restart clears the
		// auth cookie, causing every frontend WebSocket to reconnect without a
		// token and flood the logs with 403 rejections (the server still requires
		// auth until it restarts with the new setting).
		if ("port" in updates) {
			const { configureApi } = await import("@/lib/api");
			const merged = { ...settings, ...updates };
			configureApi({ port: merged.port ?? 3030 });
		}
	};

	const resetSettings = async () => {
		await settingsStore.reset();
		// Settings will be updated via the listener
	};

	const resetSetting = async <K extends keyof Settings>(key: K) => {
		await settingsStore.resetSetting(key);
		// Settings will be updated via the listener
	};

	const reloadStore = async () => {
		const freshSettings = await settingsStore.get();
		setSettings(freshSettings);
	};

	const getDataDir = async () => {
		const homeDirPath = await homeDir();

		if (
			settings.dataDir !== "default" &&
			settings.dataDir &&
			settings.dataDir !== ""
		)
			return settings.dataDir;

		return `${homeDirPath}/.screenpipe`;
	};

	const value: SettingsContextType = {
		settings,
		updateSettings,
		resetSettings,
		resetSetting,
		reloadStore,
		getDataDir,
		isSettingsLoaded,
		loadingError,
	};

	return (
		<SettingsContext.Provider value={value}>
			{children}
		</SettingsContext.Provider>
	);
};

export function useSettings(): SettingsContextType {
	const context = useContext(SettingsContext);
	if (context === undefined) {
		throw new Error("useSettings must be used within a SettingsProvider");
	}
	return context;
}
