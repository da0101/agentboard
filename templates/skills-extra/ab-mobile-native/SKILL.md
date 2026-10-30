---
name: ab-mobile-native
description: "Use whenever work touches a mobile app that has (or will have) separate native iOS and Android codebases — Swift/SwiftUI/UIKit, Kotlin/Jetpack Compose, Xcode, Gradle. Runs the two platforms in parallel lanes and forbids copying UI patterns (navigation, FAB, back buttons, sheets, controls) from one to the other: each OS gets its own 100% native experience."
version: 1.0.0
origin: agentboard
argument-hint: "<the mobile feature or screen — describe behavior, not UI>"
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - Edit
  - Write
---

# ab-mobile-native — two platforms, two native experiences, one behavior

## Identity

You are **`[ab-mobile-native]`**. Start **every** response with your label on its own line:

> **`[ab-mobile-native]`**

ANSI terminal color: `\033[38;5;114m[ab-mobile-native]\033[0m`

## Why this skill exists (read this first)

iPhone users and Android users are both picky, and they are picky about **different things**.
They notice within seconds when an app was designed for the other platform, and they
describe it as "weird", "cheap" or "a port".

Real incident: while the owner tested the iOS build, the agent building the Android build
**copied the iOS Liquid Glass navigation into Android** — the same floating glass tab bar,
the same floating action button, the same floating back buttons over the content. Android
users do not use that. They expect a **Material bottom navigation bar and a top app bar**.
The result looked foreign on every Android phone.

**The rule:** the two apps share *what the product does*. They never share *how the UI is
built or looks*. Behavior is ported. UI is re-derived from each platform's own conventions.

The quality bar is 100% native on both sides: an iOS user must believe the app was made by
Apple-platform specialists, an Android user must believe it was made by Android specialists.

## When to use

- Any new screen, flow, component or navigation change in a native iOS and/or Android app
- A bug fix or polish pass that changes how something *looks or behaves to the touch*
- Whenever two agents (or one agent in two sessions) work on the iOS and Android versions of
  the same feature

## When NOT to use

- Backend, API or data-only work with no UI change
- A single cross-platform codebase (Flutter, React Native, KMP + Compose Multiplatform UI).
  There, do not branch into two lanes; instead use each framework's *adaptive* widgets
  deliberately and still apply the Hard rules and the divergence table below to decide where the
  UI must differ per platform. Tell the user when a requested shared widget would feel
  non-native on one OS.

## Hard rules

1. **No UI pattern crosses platforms.** Not navigation structure, not a control, not an
   animation, not a layout idea, not an icon style. If you notice yourself thinking "same as
   the iOS one", stop and look up what the Android convention is (and vice versa).
2. **Behavior parity, UI divergence.** Both apps must have the same features, rules, data,
   validation, copy meaning, empty/error states and analytics events. They must *not* have
   the same widgets.
3. **Use the platform's system components first.** Custom-drawn UI is a last resort, and
   never a custom imitation of the other OS's component.
4. **The owner's test device is not the spec.** If the owner reviews on an iPhone, iPhone
   feedback changes the iOS lane. It is *translated* for Android (what is the Android-native
   way to reach the same intent?), never applied literally.
5. **Lanes never read each other's UI code as a template.** Read the shared behavior spec.
   Reading the other platform's *logic* to confirm a rule is fine; copying its view code is
   not.
6. **Shared brand is allowed, shared chrome is not.** Brand colors, logo, illustration style,
   tone of copy and typeface *intent* may match. They are expressed through each platform's
   own theme system (see table). Navigation, bars, buttons, sheets, dialogs, pickers and
   gestures follow the OS.
7. **Intentional sameness needs a record.** If a screen should look identical on both
   platforms (rare), ask the human, then log it in the stream's `## Knowledge delta` as
   `- [mobile-deliberate-same:<screen>] <why>`. Without that record, sameness is a defect.

## Step 1 — Write the platform-neutral behavior spec (once, shared)

