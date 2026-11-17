---
title: "Everyday Mac local AI recommendations"
summary: "Design draft: qualify local model and context recipes without crowding out everyday Mac use."
read_when:
  - Designing hardware-aware local AI onboarding for Apple silicon
  - Qualifying local model recipes or deciding when not to recommend local AI
---

# Everyday Mac local AI recommendations

**Status: design draft, not implemented or accepted.** Research snapshot:
November 17, 2026. Model examples below are candidates, not verified winners.

## The user outcome

Help a nontechnical person get a useful assistant without turning their everyday
Mac into a dedicated inference machine. Recommend the best usable model and
context configuration for the whole experience, not the largest model that loads.

Success can also mean saying: **we recommend connecting an AI account on this Mac**.
Local AI is optional. A poor local experience is not a successful onboarding.

## Scope

Start with Apple silicon Macs used for ordinary work: browser tabs, documents,
calls, development tools, and OpenClaw executing tasks. Preserve existing hosting,
OpenClaw ID, account connection, and manually configured model flows.

Out of scope for this iteration:

- Dedicated inference-server sizing, tailnets, and remote-server onboarding.
- A new inference runtime, universal benchmark leaderboard, or runtime manager.
- Automatic model replacement, speculative decoding, or experimental cache tuning.
- Claiming every M-series generation or memory tier has a verified recommendation.

Existing advanced server connections remain supported; this proposal does not
remove them or add a server-role question to first-run onboarding.

## Extend the existing setup owner

OpenClaw already has hardware-aware managed llama.cpp setup, curated recipes,
memory/disk checks, download confirmation, and live response/tool verification.
This proposal strengthens recommendation quality and everyday-use qualification;
it does not propose building those capabilities again.

The Gateway-owned setup flow remains responsible for selection and activation.
Provider plugins own runtime-specific models, downloads, and execution. The app
shows the recommendation, tradeoffs, consent, progress, and verification result.
Do not add a competing app-local catalog or hardware policy engine.

A single successful setup tool call remains a useful activation check, but is
not enough to award a maintained recipe a quality recommendation. Qualification
must also use realistic OpenClaw prompts and multi-step tasks.

Implementation must inspect the current contracts before proposing API or storage
changes. This document does not introduce a new RPC, config key, or database schema.

## Recommendation principles

1. **Choose across families.** Do not recommend successive sizes of one family
   merely for catalog consistency. Larger Macs may benefit from genuinely larger
   models; smaller efficient models may still win on responsiveness and headroom.
2. **Protect the rest of the machine.** Budget weights, context cache, recurrent
   state, buffers, optional vision, embeddings, and ordinary application load.
   Free RAM at one instant and total installed RAM are not the whole budget.
3. **Model and context are one recipe.** Qualify usable context, not the model's
   advertised maximum. Include instructions, tool definitions, history, tool
   results, images where supported, and room to generate an answer.
4. **Task completion beats headline tokens/sec.** Measure correct finished work,
   useful-response latency, prompt processing, cancellation, and recovery.
5. **Evidence beats branding.** Parameter count, active parameters, quantization
   labels, download size, and publisher benchmarks are not agent qualification.
6. **No recommendation is valid.** Insufficient capability, speed, memory
   headroom, storage, or runtime maturity can rule out a local recommendation.

Do not fix a universal RAM percentage in this draft. Establish conservative
reserves through shared-use testing, then validate against current memory pressure
and supported GPU working-set limits. Do not change system memory limits to force
a recipe to fit. Sustained swap growth under ordinary use fails qualification;
pre-existing swap usage alone does not establish a failure.

## Proposed user flow

1. Keep the existing account/local choice. If local is chosen, inspect the actual
   execution machine, supported runtime, memory, and free storage. Never infer
   execution location from the browser or app displaying the setup screen.
2. Show one recommended recipe, when qualified, with plain-language limitations.
   Offer a faster or more capable alternative only when its tradeoff is measured.
