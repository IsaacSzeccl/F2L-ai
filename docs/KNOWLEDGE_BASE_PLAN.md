# Knowledge base and answer-quality plan

**Goal:** when a learner asks how to do something in Microsoft Copilot or Gemini, Pip gives the complete, correct steps, uses the exact on-screen names, and says so honestly when it isn't sure.
**Scope for now:** Microsoft Copilot and Gemini only. Dates: today is 13 Oct; deck and prototype due 18 Oct; final pitch 24 Oct.

## 1. What is wrong today (read from the code, to confirm with tests in Phase 0)

| # | Finding | Where | Effect |
|---|---|---|---|
| 1 | The library holds about 3 "start" steps and 4 feature bullets per tool. It has no menu paths or exact button names. | `ai-tools.json`, `AITool` | The model has nothing to quote, so it guesses or gives part of the steps. |
| 2 | The bare word "copilot" matches `id: "copilot"`, which is **GitHub** Copilot. Microsoft 365 Copilot only matches aliases such as "word" or "m365 copilot". | `mentioned()` in `AIToolLibrary.swift` | A Microsoft Copilot question can receive coding notes. |
| 3 | The prompt says to give "safe general steps" when unsure. | `CoachClient.swift:56` | Encourages vague, partial answers. |
| 4 | One model call plans the steps and picks the targets. Nothing checks the plan against the screen. | `CoachClient`, `compose()` | Wrong or stale labels reach the learner. |
| 5 | Notes are matched by tool name only, not by task, app in front, account type or role. | `referenceNotes()` | Right tool, wrong feature. |

## 2. Design

**Recipes.** A recipe is one task, written and checked by hand. Stored as JSON next to `ai-tools.json` so Swift and C# share the content and only the loader is duplicated.

```json
{
  "id": "gemini-open-canvas",
  "tool": "gemini",
  "title": "Open Canvas to edit a draft",
  "goal": "Write and edit a draft side by side with Gemini.",
  "requires": { "account": ["personal", "workspace"], "plan": "free ok", "regions": [], "notes": "Not shown in some Workspace admin settings." },
  "tags": ["write", "draft", "canvas"],
  "steps": [
    { "do": "Open gemini.google.com and sign in.", "label": "Ask Gemini", "expect": "The prompt box is visible." },
    { "do": "Click the Canvas button under the prompt box.", "label": "Canvas", "expect": "A Canvas chip appears in the box.",
      "ifMissing": "Click the plus or Tools button first; the label may sit in that menu." }
  ],
  "commonFailures": ["Canvas missing: the account may not have the feature yet."],
  "source": ["https://support.google.com/..."],
  "verifiedOn": "2026-10-15", "verifiedBy": "initials", "verifiedWith": "personal account, Chrome on macOS"
}
```

**Selection.** Pick recipes by context rather than by keyword:
1. Resolve the tool from the front app and window title first, the question second. Make bare "copilot" ambiguous (add it to `ambiguous`), and treat GitHub Copilot as its own tool that needs "github" or a code editor in front.
2. Match tags and title against the question, using the learner's role and the tools they said they have. With under 100 recipes this is plain scoring, no embeddings.
3. Inject the top 1 to 2 whole recipes (cap about 1,500 tokens), marked as reference data like the current notes.

**Prompt.** When a recipe is present: give every step in order and keep recipe labels unless the screen shows different ones; the screen wins on labels, the recipe wins on order and completeness. When none is present: say so briefly and either ask one question or give the official site, never invented menus.

**Screen check.** Before showing a step, look for its `label` in the existing OCR and Accessibility results. If found, use it as the target (green). If not, show the `ifMissing` hint and ask the model to re-plan from the screenshot (amber), instead of pointing at a guess.

**Freshness.** Every recipe has `verifiedOn`. The app shows nothing about it, but a lint warns when a recipe is older than 21 days, and the demo recipes are re-verified the day before filming.

## 3. Phases

| Phase | Dates | Tasks | Exit criteria |
|---|---|---|---|
| **0. Baseline** | 13 Oct | Write the evaluation set (30 questions) and a failing test for the Copilot collision. Run the baseline against the default provider and record scores. | Baseline numbers recorded in this file. |
| **1. Loader and selection** | 13-14 Oct | Recipe schema, loader and validation in Swift and C#, `RecipeLibrary.select(...)`, wired into `compose()` beside `referenceNotes`. Disambiguate Copilot. Parity tests. | New unit tests pass on both platforms; collision test passes. |
| **2. Author recipes** | 14-16 Oct (parallel) | 12 to 15 recipes per product: the demo flow first (prompting, using Canvas or Copilot Pages, building a reusable assistant such as Gems or Copilot agents, connecting Google Workspace or SharePoint, scheduling), then common tasks. Draft from official docs, then **click through each one** and record `verifiedOn`. | Every demo recipe verified by a second person. |
| **3. Prompt and screen check** | 15-17 Oct | Prompt changes above; label check against OCR and Accessibility; re-plan path; honest fallback when no recipe. | Evaluation scores meet the thresholds in section 4. |
| **4. Freeze and rehearse** | 17-18 Oct | Re-verify demo recipes, rehearse the demo path 5 times with a new user, freeze recipes. | Rehearsal checklist passes. |
| **5. Expand (after 18 Oct)** | 19-23 Oct | More recipes, freshness lint in CI, add other providers to the evaluation. | Optional before the final pitch. |

