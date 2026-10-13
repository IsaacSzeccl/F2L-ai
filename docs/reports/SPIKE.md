# Model check

**Question:** does the configured model give a short, correct next step, in the expected JSON shape, quickly enough to feel like a conversation?
**Current model:** DeepSeek Flash (`deepseek-flash`), thinking disabled, temperature 0.2, at most 650 output tokens, JSON mode with one plain-text retry.

The original week-1 spike compared z.ai models for an Accessibility-based pointing prototype. That prototype and its `f2l-spike` tool have been removed; F2L now asks one model for a reply plus an optional target, and verifies Excel cells locally instead of trusting the model's coordinates. This page describes how to check a model for the current design.

## What matters now

1. **Readable replies:** the model returns `{"reply": "...", "target": ...}`. A blank or unreadable reply is retried once without JSON mode; two failures show "DeepSeek sent back an empty reply".
2. **Direct teaching:** the reply starts with the action or answer, usually one step in 1–3 short sentences (the prompt is `TeachingReply.style` + `DeepSeekClient.teachingPrompt`, identical in `CoachClient.cs`).
3. **Honest targets:** `target` is null unless one visible control is clearly the next step. Excel cells must come back as `{"cell": "B2"}` so F2L can verify them with Excel; rectangles are only drawn as dashed, approximate hints, and never over Excel.
4. **Follow-ups:** questions with earlier history still get real answers. (Plain-text history once made JSON mode return only spaces; history is now sent in the JSON shape.)

## Quick checks

```bash
# Mac: three follow-up questions with history against the real service
F2L_LIVE_DEEPSEEK=1 scripts/test.sh --filter LiveDeepSeek
```

```powershell
# Windows: a SUM question and a follow-up with history
dotnet run --project Windows/F2L.Windows.Tests/F2L.Windows.Tests.csproj -- --provider-smoke
```

Both use the key from `local.settings.json` and send no screen picture.

## Trying another model

1. Change `model` in `Sources/CoachCore/DeepSeekClient.swift` and `Model` in `Windows/F2L.Windows/CoachClient.cs` (the Swift parity tests fail if they differ).
2. Run the quick checks above, then ask 10–15 real questions with screen sharing on: an empty ChatGPT page ("where do I type?"), a filled message ("how do I send?"), Excel ("circle B2", "how do I add up column B?"), and a screen with no obvious target.
3. Record the results below. Keep a model only if it gives the right next step in at least 12 of 15 questions, never draws a rectangle over an Excel cell, and starts speaking in under about 3 seconds.

## Results

| Date | Model | Questions | Right next step | Bad targets | Typical reply time | Decision |
|---|---|---|---|---|---|---|
| 2026-10-08 | `deepseek-flash` | live follow-up check (3 runs) | 3/3 real answers | n/a (no screen) | about 2 s each | kept |

## Knowledge-base evaluation

A separate measure of answer quality: does Pip retrieve the right checked recipe, resolve the right tool, and admit
when it has none? The set is `Tests/Fixtures/kb-eval.json` (30 cases, 10 held out). Thresholds and the full method are
in `docs/plans/KNOWLEDGE_BASE_PLAN.md`, section 4.

```bash
# Offline: retrieval and tool resolution only, no network. Runs on every test run.
scripts/test.sh --filter KnowledgeBase

# Live: sends all 30 cases through the configured provider and scores the real replies. Costs tokens.
F2L_LIVE_KB=1 scripts/test.sh --filter LiveKnowledgeBase

# Which recipes nobody has followed on a real account yet, and which checks have gone stale.
scripts/lint-recipes.py
```

| Date | Run | Tool resolved | Retrieval top 2 | Honest fallback | Answered as GitHub Copilot by mistake | Notes |
|---|---|---|---|---|---|---|
| 2026-10-13 | baseline, before the recipe work | 16/30 | 0/23 | 0/7 | 8/30 | No recipes existed; the tool came from the question's words alone. |
| 2026-10-13 | offline, after Phases 0–3 | 30/30 | 23/23 | 7/7 | 0/30 | All 25 recipes are still `status: "drafted"`. |
| — | live | — | — | — | — | Not yet run: needs a provider key and a decision on the demo provider. |