3. Explain download size, where inference runs, supported tasks, what will change,
   and that tools or connected services may still send data externally. Local
   inference does not make the entire agent workflow offline or private by itself.
4. Ask for confirmation before download/configuration. Use existing progress,
   cancellation, verified download, and activation mechanisms.
5. Save the selected default only after existing verification succeeds. Failure
   or cancellation preserves the previous working configuration and explains the
   next step. Explain retained cached downloads without deleting unrelated models.

Example recommendation copy, shown only after qualification:

> Recommended for this Mac: a local assistant that leaves room for your other
> apps. This option supports [qualified tasks] with [qualified limitations].

Possible outcomes:

- **Recommended:** this exact recipe meets the supported machine/workload criteria.
- **Available with limitations:** explain the specific limitation before download;
  do not label an unqualified experimental model as recommended.
- **Local not recommended:** supported evidence shows unsuitable speed, capability,
  or headroom. Make connecting an AI account the primary next step.
- **Not yet verified:** no applicable evidence exists. Do not mislabel uncertainty
  as proof that the hardware cannot run local AI.

Example negative recommendation:

> We recommend connecting an AI account on this Mac. The local options we have
> tested would be too slow, too limited, or leave too little memory for your apps.

Account alternatives must explain eligibility, data handling, and applicable costs;
do not imply every account connection is free or has identical capabilities.
Keep an advanced local path available without requiring nontechnical users to
pick quantization formats, runtimes, or context-cache settings.

## Maintained recipe evidence

Extend the existing recipe representation only where necessary. Each qualified
recipe needs evidence identifying:

- Exact model revision/digest, weight format, runtime version, and license.
- Required downloads and staging space, including optional components.
- Exact chip/GPU, installed memory, OS, cooling, power mode, and background load.
- Context and output budgets, cache precision, concurrency, and reasoning settings.
- Peak process/system memory, memory pressure, swap growth, and sustained behavior.
- Cold/warm prompt latency, time to useful response, and correct task completion.
- Supported input types, tool-call behavior, and known failures or limitations.
- Test date, qualification owner, and evidence that must be refreshed on changes.

Store and validate this through existing repository/plugin mechanisms, not a new
parallel catalog service. A change to model, runtime, template/parser, context,
or material platform behavior requires affected qualification to be revisited.
Recipe updates must not silently replace a user's installed model or preferences.

## Initial research candidates

These are investigation priorities, not shipping recommendations. File sizes are
decimal GB, checked November 17, 2026, and are **not total resident-memory needs**.
Do not compare differently packaged files as measured memory deltas.

- **Bonsai 2 9B:** PQ2 language file about 2.42 GB. First constrained-Mac candidate.
- **Bonsai 2 27B:** PTQ about 5.95 GB or PQ2 about 7.21 GB, before optional vision.
  Promising for shared-use context headroom. Publisher acknowledges malformed tool
  calls and reasoning loops; those are qualification risks, not solved problems.
- **Gemma 4 31B:** current 4-bit MLX weights about 18.41 GB. Optional challenger,
  not included merely for family diversity. Must demonstrate a useful advantage.
- **GPT-OSS 20B / 120B:** Ollama lists roughly 14 GB / 65 GB. Investigate on
  32–36 GB / 96–128 GB machines respectively, with correct Harmony handling.
- **Liquid LFM3 1.7B:** relevant GGUF files about 1.05–1.10 GB. Lightweight-task
  baseline; general agent reliability remains unproven here.
- **Nemotron Bolt E4B:** current Q4_K_M file about 6.18 GB despite the 4GB name.
  Publisher evaluations are mixed; Mac runtime and task evidence remain required.
- **Qwen3.5 4B / 9B:** conventional smaller-model baselines for constrained Macs.
- **Qwen3.8 27B:** 4-bit MLX weights about 16.06 GB. Quality challenger to Bonsai
  on 32–36 GB, with more comfortable shared-use room on larger machines.