Before any code, write the spec in chat (or the stream) in **behavior terms only**:

- User goal and entry points; what the user can do; every state (loading, empty, partial,
  error, offline, permission denied); data shown; rules and validation; copy; analytics events;
  accessibility meaning (what a screen reader should announce, not which API).
- **Forbidden in the shared spec:** component names ("FAB", "bottom sheet", "tab bar", "glass"),
  layout positions ("floating at the bottom right"), or any wording that sounds like one OS.
  Say "the user can start a new entry" and let each lane decide how its OS offers that.

## Step 2 — Dispatch two lanes in parallel

Spawn one agent per platform at the same time (pass `model` on each call; print the dispatch
manifest first, per `ab protocol subagents`). Each lane gets **only**:
the behavior spec, its own platform's section of this skill, and its own codebase path.
Give each the matching prompt:

**iOS lane brief**
> You are the iOS lane. Build `<feature>` in the iOS app using the behavior spec. Follow Apple's
> Human Interface Guidelines and the current iOS design language (Liquid Glass on iOS 26+, with
> correct fallbacks for the deployment target). Prefer system components (NavigationStack,
> TabView, List, Form, toolbar, sheets, system pickers). Do not open or imitate the Android
> project. Before coding, output your **Platform design brief** (Step 3). After coding, output
> the **Fidelity checklist** (Step 5) with evidence.

**Android lane brief**
> You are the Android lane. Build `<feature>` in the Android app using the behavior spec. Follow
> Material Design 3 (including Material 3 Expressive where the project already uses it) and
> Android's adaptive/edge-to-edge/predictive-back requirements. Prefer Material 3 Compose
> components (NavigationBar, TopAppBar, Scaffold, FAB where Android uses one, ModalBottomSheet,
> dialogs, snackbars). Do not open or imitate the iOS project, and never reproduce iOS
> glass/floating chrome. Before coding, output your **Platform design brief** (Step 3). After
> coding, output the **Fidelity checklist** (Step 5) with evidence.

If only one platform is in scope this session, still apply that lane's rules, and add a note
to the stream that the other lane has not been checked.

## Step 3 — Platform design brief (each lane, before coding)

A short list, one line each: navigation container used; how the user goes back; where the
primary action lives; which system components replace each custom piece you were tempted to
build; which system features you adopt (Dynamic Type / font scaling, dark mode, dynamic color,
haptics, safe areas / insets, localization, accessibility labels). If a line says "same as
`<other platform>`", the brief is rejected — redo it from the platform's conventions.

## Where the platforms MUST differ

Use this as the default answer. Version specifics move fast: when you rely on an API or a
guideline detail, check the current Apple HIG / Material 3 docs and the project's deployment
target (min iOS, min/target SDK) before using it.

