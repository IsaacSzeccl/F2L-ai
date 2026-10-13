# Merging `llm-kb-improvement` into `main`

Written 13 Oct 2026. Covers what this version changes, how to merge it, and what to check afterwards.

## State of the branches

- `origin/main` is at `5a6603e` (PR #1, the whole F2L app).
- `llm-kb-improvement` already contains `origin/main` (merged in `67c5c82`), so it is 0 commits behind and the merge into `main` will have no conflicts. It can be fast-forwarded or merged through a pull request.
- Merging earlier used `-X theirs`: where the two sides differed, `main` won. Details are in [the 13 Oct report](../reports/13102026-knowledge-base-recipes-and-docs-reorg.md).

## What this version changes

1. **Knowledge-base recipes.** 25 step-by-step recipes (12 Gemini, 13 Copilot) in `Windows/F2L.Windows/Assets/Knowledge/recipes.json`, loaded by `Sources/CoachCore/Recipes.swift` and `Windows/F2L.Windows/Recipes.cs`. Pip follows a matching recipe in order; with none, it says it is unsure and asks one question or names the official site instead of inventing menus.
2. **Copilot disambiguation.** "Copilot" alone is ambiguous. The tool is resolved from the app in front, then the window title, then the question.
3. **Screen check.** If a recipe step's name is not on screen, Pip shows the recipe's `ifMissing` advice instead of a guessed circle.
4. **Evaluation.** `Tests/Fixtures/kb-eval.json` (30 cases, 10 held out), `KnowledgeEvalTests.swift`, `RecipeTests.swift`, extra parity tests, and `scripts/lint-recipes.py` (freshness lint). Offline results: tool resolved 16/30 → 30/30, retrieval top 1 0/23 → 23/23, honest fallback 0/7 → 7/7, wrong "GitHub Copilot" answers 8 → 0. Swift tests went from 127 to 160.
5. **Build fix.** `scripts/build-app.sh` now copies `recipes.json` into the Mac bundle; before, the app would have shipped without recipes.
6. **Other fixes.** A type-check timeout in `ScreenTextTests.swift` that stopped the tests compiling; `windows/` renamed to `Windows/` to match tracked paths.
7. **Docs reorganised** into `guides/`, `plans/`, `reference/`, `reports/` with `git mv` and rewritten links (index: [docs/README.md](../README.md)). `companion-concepts/` and `previews/` stay put because `asset-manifest.json` pins them.

## Merge steps

```bash
git checkout llm-kb-improvement
git fetch origin
git status --short --branch          # expect a clean tree
git merge origin/main                # expect "Already up to date"

swift test                           # expect 160 tests passing
python3 scripts/lint-recipes.py      # recipe freshness lint
scripts/check-secrets.sh             # no keys in the diff

git push origin llm-kb-improvement
# Open a PR into main on GitHub, then merge it
# (or locally: git checkout main && git merge --no-ff llm-kb-improvement && git push origin main)
```

If `main` has moved and a conflict appears, resolve it by hand. Do not use `-X theirs` again; it silently discards this branch's side.

## Not committed on purpose

- `bug-reports/` holds screenshots, typed text and logs from testers. Keep it out of git.
- `AppleWWDRCAG3.cer`, `concept.html`, `prd.html`, `prd.md` are unrelated to this change.

## Known gaps after merging

1. All 25 recipes are `status: "drafted"`. None has been followed on a real account, and the plan requires that plus a second person.
2. The C# side was never compiled (no `dotnet` on the build machine). Build and run `F2L.Windows.Tests` on Windows before release.
3. The live evaluation (`F2L_LIVE_KB=1`) has not run; it needs a provider key.
4. The recipe lint is not in CI.
5. Two Google pages disagree on the Gems path; click-through checking should settle it.
