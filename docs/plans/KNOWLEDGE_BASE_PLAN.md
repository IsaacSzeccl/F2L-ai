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
  "status": "verified",
  "verifiedOn": "2026-10-15", "verifiedBy": "initials", "verifiedWith": "personal account, Chrome on macOS"
}
```

`status` is `"drafted"` until a person has followed the recipe on a real account, and `"verified"` after. A drafted
recipe must leave `verifiedOn`, `verifiedBy` and `verifiedWith` empty, and the schema lint fails if it claims any of
them: an unverified recipe can never pose as a checked one. The recipe block also tells the model when a recipe is
only drafted, so Pip says the interface may have moved on if the screen disagrees.

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

### Where each phase stands (13 Oct)

| Phase | State | What is left |
|---|---|---|
| 0. Baseline | **done** | Evaluation set written (`Tests/Fixtures/kb-eval.json`, 30 cases, 10 held out); baseline measured and recorded in 4.4b. |
| 1. Loader and selection | **done** | Schema, loader, `RecipeLibrary.select(...)` and the Copilot disambiguation on both platforms, wired into `compose()`; parity tests extended. The C# could not be compiled here (no `dotnet` on this machine), so it is checked by the Swift parity tests only — **build and run `F2L.Windows.Tests` on Windows before relying on it**. |
| 2. Author recipes | **drafted, not verified** | 25 recipes (12 Gemini-family, 13 Copilot-family), each drafted from the official page named in its `source`. Every one is `status: "drafted"`: **nobody has followed any of them on a real account**, which is section 4.5 and the Phase 2 exit criterion. |
| 3. Prompt and screen check | **done** | Prompt carries the recipe rule and the honest fallback; `RecipeScreen` checks each step's name against OCR and Accessibility before Pip points, and shows the recipe's `ifMissing` when the name isn't there. Offline thresholds met (4.4b); the live run is unmeasured. |
| 4. Freeze and rehearse | **not started** | Needs real accounts and people: verification, rehearsal, freeze. |
| 5. Expand | **partly** | `scripts/lint-recipes.py` is the freshness lint; it is not yet wired into CI. |

## 4. Test plan

### 4.1 Unit tests (Swift Testing, mirrored in `F2L.Windows.Tests`)
- **Schema lint** (like `theSharedLibraryLoadsAndIsWellFormed`): unique ids; every recipe has a known tool, 2 or more steps, `https` sources, and tags; every step has `do` and `label`; a `verified` recipe has `verifiedOn`/`verifiedBy`/`verifiedWith`, and a `drafted` one has none of them.
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

Record each run in a results table in `docs/reports/SPIKE.md`, as the model check does. Compare against the Phase 0 baseline so you can show improvement.

### 4.4b Results

Measured with `scripts/test.sh --filter KnowledgeBase` (offline; 30 cases, 10 held out). The baseline row is the
behaviour before this work, reconstructed over the same 30 cases: no recipes existed, and the tool was taken from the
question's words alone, so a bare "Copilot" matched GitHub Copilot's id.

| Date | Run | Tool resolved | Retrieval top 1 | Retrieval top 2 | Honest fallback | Answered as GitHub Copilot by mistake |
|---|---|---|---|---|---|---|
| 2026-10-13 | **Baseline** (before this work) | 16/30 | 0/23 | 0/23 | 0/7 | **8/30** |
| 2026-10-13 | After Phases 0–3 | **30/30** | **23/23** | **23/23** | **7/7** | **0/30** |

Held-out cases score the same as the rest (`theHeldOutCasesScoreLikeTheRest`), so the scoring is not fitted to the set.
Grounded labels: 0 of the 25 recipes point at a name the screen check would reject as meaningless.

**Still to measure:** the live run (`F2L_LIVE_KB=1 scripts/test.sh --filter LiveKnowledgeBase`) needs a provider key and
has not been run, so step completeness, grounded labels and no-invention in a real reply are unmeasured. The screen-check
fixtures in 4.3 are covered by synthetic candidates, not by the 10–15 stored Copilot and Gemini screenshots.

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

Still open, and each one needs a person rather than more code:

1. Is the first recipe set limited to the demo flow, with others only after 18 Oct? The 25 drafted recipes cover the
   demo flow and the common tasks around it; which ones get the second-person check first is the call to make.
2. Which provider is the demo provider? The evaluation should use it first. The live suite uses whichever provider
   `local.settings.json` selects, so this only needs settling before the live run.
3. Who verifies recipes on Windows, and who has a Hong Kong network and a paid Copilot account? Nothing in section 4.5
   has been done, and the Microsoft 365 Copilot recipes need a licensed work account to check at all.

Settled while building:

4. **An unverified recipe is marked, not faked.** `status` was added to the schema (section 2) so a drafted recipe
   cannot carry invented initials to satisfy the lint.
5. **A recipe needs task words, not just the right tool.** "How much does Gemini cost?" resolves Gemini and retrieves
   no recipe, so it reaches the honest fallback instead of the first Gemini recipe on the shelf. This is finding 5.
6. **The tool comes from the app in front, then the window title, then the question.** Two small shared tables
   (`appTools`, `titleTools`) do it, and a code editor in front is what makes a bare "Copilot" a GitHub Copilot
   question.
