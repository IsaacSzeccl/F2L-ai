# Week-1 model spike

**Question:** which z.ai model can point at the right control, quickly enough to feel like a conversation?
**Deadline:** decide by day 3–4. **Pass bar:** ≥80% hit rate on about 15 real cases, with the median time to the model's first output under 1 s.

## Why the spike is shaped like this

The coach gets its coordinates from macOS Accessibility, not from the model. The model's job is to **pick the right id** from a list of real on-screen controls (`point_at`), or to draw an approximate box when the control isn't in the list (`point_at_region`). So the spike measures:

1. **Valid pointer:** whether the model called `point_at` with an id that exists. An invented id fails, because the app refuses to draw it.
2. **Hit:** whether it chose the control a human would.
3. **Speed:** time to the first streamed token or tool call. This is the part of the latency the model controls.

## Steps

1. **Collect cases (about 1 hour).** Turn on developer mode once with `defaults write app.beacon.coach developerMode -bool true` and restart Beacon. This keeps the snapshot tool out of learners' menus, because it's the only feature that writes screen contents to disk. Open the target screen, then hover the top bar → **⋯** → **Save spike snapshot (developer)**. You have 3 seconds to make sure the target window is in front. Each snapshot saves `case-<time>.json` and `case-<time>.jpg` to `~/Library/Application Support/Beacon/spike-cases/`. Cover every element the demo needs:
   - ChatGPT: empty home page (message box), message typed (send button), model picker, attach button, a response with copy/regenerate buttons, the sidebar "new chat" button
   - Gemini and Copilot: the same core set
   - At least two screens with **few or no AX controls**, to exercise the `point_at_region` fallback
2. **Label each case.** In each JSON file, replace `"question": "EDIT ME…"` with what a learner would say ("where do I type my question?"). Set `"expectedElementID"` to the right id; open the JSON and search the `elements` list for the label.
3. **Run the candidates:**
   ```bash
   export ZAI_API_KEY=…
   swift run beacon-spike ~/Library/Application\ Support/Beacon/spike-cases --model glm-4.6v --runs 2
   swift run beacon-spike ~/Library/Application\ Support/Beacon/spike-cases --model glm-5.3-flashx --runs 2
   # if both fail:
   ANTHROPIC_API_KEY=… swift run beacon-spike ~/Library/Application\ Support/Beacon/spike-cases --provider anthropic
   ```
4. **Decide.** Choose the model that clears the bar, and set it in Settings → Coach model. Record the numbers in the table below. They're your evidence for the pitch's reliability claim.

## Candidates (from the z.ai docs, Oct 2026)

| Model | Vision | Tools | Thinking | Price in/out per 1M | Notes |
|---|---|---|---|---|---|
| `glm-4.6v` (default) | yes | native function calling | can be disabled | $0.30 / $0.90 | Safest for `point_at` |
| `glm-4.6v-flashx` | yes | yes | can be disabled | $0.04 / $0.40 | Used for the background summary; try it as the coach if `glm-4.6v` is slow |
| `glm-5.3-flashx` | yes (native multimodal) | yes | **always on**, sent as `reasoning_effort: low` | $0.37 / $1.25 | Rated at about 200 tok/s, but the reasoning step adds time before the first word |
| `glm-5.3` | **no (text only)** | yes | always on | $1.40 / $4.40 | Unsuitable: can't see the screen |

## Results

| Date | Model | Cases × runs | Valid | Hit rate | First event p50 / p90 | Decision |
|---|---|---|---|---|---|---|
| | | | | | | |
