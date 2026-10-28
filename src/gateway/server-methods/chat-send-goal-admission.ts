import { getRegisteredAgentHarness } from "../../agents/harness/registry.js";
import { resolveEffectiveAgentRuntime } from "../../agents/thinking-runtime.js";
import type { SessionEntry } from "../../config/sessions/types.js";
import type { WorkerSessionPlacementRecord } from "../worker-environments/placement-record.js";
import { isDirectChatGoalSession } from "./chat-restart-recovery.js";
import type { ChatSendAdmissionParams } from "./chat-send-pre-admission.types.js";
import { isDirectGatewayUserClient } from "./cron-creator-authority-admission.js";

/** Codex Goal input stays pending until its native writer admits it. */
export function resolveCodexGoalAdmission(
  params: ChatSendAdmissionParams,
  current: { entry?: SessionEntry; canonicalKey: string },
  placement: WorkerSessionPlacementRecord | undefined,
  acpMeta: SessionEntry["acp"] | null,
): "local" | "worker" | undefined {
  const { session, request, context, client } = params;
  const cfg = context.getRuntimeConfig();
  const harness = getRegisteredAgentHarness("codex")?.harness;
  const local = !placement || placement.state === "local";
  const eligible = Boolean(
    request.goalOperation &&
    current.entry &&
    isDirectGatewayUserClient(client) &&
    harness &&
    (local
      ? !cfg.cloudWorkers?.requiredProfile
      : placement.executionMode === "remote-exec" &&
        harness.cloudPlacement?.mode === "remote-exec") &&
    isDirectChatGoalSession({
      entry: current.entry,
      allowAborted: request.goalOperation.action === "resume",
      acpMeta,
      requestedSessionId: session.requestedSessionId,
      sessionKey: current.canonicalKey,
    }) &&
    resolveEffectiveAgentRuntime({
      cfg,
      agentId: session.agentId,
      sessionKey: current.canonicalKey,
      sessionEntry: current.entry,
      provider: session.resolvedSessionModel.provider,
      modelId: session.resolvedSessionModel.model,
    }) === "codex",
  );
  return eligible ? (local ? "local" : "worker") : undefined;
}
