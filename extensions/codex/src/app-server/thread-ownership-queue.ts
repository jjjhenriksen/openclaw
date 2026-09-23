import { createDeferred } from "openclaw/plugin-sdk/extension-shared";
import { resolveGlobalSingleton } from "openclaw/plugin-sdk/global-singleton";
import { KeyedAsyncQueue } from "openclaw/plugin-sdk/keyed-async-queue";

// Dist and source copies share physical clients, so their lifecycle queues must
// share ownership too. Settled entries drain naturally; never clear active tails.
const nativeThreadOwners = resolveGlobalSingleton(
  Symbol.for("openclaw.codexNativeThreadOwners"),
  () => new KeyedAsyncQueue(),
);

/** Serialize OpenClaw-owned lifecycle changes, not native-internal thread controllers. */
export async function withCodexAppServerThreadMutation<T>(
  threadId: string,
  run: () => Promise<T>,
): Promise<T> {
  return await nativeThreadOwners.enqueue(`thread:${threadId}`, run);
}

/** Queued cancellation settles the caller without letting successors overtake its lane. */
export async function withCodexAppServerThreadMutationHold<T>(
  threadId: string,
  run: (hold: (until: Promise<unknown>) => void, start: () => void) => Promise<T>,
  signal?: AbortSignal,
): Promise<T> {
  signal?.throwIfAborted();
  const { promise, resolve, reject } = createDeferred<T>();
  const abort = () =>
    reject(signal?.reason instanceof Error ? signal.reason : new Error("compaction aborted"));
  signal?.addEventListener("abort", abort, { once: true });
  const start = () => signal?.removeEventListener("abort", abort);
  const queued = nativeThreadOwners.enqueue(`thread:${threadId}`, async () => {
    let heldUntil: Promise<unknown> | undefined;
    try {
      signal?.throwIfAborted();
      resolve(
        await run((until) => {
          heldUntil ??= until;
        }, start),
      );
    } catch (error) {
      reject(error);
    }
    await heldUntil;
  });
  void queued.finally(start).catch(reject);
  return promise;
}

/** Serializes bound turns and retirement so detach cannot unsubscribe an active turn. */
export async function withCodexConversationThreadActivity<T>(
  bindingId: string,
  run: () => Promise<T>,
): Promise<T> {
  return await nativeThreadOwners.enqueue(`conversation:${bindingId}`, run);
}