- **Qwen3-Coder-Next:** Q4_K_M about 48.53 GB. Prioritize 96 GB+ qualification;
  do not turn a tight 64 GB fit into a general everyday-Mac recommendation.
- **DeepSeek V4 Flash-0731:** exact artifact matters: IQ3_XXS about 104.21 GB,
  Q3_K_M about 128.08 GB, Q8 about 161.87 GB. Investigate at 192–256 GB+ rather
  than recommending a crowded 128 GB setup. V4.1 is a different sizing problem.

The tentative 8 GB outcome is connected AI for general agent work, with tiny local
models explicitly limited. For 16 GB, start with efficient smaller candidates;
27B is a stretch test, not a default. At 24–36 GB, investigate Bonsai 27B alongside
less-compressed quality challengers. At 48–64 GB, better context/headroom may beat
a larger model. These are hypotheses to test, not accepted hardware cutoffs.

Published community Bonsai 2 27B results illustrate why chip and workload matter:
an M5 Air 16 GB report gives about 7–8 generated tokens/sec; an M3 Max 36 GB report
gives about 24. These are short benchmark runs, not comparable controlled agent
tests, sustained thermal results, or predictions for an M3 Pro. Long context that
fits can still be too slow to process.

## Qualification and rollout

Start with one 36 GB M3 Pro and two 16 GB Macs. Record the exact 16 GB chips before
testing. Cross over finalists between the two machines to separate model effects
from hardware effects. This initial pool cannot qualify every M-series tier.

Use synthetic, repeatable tasks in an isolated OpenClaw setup with representative
instructions and tool schemas, while a realistic browser/application workload is
active. Cover tool selection and arguments, multi-step execution, tool-result
interpretation, errors and recovery, long-session retrieval, and cancellation.
Do not award tool support for merely emitting plausible tool-call JSON.

Test short and progressively larger contexts with output room; include cold and
warm runs. Establish numeric latency, success-rate, and memory-pressure acceptance
thresholds from this baseline before promoting any recipe. Do not invent passing
scores or treat publisher evaluations as our results.

Roll out in three stages:

1. Agree on this product scope and qualification rubric.
2. Publish reproducible results and qualify a small first recipe set.
3. Extend existing setup and add clear recommendation/limitation states, with
   activation, cancellation, existing-config preservation, and upgrade proof.

Keep this work separate from the existing macOS onboarding wording/connection-path
change. This draft does not modify that implementation or claim it is merge-ready.

## Open decisions

- Which measured task-success, latency, and everyday-use headroom thresholds pass?
- Which hardware profiles can share evidence without extrapolating across chips?
- Who maintains recipes, and what changes invalidate their recommendation status?
- How should a verified recommendation adapt to temporary pressure without making
  a permanent judgment from one busy moment or silently reducing user settings?
- Which limited local experiences are worth exposing in ordinary onboarding?

## References

- [Existing local-model guidance](https://docs.openclaw.ai/gateway/local-models).
- [Managed llama.cpp setup](https://docs.openclaw.ai/plugins/llama-cpp).
- [Bonsai runtime support and community evidence](https://github.com/PrismML-Eng/Bonsai-demo).
- [Bonsai known issues](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/blob/main/KNOWN_ISSUES.md).
- [Bolt model and evaluation](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB).
- [Coder-Next exact files](https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/tree/main).
- [DeepSeek Flash-0731 exact files](https://huggingface.co/unsloth/DeepSeek-V4-Flash-0731-GGUF/tree/main).
- [Gemma MLX artifact](https://huggingface.co/mlx-community/gemma-4-31b-it-4bit).
- [GPT-OSS runtime artifacts](https://ollama.com/library/gpt-oss).
- [Liquid GGUF artifacts and runtime requirements](https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF).
- [Qwen MLX artifact](https://huggingface.co/mlx-community/Qwen3.8-27B-4bit).

No new inference, shared-use, upgrade, or model-quality tests were performed for
this documentation draft. Source facts, candidate hypotheses, and proposed product
behavior are intentionally separate.
