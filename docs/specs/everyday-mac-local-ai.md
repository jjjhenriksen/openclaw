---
title: "Everyday Mac local AI"
summary: "Draft: recommend local AI only when it works well alongside everyday apps."
read_when:
  - Designing local model setup for Apple silicon Macs
---

# Everyday Mac local AI

**Draft.** Help people choose a useful assistant, not the biggest model their Mac
can load. Leave room for macOS, browser tabs, other apps, and OpenClaw's tools.
Connecting an AI account is a valid—and sometimes better—answer.

## Keep setup simple

Use the existing Gateway-owned setup and provider plugins. No second model picker,
installer, or app-local catalog. Check the machine that will actually run inference,
not the device displaying setup. Keep existing configurations and advanced choices.

Show one of these outcomes:

- **Recommended:** this exact model/runtime/context recipe passed everyday-use tests.
- **Available, not yet verified:** it fits the estimate, but we have not established
  everyday speed, quality, and memory headroom.
- **Local not recommended:** applicable tests show a poor experience; explain why.
- **Nothing fits right now:** explain the memory or disk constraint. A busy machine
  is not proof that its hardware can never run local AI.

Before downloading, show where it runs, download size, limitations, and what will
change. Ask first. Verify a real response and tool call before changing the default.
Cancellation or failure keeps the previous configuration. Local inference does not
make tools or connected services offline or private.

## What earns a recommendation

Test an exact model revision, quantization, runtime, context/output budget, and
machine profile—not just a model family. Count weights, context cache, buffers,
embeddings, and other apps. Do not change system memory limits to force a fit.

Measure correct multi-step OpenClaw tasks, useful-response latency, long-context
quality, sustained speed, memory pressure, swap growth, cancellation, and recovery.
Use realistic instructions and tools with ordinary apps open. One successful tool
call is an activation check, not a quality benchmark.

Start with 16 GB and 36 GB Macs. Pick numeric acceptance thresholds from measured
baselines before promoting recipes. Compare families; no model is a winner yet.
Do not extrapolate results across chips or memory tiers without evidence.

## Use the OpenClaw catalog where it fits

The existing remote catalog at
https://catalog.openclaw.ai/models/v3/catalog.json supplies model metadata such as
capabilities, context limits, and pricing through OpenClaw's normal catalog path.
Reuse that path; do not add another network fetch in setup.

Managed llama.cpp currently selects one pinned upstream build per platform/backend,
not a fork per model. Models needing a special fork must have a tested, pinned
runtime recipe before automatic setup can support them. This step does not add
custom-fork downloads.

That feed does not currently supply exact local download/runtime pins or
Mac-specific everyday-use qualification. Keep immutable downloads and local
memory budgets with the provider's existing recipes. A catalog listing or advertised
context limit cannot prove that a particular quantized build works well on a Mac.

## First implementation and remaining work

The first implementation labels managed setup as an unverified memory-fit estimate,
explains the limits of the activation check and local privacy, and offers account
setup when no memory-fit recipe exists. Existing consent, downloads, activation,
and selection budgets stay unchanged. No new config keys or runtime are introduced.

Still needed: measured qualification results, accepted thresholds, recipe evidence,
and evidence-backed ranking. No new models or performance claims ship in this step.
Refresh affected evidence when weights, runtime, parser/template, context, or
platform changes. Never silently replace an installed model.
