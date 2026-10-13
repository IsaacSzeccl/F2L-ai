# F2L: an expressive companion that teaches computer confidence

Design proposal · revised 7 October 2026 · F2L-ai

This document completes the research and product-planning work for the companion idea. It is an end-to-end implementation specification, not a claim that the native feature has been built. The user has confirmed the F2L name, Mac and Windows scope, and floating desktop-companion presentation; these supersede the earlier naming, Mac-first release assumption and sidebar recommendation. `DECISIONS.md` records the corrections. Character names and dimensions are provisional design choices.

## Recommendation

Build F2L as a small, original 2D teaching companion that lives directly over the desktop on **both macOS and Windows**, with a nearby speech bubble, a separate on-demand question strip, and the existing live-pointer concept. The learner stays in their current software. The core experience has no permanent chat window, dashboard, lesson sidebar or automatic window rearrangement. Temporary onboarding and settings are supporting utilities. Start with teaching adults to use AI tools. Extend the same teaching system to carefully selected Excel and Word tasks after the first experience is reliable.

The product promise is: **F2L helps you understand what to do, shows you where, and gives you room to do it yourself.**

The companion should make unfamiliar software feel approachable. The educational value comes from short explanations, correct pointing, practice, and verification. More expressions alone do not establish better learning.

Use respectful audience language in the report: people with low digital confidence, first-time computer users, or adults returning to digital work. Confidence is not a measure of intelligence.

## What was actually inspected

