# 13 Oct 2026: knowledge-base recipes, Copilot disambiguation, docs reorganisation

Branch `llm-kb-improvement`. Executes `docs/plans/KNOWLEDGE_BASE_PLAN.md` and settles the merge against `main`.

## Merge
No merge was in progress and no file was conflicted. `llm-kb-improvement` had been branched from a stale local `main` and held only `docs/`, while `origin/main` (5a6603e, PR #1) held the whole F2L app. I merged `origin/main` with `-X theirs`, so main's version wins everything. Two untracked local files collided and were replaced with main's: `Sources/F2L/Companion.swift` and `Sources/F2L/Voice.swift` (local differences were microphone-error wording only; copies were kept in the session scratchpad).

Also fixed: a pre-existing compile failure in `Tests/CoachCoreTests/ScreenTextTests.swift` (type-check timeout), and the on-disk directory `windows/` renamed to `Windows/` to match the 84 files git tracks.

## Results (offline, 30 cases, 10 held out)

| Run | Tool resolved | Retrieval top 1 | Retrieval top 2 | Honest fallback | Answered as GitHub Copilot by mistake |
|---|---|---|---|---|---|
| Baseline, reconstructed | 16/30 | 0/23 | 0/23 | 0/7 | 8/30 |
| After Phases 0 to 3 | 30/30 | 23/23 | 23/23 | 7/7 | 0/30 |

Tests went from 127 to 160, all passing.

## What changed
- **Recipes:** `Sources/CoachCore/Recipes.swift` and `Windows/F2L.Windows/Recipes.cs` (schema, loader, scoring, recipe block, `RecipeScreen` label check); `Windows/F2L.Windows/Assets/Knowledge/recipes.json` holds 25 recipes (12 Gemini family, 13 Copilot family).
- **Copilot collision:** bare "copilot" is now ambiguous. The tool is resolved from the app in front, then the window title, then the question (`resolve`, `fromScreen`).
- **Prompt:** follows a recipe in order and completely; with none, says it is unsure and asks one question or names the official site, never inventing menus. Mirrored in `CoachClient.cs`.
- **Screen check:** when a recipe step's name is not on screen, Pip shows the recipe's `ifMissing` advice instead of a guessed circle.
- **Selection rule:** a recipe needs task words, not only the right tool, so "How much does Gemini cost?" reaches the honest fallback.
- **Evaluation:** `Tests/Fixtures/kb-eval.json`, `KnowledgeEvalTests.swift` (offline, plus live suite gated by `F2L_LIVE_KB=1`), parity tests for the C# side, `scripts/lint-recipes.py` freshness lint.
- **Build:** `scripts/build-app.sh` now copies `recipes.json` into the Mac bundle (it would otherwise have shipped without recipes).

## Not done
1. **No recipe is verified.** All 25 are `status: "drafted"`, written from official pages (listed per recipe) but never followed on a real account. This is plan section 4.5 and the Phase 2 exit criterion; it needs real accounts and a second person. The `status` field was added so a drafted recipe cannot carry invented initials.
2. **The C# is not compiled.** There is no `dotnet` on this machine. It is checked by the Swift parity tests only; build and run `F2L.Windows.Tests` on Windows.
3. **The live evaluation has not run.** It needs a provider key and a decision on the demo provider.
4. **Phase 4 is untouched;** Phase 5 is partial (the lint is not in CI).
5. Two official Google pages disagree on the Gems path ("Explore Gems" versus "Open Sidebar, then Gems"). Both are in the recipe; click-through verification should settle it.

## Docs reorganisation
Documents moved into `guides/`, `plans/`, `reference/` and `reports/` with `git mv`, and every link was rewritten and checked (0 broken). `companion-concepts/` and `previews/` stay at their paths because `asset-manifest.json` and `scripts/verify-assets.ps1` pin them by exact path. See `docs/README.md`.
