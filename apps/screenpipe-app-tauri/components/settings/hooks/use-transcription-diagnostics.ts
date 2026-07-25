import { useState, useCallback, useRef } from "react";
import { Settings } from "@/lib/hooks/use-settings";

const DEFAULT_OPENAI_COMPATIBLE_ENDPOINT = "http://127.0.0.1:8080";

export type TxDiagnosticStatus = "pass" | "fail" | "skip" | "pending" | "running";
export type TxDiagnosticStep = { status: TxDiagnosticStatus; message: string; latencyMs?: number };
export type TxDiagnostics = {
  endpoint: TxDiagnosticStep;
  auth: TxDiagnosticStep;
  models: TxDiagnosticStep;
  transcribe: TxDiagnosticStep;
};
export const INITIAL_TX_DIAGNOSTICS: TxDiagnostics = {
  endpoint: { status: "pending", message: "" },
  auth: { status: "pending", message: "" },
  models: { status: "pending", message: "" },
  transcribe: { status: "pending", message: "" },
};

export function useTranscriptionDiagnostics(opts: {
  settings: Settings;
}) {
  const { settings } = opts;

  const [txTestStatus, setTxTestStatus] = useState<"idle" | "testing" | "done">("idle");
  const [txTestResults, setTxTestResults] = useState<TxDiagnostics>(INITIAL_TX_DIAGNOSTICS);
  const [txDiagnosticsOpen, setTxDiagnosticsOpen] = useState(false);
  const txDiagnosticsAbortRef = useRef<AbortController | null>(null);

  // Run transcription diagnostics (endpoint -> auth -> models -> transcription test)
  const runTranscriptionDiagnostics = useCallback(async () => {
    txDiagnosticsAbortRef.current?.abort();
    const abort = new AbortController();
    txDiagnosticsAbortRef.current = abort;

    setTxTestStatus("testing");
    setTxTestResults({
      endpoint: { status: "pending", message: "" },
      auth: { status: "pending", message: "" },
      models: { status: "pending", message: "" },
      transcribe: { status: "pending", message: "" },
    });
    setTxDiagnosticsOpen(true);

    const endpoint = settings.openaiCompatibleEndpoint || DEFAULT_OPENAI_COMPATIBLE_ENDPOINT;
    const apiKey = settings.openaiCompatibleApiKey;

    const headers: Record<string, string> = {};
    if (apiKey) {
      headers["Authorization"] = `Bearer ${apiKey}`;
    }
    // Include user-configured custom headers
    if (settings.openaiCompatibleHeaders) {
      Object.assign(headers, settings.openaiCompatibleHeaders);
    }

    const skipRemaining = (failStep: string, message: string) => {
      const steps = ["endpoint", "auth", "models", "transcribe"] as const;
      const failIdx = steps.indexOf(failStep as any);
      setTxTestResults((prev) => ({
        ...prev,
        [failStep]: { status: "fail" as const, message },
        ...Object.fromEntries(
          steps
            .filter((_, i) => i > failIdx)
            .map((k) => [k, { status: "skip" as const, message: "Skipped" }])
        ),
      }));
      setTxTestStatus("done");
    };

    // Step 1: Endpoint connectivity — try root URL or /v1/models
    setTxTestResults((prev) => ({
      ...prev,
      endpoint: { status: "running", message: "Connecting..." },
    }));

    let endpointReachable = false;
    try {
      await fetch(endpoint, { signal: abort.signal, method: "GET" });
      endpointReachable = true;
    } catch {
      // root URL failed, try /v1/models as fallback
      try {
        await fetch(`${endpoint}/v1/models`, { headers, signal: abort.signal });
        endpointReachable = true;
      } catch {
        // neither worked
      }
    }

    if (abort.signal.aborted) return;

    if (!endpointReachable) {
      skipRemaining("endpoint", `Connection failed. Is the server running at ${endpoint}?`);
      return;
    }

    setTxTestResults((prev) => ({
      ...prev,
      endpoint: { status: "pass", message: `Server reachable` },
      auth: { status: "running", message: "Checking..." },
    }));

    // Step 2+3: Try to list models (also tests auth)
    let modelCount = 0;
    // Try OpenAI-style /v1/models
    try {
      const modelsResponse = await fetch(`${endpoint}/v1/models`, {
        headers,
        signal: abort.signal,
      });
      if (modelsResponse.status === 401 || modelsResponse.status === 403) {
        skipRemaining("auth", `${modelsResponse.status} Unauthorized. Check your API key.`);
        return;
      }
      if (modelsResponse.ok) {
        const data = await modelsResponse.json();
        modelCount = (data.data || []).filter((m: any) => m.id).length;
      }
    } catch {
      // /v1/models not available, try Ollama fallback
    }

    // Fallback: try Ollama-style /api/tags
    if (modelCount === 0) {
      try {
        const ollamaResponse = await fetch(`${endpoint}/api/tags`, {
          headers,
          signal: abort.signal,
        });
        if (ollamaResponse.ok) {
          const ollamaData = await ollamaResponse.json();
          modelCount = (ollamaData.models || []).filter((m: any) => m.name).length;
        }
      } catch {
        // no models endpoint available
      }
    }

    if (abort.signal.aborted) return;

    setTxTestResults((prev) => ({
      ...prev,
      auth: { status: "pass", message: apiKey ? "API key accepted" : "No auth required" },
      models: {
        status: "pass",
        message: modelCount > 0
          ? `${modelCount} model${modelCount !== 1 ? "s" : ""} available`
          : "No models listed (you can still type a model name)",
      },
      transcribe: { status: "running", message: "Sending test audio..." },
    }));

    // Step 4: Test transcription with a short silent WAV
    const model = settings.openaiCompatibleModel || "";
    const txStart = performance.now();
    try {
      // Generate a minimal 1-second silent 16kHz mono WAV
      const sampleRate = 16000;
      const numSamples = sampleRate; // 1 second
      const dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
      const buffer = new ArrayBuffer(44 + dataSize);
      const view = new DataView(buffer);
      // WAV header
      const writeStr = (offset: number, str: string) => {
        for (let i = 0; i < str.length; i++) view.setUint8(offset + i, str.charCodeAt(i));
      };
      writeStr(0, "RIFF");
      view.setUint32(4, 36 + dataSize, true);
      writeStr(8, "WAVE");
      writeStr(12, "fmt ");
      view.setUint32(16, 16, true); // subchunk size
      view.setUint16(20, 1, true); // PCM
      view.setUint16(22, 1, true); // mono
      view.setUint32(24, sampleRate, true);
      view.setUint32(28, sampleRate * 2, true); // byte rate
      view.setUint16(32, 2, true); // block align
      view.setUint16(34, 16, true); // bits per sample
      writeStr(36, "data");
      view.setUint32(40, dataSize, true);
      // samples are zero (silence)

      const blob = new Blob([buffer], { type: "audio/wav" });
      const formData = new FormData();
      formData.append("file", blob, "test.wav");
      formData.append("model", model);
      formData.append("response_format", "json");

      const txHeaders: Record<string, string> = {};
      if (apiKey) txHeaders["Authorization"] = `Bearer ${apiKey}`;
      if (settings.openaiCompatibleHeaders) Object.assign(txHeaders, settings.openaiCompatibleHeaders);

      const txResponse = await fetch(`${endpoint}/v1/audio/transcriptions`, {
        method: "POST",
        headers: txHeaders,
        body: formData,
        signal: abort.signal,
      });

      const latencyMs = Math.round(performance.now() - txStart);

      if (!txResponse.ok) {
        const errText = await txResponse.text().catch(() => "");
        setTxTestResults((prev) => ({
          ...prev,
          transcribe: {
            status: "fail",
            message: `${txResponse.status}: ${errText.slice(0, 120) || "Request failed"}`,
            latencyMs,
          },
        }));
        setTxTestStatus("done");
        return;
      }

      const txData = await txResponse.json();
      const text = txData.text ?? "";

      if (abort.signal.aborted) return;

      setTxTestResults((prev) => ({
        ...prev,
        transcribe: {
          status: "pass",
          message: text
            ? `OK (${latencyMs}ms): "${text.slice(0, 80)}"`
            : `OK (${latencyMs}ms): empty transcription (silent audio)`,
          latencyMs,
        },
      }));
    } catch (err: any) {
      if (abort.signal.aborted) return;
      const latencyMs = Math.round(performance.now() - txStart);
      setTxTestResults((prev) => ({
        ...prev,
        transcribe: {
          status: "fail",
          message: `Transcription failed: ${err.message || "Unknown error"}`,
          latencyMs,
        },
      }));
    }

    setTxTestStatus("done");
  }, [settings.openaiCompatibleEndpoint, settings.openaiCompatibleApiKey, settings.openaiCompatibleModel]);

  return {
    txTestStatus,
    txTestResults,
    txDiagnosticsOpen,
    setTxDiagnosticsOpen,
    runTranscriptionDiagnostics,
    txDiagnosticsAbortRef,
  };
}