Local checkout: `C:\Users\solom\OneDrive\Desktop\F2L-ai`. GitHub access to [IsaacSzeccl/F2L-ai](https://github.com/IsaacSzeccl/F2L-ai) was confirmed. The working copy includes earlier uncommitted fixes and planning documents; those remain in place.

| Existing evidence | Implication for this design |
|---|---|
| `README.md` and `DECISIONS.md`: native macOS coach for ChatGPT, Gemini and Copilot; it points and the learner clicks | The companion fits the existing mission. First release means teaching people to use AI tools, not training a model. |
| `Island.swift`: 260 × 38 collapsed island; 440 × 215 expanded island; one orb; learner transcript and reply together | The proposal changes the interaction surfaces and adds typed input. It is more than replacing an image. |
| `IslandPanel.canBecomeKey` is false | A working text field needs a separate input-capable panel or a deliberate focus policy. Simply adding a text box to the island will not be sufficient. |
| `CoachSession.swift`: idle, listening, thinking and speaking phases, pause/error flags, turn cancellation | Keep these lifecycle states and add a separate expression/presentation state. |
| `Overlay.swift`: click-through drawing windows; `TargetWatcher.swift`: tracks controls and events | Retain pointing separately from interactive companion controls. |
| `PromptBuilder.swift`: one step at a time; short, respectful speech; exact vs approximate pointers | Preserve these teaching rules and extend them with lesson evidence and progress. |
| `LOCAL_REVIEW.md`: same-app window identity, stale summaries and false submission remain concerns | Resolve these before making confident progress celebrations depend on them. |
| The current runtime is Swift/macOS, with a runnable Windows WPF preview now present | Complete and verify both native hosts against the same assets, behavior and teaching fixtures. Windows is required, not a later optional expansion. |

No separate report, PRD file, PDF or Word report was found in the repository. Alignment with the report's exact wording remains pending. Native compilation and live macOS behavior were not tested in this Windows planning session.

## Research and what it means here

1. **Use motion to direct attention.** Two experiments on multimedia lessons found that a teaching agent's combined gaze and pointing improved attention to relevant content and learning outcomes. This supports testing a brief look toward F2L's highlighted control. It does not establish that this mascot improves adults' software skills. [Original study, Learning and Instruction, 2023](https://www.sciencedirect.com/science/article/pii/S0959475222001505).
2. **Friendliness needs context.** Two experiments found that a smiling teaching agent could produce negative responses and could be perceived as insincere. Give the character a calm resting face and use encouragement after meaningful progress. This is evidence against assuming that constant smiling always helps, not a universal prohibition on smiling. [Liew et al., 2016](https://www.irrodl.org/index.php/irrodl/article/view/2350).
3. **Help must be easy to request, dismiss and correct.** Microsoft's human–AI interaction guidance emphasizes appropriate timing, relevant information, user control and communicating uncertainty. Provide visible Ask, Pause screen access, Hide and correction controls. [Microsoft HAX guidelines](https://www.microsoft.com/en-us/haxtoolkit/ai-guidelines/).
4. **Motion must be optional.** W3C guidance supports disabling nonessential interaction animation and pausing persistent automatic movement. Apply these principles to the desktop companion, alongside native accessibility testing; this is not a claim of audited WCAG conformance. [Animation from interactions](https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html), [Pause, stop, hide](https://www.w3.org/WAI/WCAG22/Understanding/pause-stop-hide.html).
5. **Office can supply structured evidence.** Office Add-ins can extend supported Excel and Word clients with web-based interfaces and document APIs. They are a plausible later observation adapter and a task-pane option. Exact API availability must be checked against application version and requirement sets; document APIs do not automatically provide screen coordinates for every ribbon control. [Microsoft Office Add-ins overview](https://learn.microsoft.com/en-us/office/dev/add-ins/overview/office-add-ins).

These findings justify the design hypotheses. They do not justify a report claim that F2L already reduces anxiety, increases retention, or works across all applications.

### Positioning against existing products

Screen-aware coaching is an existing product category. Microsoft's documentation says Copilot Vision can explain shared screen content, provide step-by-step guidance and highlight areas while leaving clicks and typing to the user. Do not pitch those capabilities alone as unique to F2L. [Microsoft Copilot Vision support](https://support.microsoft.com/en-us/microsoft-copilot/using-copilot-vision-with-microsoft-copilot).

F2L's proposed distinction should be its complete beginner learning experience: respectful language, a consistent companion, predictable space for guidance, graduated hints, task-specific evidence, recovery from mistakes and a check that the learner can repeat a similar task independently. These are product commitments to build and validate, not a claim that every competing product lacks them. A future Cantonese experience could be relevant to local learners, but language coverage must be tested before it becomes a pitch claim.

## Character directions

See [the F2L character exploration sheet](../companion-concepts/character-studies-f2l.png). Generated concept art is a visual brief; it still needs consistent production artwork and animation assets.

| Direction | Personality and identity | Tradeoff |
|---|---|---|
| **Pip — lantern sprite, recommended** | Amber body, cream face, asymmetric folded flame, small teal clasp; calm, curious, capable. A friendly guide that helps you find your next step; its lantern identity is independent of the retired product name. | Simplify painted texture and the folded tip for small sizes. Avoid worried eyebrows becoming angry. |
| **Mori — leaf moth** | Sage cape-like wings and two leaf antennae; gentle and patient. | Fine leaf detail disappears at small sizes; can feel more like a nature brand. |
| **Tiko — pocket robot** | Periwinkle body, screen face and one offset antenna; clear digital-helper identity. | Familiar category, so distinctive proportions and gestures matter. |

Produce only the selected character for the first release. Give it an adult conversational voice, modest gestures and no dependency-building mechanics. No guilt for leaving, sad face when ignored, streak punishment or exaggerated celebration after every click. Offer a quiet mode with the same teaching functionality.

### Expressions follow the kind of question

The companion chooses its expression automatically from the question's type; there is no lesson-difficulty selector. Classify the request's intent and structure, not the learner's ability or feelings. A multi-part conceptual request maps to thoughtful concentration, while genuine ambiguity maps to curiosity. Neither expression blames or embarrasses the learner.

| Question type | Example | Expression | Teaching response |
|---|---|---|---|
| Quick fact, greeting or direct definition | “What does SUM do?” | Warm smile; open, relaxed eyes | Answer directly and briefly. |
| “How do I…?” or a single procedural request | “How do I add these costs?” | Attentive, focused expression; look toward the relevant control | Give the next grounded step and point to its target. |
| Multi-part or conceptual request | “Explain this formula and why it changes when I copy it.” | Thoughtful concentration; a subtle pondering look | Organize the explanation into steps while the companion stays calm and capable. |
| Vague, incomplete or genuinely ambiguous request | “Can you help with this?” or “Which one?” | Curious head tilt; raised brow | Ask one short clarifying question before guessing or pointing. |

Expression comes from the question type, not presumed task difficulty. A multi-part question earns a thoughtful look, not a distressed face. A curious look means F2L needs context; it does not mean the learner did something wrong. Do not infer emotion or expertise from silence, age, typing speed or appearance.

Lifecycle states stay separate from question-type emotion. While listening, use an attentive still pose. While thinking, show a brief pondering pose. While replying, direct the character's gaze or gesture toward a verified target. On a verified task result, allow one restrained nod or smile. On an error or pause, use a calm, neutral expression with a clear status. These states can coexist with the question's expression; for example, F2L can look warmly engaged while speaking the answer to a quick factual question.

Question-type expressions are derived from one validated intent value returned in the current answer, or from a small local classifier over the already submitted question. Do not add a second model request just to choose a face. Map only recognized values to the animation states; if intent is unknown, keep a friendly neutral face. Display the teaching answer and actions independently from the emotion. A smile must never imply that a task succeeded, and a confident expression must never hide uncertain or approximate pointing.

Production handoff: layered master artwork, transparent exports, consistent pivots/bounds, left/right facing variants, neutral still, question-type expressions, lifecycle overlays, a transition table, reduced-motion stills and asset-use records. Test at 48, 72 and 96 logical pixels in light and dark surroundings. Do not rely on AI-generated frames remaining consistent across animation sequences.

## Input, output and the work area

Three surfaces have distinct jobs:

1. **The real application:** the learner clicks and types here to perform the task. F2L's ring identifies the next control.
2. **Ask F2L:** an explicitly labeled, on-demand question composer. It contains the learner's question and a Send control, never the answer. Speech remains available.
3. **The companion and bubble:** the current instruction and short feedback. Keep a compact “You asked…” receipt for context; open past conversation only on request.

Keep the question composer and answer bubble within the same general edge area. Separating their functions does not require forcing the learner to look between opposite corners. After Send, the composer folds; the reply appears beside the character and F2L automatically expresses the type of question it received. Tap the character itself to ask a follow-up; do not add a separate “Ask another question” prompt. Preserve drafts on cancellation. Typing into the taught application's own input must never send a message to F2L.

### Confirmed presentation: a companion directly on the desktop

F2L is installed background software, with a companion as its everyday interface. It must not feel like opening another chat application. Keep the learner's real app dominant and preserve their window sizes and positions.

- **Resting:** a small character near the user's chosen edge, approximately 56–80 logical pixels as a starting design size. Optional hide-to-menu-bar/tray mode; no idle speech bubble, permanent composer or endless bouncing.
- **Asking:** click the character, invoke an accessible shortcut, or use the visible talk control. The compact input strip shows a live transcript while listening, which can be corrected before sending; typed and spoken questions share one conversation state. On Windows, tapping starts and stops dictation. On Mac, use the supported shortcut or control. The output bubble folds while composing and offers a direct way back to the last reply, so an accidental open does not lose the visible answer.
- **Replying:** after submission the question strip folds; a speech bubble appears beside the character with readable answer text and spoken audio. Speak the answer automatically by default, with visible stop/replay and mute controls. The expression responds to question type, while the animation follows actual audio playback. Keep one current instruction; the character reopens the question strip for a follow-up. The input field never becomes a scrolling answer area.
- **Doing:** the learner acts in their app. The character stays still and the pointer marks the target. The latest instruction remains available until the learner advances or explicitly collapses it; recall is one action away.
- **More detail:** split a long explanation into learner-controlled steps, or expand the same temporary bubble on request. Full history is optional and transient, never the default main window.
- **Management:** use a menu-bar item on macOS and a system-tray item on Windows for pause, hide/show, settings and quit. Temporary permission and settings windows are acceptable.

The provisional bubble width is 240–320 logical pixels. Its tail points toward the character. Place the bubble above-left or above-right according to available space, not inside a fixed app-like card enclosing the entire companion. Character, output bubble, temporary input strip and click-through pointer are distinct surfaces with different focus and hit-testing behavior.

The previous Lesson side area and Quiet focus sidebar concepts are superseded. The preferred response to insufficient space is to collapse, relocate or recall the temporary bubble; do not automatically reserve a sidebar or resize another application's window. If the bubble is hidden, F2L can continue an already requested spoken reply, but must retain a visible text recall control when shown again.

### Placement policy

- Use the actual target display's usable area, not `NSScreen.screens.first`. Respect menu bars, notch, dock/taskbar, other displays and scaling.
- Collect the current target rectangle, focused editable region, known caret/selection region, open menu/dialog bounds when available, composer bounds and pointer position.
- Enlarge the protected target by a proposed 20 logical pixels and test both character and bubble against it. Avoid the entire focused field when the caret cannot be read.
- Evaluate a small set of edge anchors and bubble directions. Reject known protected-region intersections and off-screen placements. Rank the rest by minimal movement, proximity and how little meaningful work they cover.
- Keep the current anchor while it remains usable. Re-evaluate after target, focus, window or display changes, rather than on every animation frame. Do not move controls while the user is pressing, typing in or dragging them.
- If a newly opened menu occupies the same area, retract the decorative/output overlay immediately and retain a stable reopen control. Preserve the draft in any active composer and make clear where it can be reopened.
- When no safe candidate exists, collapse to the character/launcher and retain optional audio plus the pointer. Keep the last instruction available through a clear Show instruction control; offer a user-chosen temporary bubble location. Do not move or resize the taught app. Always provide a text-accessible recall path for users who cannot use audio, and preserve an active draft.

Voice privacy is visible and simple: no always-on listening; show when the microphone is active; let the learner cancel before sending. Keep a typed path available. Explain which speech recognizer is active and whether it processes audio locally or sends it to a service. The Mac implementation uses Apple's speech recognition when supported on-device and ElevenLabs for speech output when configured, falling back to Apple's voice. The Windows preview uses Windows speech recognition and Windows voice, with optional ElevenLabs output; both require live testing on their target systems.

**Scope of guarantee:** known targets can be kept clear with geometry. Unknown important content cannot be identified perfectly. A transparent, click-through overlay still obscures vision if drawn over content. Test obstruction rather than claiming that click-through alone solves it.

### Focus and keyboard behavior

The pointer remains in its own click-through window. Companion buttons are clickable but should not take typing focus unnecessarily. Only opening/clicking Ask F2L deliberately gives keyboard focus to its composer. Cache the external app/window/control identity before that transfer; exclude F2L's own windows from teaching context and screenshot selection. Validate identity again before using a result.

After Submit or Escape, restore the original control only if the same window/control is still valid and the user has not intentionally switched elsewhere. Never force focus back over a later user action. Handle Enter, Shift+Enter, input-method composition, screen-reader navigation and interruption. Apple's panel APIs permit controlled key-focus behavior, but the concrete implementation needs native testing. [Apple panel focus documentation](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded).

## The teaching system

Use the loop **understand the goal → give one small step → point → let the learner act → inspect evidence → explain the result → offer the next step**.

Provide three levels of help, selected explicitly and adapted from demonstrated task performance:

- **Guide me:** one action, exact location, short reason if needed.
- **Let me try:** give the objective and offer hints on request; reduce proactive prompts.
- **Check my work:** inspect the result and explain any mismatch.

Give every lesson a goal, prerequisites, supported app/version, expected observable evidence, common mistakes, recovery hints and a transfer exercise. A click is evidence of an interaction, not automatically evidence of understanding. If the result cannot be verified, ask the learner to confirm rather than reporting success.

Classify each submitted question by intent and have F2L adapt its expression and explanation automatically. Do not add learner-facing simple/hard lesson modes or label the learner's ability. Let the learner continue the conversation naturally; ask a clarifying question only when intent or task context is ambiguous. Do not attach a permanent “bad at computers” label to the learner. Store progress only as chosen task-level evidence, with reset/delete controls; avoid saving screen contents as progress records.

| Domain | Begin with | Then extend to | Evidence worth checking |
|---|---|---|---|
| AI tools | Find the question box; ask with a goal and context; send; ask a follow-up | Compare responses, request revisions, check a factual claim against a source | The intended control was used; the learner can formulate a new useful request and explain what needs checking. An AI answer is not verified merely because it appeared. |
| Excel | Cells and ranges; entering values; SUM; formatting a table | Sort/filter, relative/absolute references, charts; then selected lookup/pivot lessons | Selected range, formula, result and relevant table state, preferably through a structured adapter. |
| Word | Select text; paragraphs; headings; save a document | Styles, lists, page layout, tables; then review and document structure | Actual paragraph styles and document state, rather than visual bold text alone. |

Select a bounded starter set, such as five AI tasks, before claiming broad application coverage. For Office, choose a few precise lessons and validate on real Mac/Windows/web versions. Offer fictional practice data first; the learner decides when to work with a real document.

## Implementation architecture

Treat macOS and Windows as one product with two required native hosts. Reuse the existing Swift/AppKit/SwiftUI Mac implementation and develop the proposed C#/WPF Windows host, each presenting only the floating companion in everyday use. Share artwork, animation state names, teaching specifications, prompts and test fixtures. Each OS still needs its own accessibility, capture, focus, input and overlay integration.

The native-window approach is a proposed implementation choice, not a requirement for the user to see an app window. Prototype the transparent character, input focus, bubble placement and click-through pointer on both machines in the first engineering work package. Do not lock an animation runtime before checking both hosts. A single shared UI framework is worth reconsidering only if it demonstrably reduces maintenance without weakening those native behaviors; a rewrite is not needed to achieve this presentation.

The checkout has the established Mac prototype plus a runnable Windows preview. The Windows preview captures the active app window on an explicit question and sends it for DeepSeek vision when sharing is enabled. It has draggable and resizable Pip, temporary typed/voice input with transcript review, question-type expressions, spoken replies and a screenshot-based click-through target highlight. It does not yet read UI Automation controls or verify task results. A successful build and launch do not establish full Windows compatibility.

| Component | Work required | Completion evidence |
|---|---|---|
| Shared turn submission | Add typed submission beside speech and route both through the same cancellation/context pipeline | Typed and spoken questions produce equivalent behavior; late replies never replace a newer turn. |
| `CompanionState` and reducer in CoachCore | Separate lifecycle, teaching intent, expression, target certainty and progress evidence | Invalid/stale model hints fall back to neutral; pause and cancellation override presentation. |
| `CompanionView` and renderer | Layered original art, deterministic local transitions and still fallback | State transitions work offline, respect reduced motion and add no model round trip. |
| Bubble/presentation model | One current instruction, short context receipt, optional detail/history | Text remains legible while streamed; incomplete text is not announced token by token. |
| Composer panel | Explicit focus, draft preservation and target-window tracking | No keystrokes land in the wrong application in the supported focus scenarios. |
| Placement engine | Pure rectangle calculations with platform display adapters | Protected regions are clear in geometry fixtures and real mixed-display trials. |
| Lesson engine | Goals, prerequisites, hints, expected evidence and recovery | User action and successful task outcome are represented separately. |
| Windows native host, required | Native overlay, UI Automation, capture, tray, speech and focus adapters using shared behavior fixtures | The same end-to-end teaching interactions pass on the Windows test machine. |
| Office adapter, later | Supported document APIs plus native control reading where needed | Version-specific evidence checks pass; unknown states remain unknown. |

Proposed presentation contract: `turnID`, `windowID`, `screenRevision`, `phase`, `questionType`, `instructionText`, `targetRef`, `targetCertainty`, and `progressEvidence`. Allow only question types such as `quickFact`, `procedural`, `multiPart`, and `clarificationNeeded`. Validate the enum and turn/window identities; fall back to friendly neutral when it is absent or unrecognized. Derive the character expression from this type in local code. Derive placement and trusted lifecycle from the application, not generated coordinates or an unrestricted model animation script. Question classification arrives with the existing reply, so displaying an expression makes no additional model request. A question-type face cannot override pause, uncertainty, verification or a later turn.

Start with native animation of a small set of layered assets or curated frame sequences. Keep an asset manifest independent of Swift so a Windows implementation can reuse artwork and state names. Rive is a later option for richer transitions: its documentation lists Apple and C#/C++ runtimes and warns that feature support differs. Its Windows listings do not establish a drop-in WPF solution; test the actual host before choosing it. [Rive runtime documentation](https://rive.app/docs/runtimes/getting-started).

Drive speaking animation from actual playback start/finish; do not infer that the speaker is talking merely from arriving text. Subtitle updates should follow complete phrases or sentences. Reuse the existing speech interruption path. Use the existing screen-context budget; an expression change must not trigger another screenshot or model call.

## Full delivery sequence and release gates

This is a dependency plan rather than a calendar promise. Native access, team size and the selected character determine duration.

| Work package | Deliverables | Gate to proceed |
|---|---|---|
| 1. Validate both native foundations | Mac baseline build/tests plus Windows pointing, transparent companion and input-focus prototype; fixes for same-app identity and false submission | Each OS demonstrates correct pointing, window tracking, pause, deliberate input focus and interruption. |
| 2. Refine interaction and character | Floating character/bubble/input trials on both OSs, selected character, expression vocabulary, accessible static alternative | Representative learners understand where to ask versus where to perform the task; no recurring obstruction problem. |
| 3. Produce the character assets | Layered master, four question-type expressions, lifecycle overlays, facing directions, manifest and reduced-motion stills | Warm, focused, thoughtful and curious expressions are recognizable at small sizes; consistent body, pivots and margins; no runtime asset gaps. |
| 4. Build both companion conversations | Mac and Windows hosts, typed and voice input, temporary bubble and question strip, current-step controls, focus restoration, phrase captions | End-to-end questions work on both OSs; drafts persist; cancellation, pause and errors show the correct state. |
| 5. Build placement and accessibility | Stable edge anchors, bubble direction, protected areas, collapse/recall/relocate, keyboard and screen-reader paths on both OSs | Supported targets remain visible; no unexpected focus transfer or automatic window rearrangement; limited-space fallback is usable. |
| 6. Deliver AI teaching lessons | Bounded task catalogue, graduated hints, evidence checks, explanations and transfer tasks | Unrehearsed learners complete representative tasks and a similar task without full prompting. |
| 7. Verify learning and release both platforms | Comparison study, matched Mac/Windows acceptance suite, issue fixes, onboarding, settings, signed packages and support material | Both platform gates pass before claiming compatibility; learning claims match observations and production service behavior. |
| 8. Extend to Office | App-specific evidence adapters and tested Excel/Word lessons on the supported platforms | Each advertised platform/app/version passes task-specific evidence checks. |

Work packages 2 and asset exploration can proceed while native validation is arranged. Production integration on both platforms depends on their focus and window-identity work. Windows is a release requirement throughout this sequence. Office lessons depend on reliable outcome evidence, not on having more character animations.

For a competition deadline, complete one coherent AI teaching journey with the same design, then cut cosmetic variants and extra lessons before cutting reliable pointing, clear text, pause or an unrehearsed learner test. For a public release, also finish packaging/signing, update delivery, crash recovery, service/proxy and rate-limit decisions, accurate onboarding disclosures and a tested support path. Personal team API keys are not a public distribution design.

## Evaluation and definition of done

Conduct a first formative round with roughly 6–8 representative adults of varied digital confidence. This is a usability discovery sample, not enough to claim population-wide educational effectiveness. Include people who use keyboard navigation, larger text or reduced motion where feasible.

Compare the current voice/pointer/bubble baseline with the character version while keeping instruction wording, task difficulty and pointing behavior equivalent. Counterbalance condition order and use matched tasks. Ask which version feels helpful, distracting or patronising, but give task performance and transfer priority over mascot preference.

Record: task completion without facilitator rescue, wrong-control actions, time to a usable instruction, requested hints, focus mistakes, target obstruction, successful recovery, and an unassisted similar task. Recheck a subset later for retention if the report makes retention claims. Use consented, minimal observations; raw screen recording is not required by this plan.

Proposed engineering gates, to be measured rather than presented as achieved results:

- No known critical focus, privacy-pause or stale-target failures in the release scenario suite.
- Zero overlap with registered protected target/focus regions across the placement fixtures; manually inspect real meaningful-content obstruction separately.
- No unsupported “success” state on ambiguous evidence; deletion must not count as message submission.
- Added expression handling is local and introduces no additional model/network request per turn.
- Preserve the repository's existing under-2.5-second first-word goal as an unverified target; report p50 and p95 on named hardware/network conditions.
- Every lesson works with motion off, readable text and speech off; essential controls are keyboard reachable and labeled.
- Compare learning/task results against the baseline before asserting a benefit. Set any numerical improvement target after measuring baseline variance; do not invent a percentage now.

## Suggested report wording

F2L is a context-aware desktop learning companion being developed for macOS and Windows for adults with low digital confidence. It combines short explanations, on-screen guidance and an expressive 2D character directly over the application the person is using. Questions are entered through a temporary input strip or voice; instructions appear in a nearby speech bubble. The learner remains in control and performs each action. The initial scope is AI-tool literacy; future application-specific lessons may extend the approach to productivity tools such as Excel and Word. The character is intended to make feedback clearer and more approachable, while its effect on usability and learning will be evaluated against a version without the character.

## Open decisions

Confirmed by the user: F2L is the product name; both Mac and Windows are required; the core interface is a floating desktop companion without an app-like main chat window. Remaining choices: final character, first lesson catalogue, exact learner audience, report location, target OS versions/architectures and speech engine. Confirm machine access and contributor availability before estimating dates. Pip remains a proposed character name, not the product name.

## Art provenance

`companion-concepts/character-studies-f2l.png` is the current F2L-branded concept sheet, edited with the built-in image-generation tool. The original sheet is retained as historical exploration. Both the original generation prompt and branding edit prompt are recorded in `companion-concepts/IMAGE_PROMPT.md`. It is original concept exploration, not a tested production animation or a cleared product name.

## Deliverables and verification

- The current proposal, compatibility scope and decision log reflect F2L, both required platforms and the floating desktop presentation.
- Product-facing Mac strings, coach identity, the Swift package's public product names, build scripts and app bundle metadata now use F2L. Legacy source/target names and bundle/Keychain identifiers remain stable to avoid an unrelated migration. Earlier uncommitted functional fixes are preserved.
- The browser concept preview remains a scripted design aid. The Windows WPF companion builds and launches locally, captures the active application window on an explicit question, has type-driven expressions, draggable/resizable Pip, tap-to-start dictation with transcript review, spoken replies and screenshot-based target highlights. The current configured DeepSeek key previously returned HTTP 401 in a text-only check; successful generation and image analysis remain unverified.
- The native Mac build, the revised Mac companion, Windows live screen capture, focus restoration and accessibility remain unverified. Nothing has been committed, pushed or published.
- Native compilation/signing on macOS, a valid provider key, reliable screen capture, screen-obstruction checks, UI Automation pointing, full accessibility verification and learning-outcome studies remain required before release.