**Cut order if behind:** Phase 5, then broad recipes beyond the demo flow, then the re-plan path. **Never cut:** the verified demo recipes and the label check.

## 4. Test plan

### 4.1 Unit tests (Swift Testing, mirrored in `F2L.Windows.Tests`)
- **Schema lint** (like `theSharedLibraryLoadsAndIsWellFormed`): unique ids; every recipe has a known tool, 2 or more steps, `https` sources, and `verifiedOn`/`verifiedBy`/`verifiedWith`; every step has `do` and `label`; tags non-empty.
- **Selection:** a table of (question, front app, window title, profile) to expected recipe ids, including the collision cases: "Copilot" in Word, Edge on copilot.microsoft.com, VS Code, and no front app; Gemini versus Google Workspace questions; questions with no match return nothing.
- **Disambiguation:** "How do I use Copilot?" never returns GitHub Copilot unless GitHub or a code editor is in front.
- **Prompt assembly:** `compose()` includes the recipe block, marked as data, within the token cap; excluded when it's irrelevant; unchanged output for questions with no recipe.
- **Parity:** Swift and C# loaders return the same ids and scores for the same table (extend `ParityTests.swift` as the library test does).
- **Fallback:** a missing or corrupt recipe file falls back like `AIToolLibrary.builtIn` and the app still works.

### 4.2 Reply tests with a mocked provider (like `CoachClientTests`)
- A reply containing steps not in the recipe, or labels not in the recipe or screen, is flagged by the checker.
- With a recipe, all recipe steps appear and in order (using a canned reply).
- Without a recipe, no invented menus: the reply must contain an official site or an honest "not sure".

### 4.3 Screen check tests (existing `ScreenText`, `NamedPlace`, `TargetSnap` fixtures)
- Add 10 to 15 stored screenshots of Copilot and Gemini (no personal data). For each recipe step with a screenshot: label found, green target; label missing, falls back and shows `ifMissing`.
- Include a case where the interface differs from the recipe (renamed button) and confirm the screen wins.

### 4.4 Evaluation set (the main quality measure)
30 cases in `Tests/Fixtures/kb-eval.json`: question, front app and window title, account type, expected recipe id, required step labels in order, forbidden claims. Run two ways:
- **Offline:** retrieval only, no network. Runs on every test run.
- **Live, gated by `F2L_LIVE_KB=1`** (like the other live suites): sends each case through the real default provider and scores the reply.

| Metric | How | Pass threshold |
|---|---|---|
| Retrieval hit | Expected recipe is in the top 2 | at least 90% |
| Step completeness | Required labels all present, in order | at least 85% |
| Grounded labels | Every label appears in the recipe or on the screenshot | at least 95% |
| No invention | No forbidden claims or made-up menus | 100% on the demo cases |
| Honest fallback | Questions with no recipe say so | at least 90% |
| Latency | Time to first word | under about 3 s, as in `SPIKE.md` |

Record each run in a results table in `docs/SPIKE.md`, as the model check does. Compare against the Phase 0 baseline so you can show improvement.

### 4.5 Manual verification (every recipe)
A second person follows the recipe on a real account, on both Mac and Windows where the product allows, and ticks: each label exists exactly as written; each `expect` is true; `ifMissing` works; requirements (account, plan, region) are correct. Record `verifiedWith`. Test with a Hong Kong network and a personal account, since availability differs by region and licence.

### 4.6 Demo rehearsal checklist
- The three demo questions return the right recipe, all steps, and green targets at least 4 of 5 times.
- A new user (not a teammate) completes the flow unaided.
- Re-run the evaluation the day before filming and re-verify recipes if any interface changed.

## 5. Risks and how the plan handles them

| Risk | Handling |
|---|---|
| Interfaces change or differ by account | `requires`, `verifiedWith`, the screen-wins rule, the `ifMissing` path, and re-verification before filming. |
| Authoring and clicking through takes longer than the time available | Demo recipes first; others only if time remains; the second-person check is only mandatory for the demo path. |
| Whole recipes cost tokens | Cap the block; at most two recipes. |
| Feature names are unsettled (for example, which "Copilot" product offers agents or a Cowork feature) | Confirm current names in the app before writing the recipe; do not rely on this plan or on model memory. |
| Evaluation overfits the 30 cases | Hold out 10 cases that nobody tunes on. |
| Swift and C# drift | Shared JSON plus parity tests. |

## 6. Decisions to confirm
1. Is the first recipe set limited to the demo flow, with others only after 18 Oct?
2. Which provider is the demo provider? The evaluation should use it first.
3. Who verifies recipes on Windows, and who has a Hong Kong network and a paid Copilot account?