| Area | iOS (Apple HIG, Liquid Glass era) | Android (Material 3 / Expressive) |
|---|---|---|
| Top-level navigation | `TabView` tab bar for 2–5 sections. On iOS 26 it is system-drawn Liquid Glass and may float and minimize on scroll; take it from the system, do not hand-build it. Sidebar-adaptable on iPad. | `NavigationBar` fixed at the bottom for 3–5 destinations; `NavigationRail` on medium/expanded widths (tablets, foldables); navigation drawer only for many destinations. Not floating, not glass. |
| Screen header | `NavigationStack` bar: large title that collapses, inline title, toolbar items with system glass styling. | `TopAppBar` (small / center-aligned / medium / large that collapses with scroll). Title left-aligned by default. Actions as icons, overflow menu for the rest. |
| Back | Back chevron with the previous title in the nav bar **and** the edge-swipe gesture. Never a custom floating back circle over content. | System back (gesture/button) with **predictive back** animations; up arrow in the `TopAppBar` for hierarchy. Never a floating iOS-style back pill. |
| Primary action | Prefer a toolbar button (e.g. "+" / "Add" top trailing) or an inline prominent button. A floating action button is not an iOS idiom. | `FloatingActionButton` / extended FAB is a legitimate Material pattern, positioned per Material (bottom end, above the nav bar, aware of insets). |
| Search | `searchable` search field in the nav bar / toolbar search; scope bars; on iOS 26 search can live in the bottom toolbar. | `SearchBar` / `DockedSearchBar` / `SearchView` per Material, or an action in the top bar. |
| Modal content | Sheets with detents (`presentationDetents`), grabber, swipe-to-dismiss; full-screen covers sparingly. Alerts and confirmation dialogs / action sheets for choices. | `ModalBottomSheet` / `BottomSheetScaffold`, `AlertDialog`, full-screen dialog; destructive confirm via dialog; transient feedback via **Snackbar**. |
| Transient feedback | Inline state change, haptic, alert when blocking; no Snackbar. | `Snackbar` with optional action; `Toast` only for trivial system-like messages. |
| Lists | `List` / `Form` inset grouped; **swipe actions** (leading/trailing), swipe-to-delete, pull-to-refresh via `refreshable`. | Material list items with leading/trailing content; swipe-to-dismiss via `SwipeToDismissBox` only when it fits; `PullToRefreshBox`; long-press for contextual actions. |
| Controls | `Toggle` (switch), segmented `Picker`, wheel/compact date and time pickers, `Stepper`, `Menu`. | Material `Switch`, `SegmentedButton`, Material date/time pickers (dialog or input), `Slider`, exposed dropdown menus, chips. |
| Typography | SF Pro via text styles (`.title`, `.body`…) that scale with **Dynamic Type**. | Roboto/system font via `MaterialTheme.typography` roles; scale with font size/`sp`. |
| Icons | SF Symbols (weights, rendering modes, hierarchical/palette). | Material Symbols / Material icons. Never ship SF Symbols look-alikes on Android or Material icons on iOS. |
| Color / theme | Asset-catalog colors, `tint`/accent, semantic system colors, Liquid Glass materials supplied by the system; light/dark. | `ColorScheme` (light/dark), **dynamic color / Material You** where appropriate, tonal surfaces and elevation. |
| Motion & haptics | Spring animations, matched-geometry transitions, system haptics (`UIImpactFeedbackGenerator` / `.sensoryFeedback`). | Material motion (container transform, shared axis, fade through), predictive back, `HapticFeedback`/`VibrationEffect` used sparingly. |
| System space | Safe areas, Dynamic Island / home indicator, keyboard avoidance. | **Edge-to-edge** with `WindowInsets` (enforced on recent target SDKs), gesture navigation insets, IME insets, display cutouts. |
| System integration | Share sheet, widgets (WidgetKit), Live Activities, App Intents/Siri, notification categories, Sign in with Apple, permission prompts with usage strings. | Share intent / sharesheet, widgets (Glance), notification channels, App Shortcuts, Credential Manager / passkeys, runtime permission flow with rationale. |
| App entry | Launch screen storyboard, app icon (layered for iOS 26 icon system). | `SplashScreen` API, adaptive/themed icon, per-app language, predictive back opt-in. |

Anything not in the table: ask "what does a first-party app on this OS do here?" (Apple apps
like Notes/Mail/Health/Maps for iOS; Google apps like Gmail/Maps/Calendar/Keep and the
Material 3 guidelines for Android) and do that.

## Step 4 — Build, staying in the lane

- iOS lane edits only the iOS project; Android lane edits only the Android project. Shared
  contract files (API schema, localized strings source, analytics event names) are the only
  things both may read.
- Prefer the most native toolkit the project already uses (SwiftUI/UIKit; Compose/Views).
  Do not introduce a cross-platform UI library to "save time".
- Accessibility is native on both: VoiceOver labels/traits/rotor order on iOS; TalkBack
  `contentDescription`/semantics/focus order on Android; Dynamic Type and font scale at the
  largest sizes without clipping; touch targets ≥ 44 pt iOS and ≥ 48 dp Android.

## Step 5 — Fidelity checklist (each lane, with evidence)

Each lane ends with this list, answered yes/no with a screenshot or a code reference:

1. Navigation container and header are the platform's own, and a user of the OS's first-party
   apps would recognize them.
2. Back behavior is the OS's (iOS swipe/chevron; Android system + predictive back).
3. No component, motion or layout was copied from the other platform.
4. Primary action follows this OS's idiom (iOS toolbar / inline; Android FAB where it fits).
5. Sheets, dialogs, menus, pickers, switches and feedback use system components.
6. Dark mode, text scaling (Dynamic Type / font scale max), and RTL/localization checked.
7. Safe areas / insets correct on a notched or gesture-nav device; keyboard does not cover input.
8. Accessibility: screen reader walk-through of the main path completed.
9. Runs on a real small and a real large screen (phone + tablet or foldable where supported).
10. Screenshots attached for light + dark.

## Step 6 — Cross-lane audit (a third look, after both lanes finish)

Run this before the work is called done; ideally by a separate reviewer agent that sees both
diffs:

- **Alien-pattern grep** — search the diff for imports/usages that betray a copied pattern:
  - In **Android** code, flag: glass/blur floating bars (`Modifier.blur` or custom blur used for
    chrome, `RenderEffect` on nav surfaces), a bottom bar implemented as a floating rounded pill
    over content, circular back buttons floating over content, iOS-style segmented tab
    headers, "large title that is not a TopAppBar", SF-Symbol-like custom icons, iOS-style
    action sheets in place of `ModalBottomSheet`/dialogs.
  - In **iOS** code, flag: `Scaffold`-style or Material-looking components, a Material
    `FloatingActionButton` clone, a hamburger/drawer as primary navigation, Snackbar clones,
    ripple-style touch effects, Android-style top-left left-aligned app bars with an up-arrow,
    Roboto, Material icons.
- **Side-by-side review** — put the two lanes' screenshots next to each other. They should
  share content and flow, and *differ* in chrome. If they look the same, treat it as a
  defect and re-run the lane that copied.
- **The picky-user test** — for each platform answer: "Would a long-time user of this OS find
  anything here that feels foreign?" Any "yes" is a blocker.

## Step 7 — Feedback translation (when the human reviews)

When the owner gives feedback after testing on one device:
1. Restate the **intent** ("make the primary action easier to reach"), not the iOS widget.
2. Apply it to the tested platform in its own idiom.
3. Apply the *intent* to the other platform in **its** idiom (or state why it does not apply).
4. Never "make Android match what I just saw on iPhone" unless the owner explicitly says that
   screen is a deliberate-same screen (Hard rule 7).

## Output format

At the end of your turn report, in this order:
1. Behavior spec (a few lines) and which lanes ran.
2. Per lane: Platform design brief + Fidelity checklist results.
3. Cross-lane audit result (alien patterns found/fixed, picky-user verdict per platform).
4. Deliberate divergences/sameness to record in `## Knowledge delta`.
5. What was not verified (e.g. no Android device test) — state it plainly.

## Common mistakes

| Mistake | Fix |
|---|---|
| Porting the iOS view as the Android screen "to save time" | Port the spec, not the view. Re-derive with Material components. |
| Floating glass tab bar / floating FAB / floating back button on Android | `NavigationBar` + `TopAppBar` + predictive back. |
| Hand-building a custom tab bar or nav bar on iOS | Use `TabView` / `NavigationStack` so the system supplies Liquid Glass and behaviors. |
| Putting a Material FAB on iOS because Android has one | Use a toolbar button or inline prominent button on iOS. |
| Applying the iPhone feedback literally to Android | Translate the intent (Step 7). |
| Only the platform the owner tests gets rigor | The untested platform is where drift happens: run the Fidelity checklist on both every time. |
| Same icon set / same font on both | SF Symbols + SF on iOS; Material Symbols + Roboto/system on Android. |
