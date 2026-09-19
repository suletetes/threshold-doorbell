# Aggressive UI/UX Audit: Threshold

Judged against Linear, Arc, Raycast, Superhuman, Stripe Dashboard, and the top tier of Flutter apps.
Not against average apps. Every finding cites real files and real values read from the codebase.

Scope audited: `app/lib/main.dart`, `app/lib/app/home_screen.dart`, `app/lib/session/conversation_screen.dart`,
`app/lib/session/captions_only_screen.dart`, `app/lib/captions/caption_surface.dart`,
`app/lib/settings/settings_screen.dart`, `app/lib/reply/reply_bar.dart`,
`app/lib/permissions/permission_prompt.dart`, `app/lib/consent/recording_notice_screen.dart`,
plus `app/lib/settings/settings_state.dart` and `app/lib/session/watermark_safe_area.dart`.

---

## 1. Executive summary

**Current level: competent engineering prototype. Roughly 4/10 on visual craft.**
**Target level: premium accessibility product. 9/10.**

The engineering underneath is genuinely strong: 287 passing widget and unit tests, a real state machine per
surface, semantics labels and live regions on every status region, an enforced 4.5:1 contrast floor, and a
200% text-scale clamp on the caption subtree. Accessibility is wired into the logic rather than bolted on.
That is the hard part and it is already done.

The presentation layer is where this loses. The product currently looks like a functional test harness, not a
shipped app. Three structural facts explain nearly every visual problem found:

1. **There is no design system.** No `theme/` or `design/` directory exists. Verified by directory listing.
2. **`main.dart` ships a one-line theme.** `ColorScheme.fromSeed(seedColor: Color(0xFF1565C0))` with
   `useMaterial3: true` and nothing else: no typography, no component themes, **no dark theme at all**.
3. **Every screen therefore styles itself inline**, with hardcoded hex and raw font sizes.

The consequence is that the app inherits stock Material defaults everywhere, and every surface drifts from
every other surface. A judge opening this app sees default buttons on a white background, then a near-black
video screen with a flat blue pill. Nothing signals intent.

**The opportunity is unusually large.** Because the logic is clean and fully tested behind interfaces, the
entire visual layer can be replaced without touching behavior. This is a presentation-only refactor with a
disproportionate payoff.

---

## 2. Critical issues (must fix)

### C1. No dark theme, on a product used in the dark
`main.dart` defines `theme:` only. There is no `darkTheme:` and no `themeMode:`. Yet
`conversation_screen.dart:63` hardcodes `backgroundColor: Color(0xFF0B0B0F)` (near-black) while
`home_screen.dart` and `settings_screen.dart` render on the default light surface. The user goes from a light
home screen to an almost-black conversation screen with no transition of visual language. A doorbell app is
used at night, at the door, often one-handed. Dark must be first-class, not accidental.

### C2. Hardcoded color literals scattered across screens
Concrete instances read from source:
- `conversation_screen.dart:63` `Color(0xFF0B0B0F)` scaffold
- `conversation_screen.dart:103` `Color(0xFF15151B)` video placeholder
- `conversation_screen.dart:~245` `Color(0xCC1565C0)` mode badge
- `conversation_screen.dart:~330` `Color(0xB3000000)` auth scrim
- `home_screen.dart:~62` `Color(0xFF555555)` helper text
There is no single source of truth, so these will drift further with every change. `Color(0xFF555555)` on
white is about 7.4:1, which passes, but it was chosen by eye rather than by role, and it is an unnamed
literal nobody will maintain.

### C3. Typography is ad hoc integers, not a scale
Raw sizes found in screens: `18` (home body), `22` (caption base, `caption_surface.dart:29`), `20`
(`_StatusPanel`, `_ErrorPanel`, auth title), `16`, `14` (home helper). No line heights except a few
`height: 1.3`, no letter spacing, no weight system beyond occasional `w600`/`w700`. Material 3 ships a
15-style scale with explicit line height and tracking for exactly this reason. Right now hierarchy is
communicated by arbitrary numbers, which is why the screens read flat.

### C4. Error states are dead ends
`_ErrorPanel` (`conversation_screen.dart`) renders a centered `Text` and nothing else. When the session fails,
the user sees "Couldn't connect to your doorbell." with **no icon, no retry button, no secondary action**.
For a deaf user who just missed a visitor, this is the highest-stress moment in the product and it offers no
path forward. This violates basic error-recovery heuristics and it is the single worst UX defect found.

### C5. The primary action has no visual weight
`home_screen.dart` is a `Column` containing a paragraph of 18px text, a stock `FilledButton` reading
"Answer the door", a helper line, and an `OutlinedButton` reading "Settings". "Answer the door" is the
entire reason the app exists. It should dominate the screen. Currently it is a default-width button that
looks identical in weight to Settings.

### C6. Zero motion
No `AnimatedSwitcher`, no transitions, no press feedback beyond Material's stock ink. The conversation screen
swaps hard between connecting, probing, live, reconnecting, and error. Because these panels are all centered
text, a state change can be nearly invisible, which is dangerous in a product where the user cannot hear a
cue. Motion here is not decoration, it is a redundant channel for state change on a surface used by people who
get no audio feedback.

### C7. Caption surface is under-designed for the product's centerpiece
`caption_surface.dart` maps confidence to "opacity/weight" only (per its own header comment). The caption
region in `conversation_screen.dart` is a plain `Container` with
`borderRadius: BorderRadius.circular(12)` and `withValues(alpha: 0.8)`. This is the hero surface of the entire
product and it is styled like a debug overlay. Provisional versus confident text deserves a deliberate,
legible treatment, not just alpha.

---

## 3. High-impact improvements (ranked by visible payoff per hour)

1. **Ship a real theme with light and dark.** A typed token layer plus a `ThemeData` factory with component
   themes for `FilledButton`, `OutlinedButton`, `Card`, `AppBar`, `Switch`, `Slider`, `Dialog`, `ListTile`,
   `SnackBar`. This alone lifts every screen at once, because all of them currently fall back to defaults.
2. **Redesign the caption surface.** Larger optical size, a defined container with proper elevation and a
   subtle border, clear speaker attribution per turn, and a distinct visual language for provisional text
   (for example reduced emphasis plus an explicit provisional marker) rather than raw opacity.
3. **Rebuild the home screen around one hero action.** A large, unmistakable primary action card with an
   icon and a supporting status line, with Settings demoted to an app-bar action or a quiet secondary row.
4. **Give every failure a recovery path.** Error state gets an icon, a plain-language cause, a primary
   "Try again", and a secondary escape (open the Ring app, or return home).
5. **Introduce purposeful motion.** Cross-fade plus slight vertical translation between session states,
   caption entry animation, and press scale on primary actions. All gated on
   `MediaQuery.disableAnimations` so reduced-motion users are respected.
6. **Add a status/banner component.** The Captions-Only banner, the offline state, the Privacy-Mode
   unavailable line, and the permission-denied explanation are four different ad hoc treatments of the same
   idea. One component, four semantic variants.
7. **Fix the analyzer baseline.** `dart analyze` reports 17 issues including a hard compile error in
   `test/widget_test.dart` (references a nonexistent `MyApp`). There is no `analysis_options.yaml` at all,
   so the project has effectively been running without a lint policy.

---

## 4. Detailed findings by dimension

### Typography
- No scale. Sizes are inline integers (see C3).
- No `TextTheme` defined anywhere, so all default Material styles are unmodified Roboto.
- Line height set only sporadically (`height: 1.3` in two places), so multi-line copy has inconsistent
  leading between screens.
- No letter spacing control. At the 22px+ caption size, default tracking is too loose for sustained reading.
- Weight vocabulary is thin: mostly regular, with `w600` on the mode badge and `w700` on two titles.

### Color and contrast
- Single seed color, no semantic roles. There is no token for "live", "recording", "provisional caption",
  "danger", or "success", even though the product has all four concepts.
- `settings_state.dart` does hold `captionForeground`/`captionBackground` with an enforced floor, which is
  genuinely good, but it is an island: the rest of the app does not participate in that discipline.
- Contrast on the enforced caption path is correct by construction (4.5:1 floor, verified by tests). Contrast
  elsewhere is unverified because colors are literals.

### Spacing, rhythm, density
- Padding values found: `20` (home), `12`, `16`, `24`, `8`. These are close to a 4dp grid but not derived
  from one, and `SizedBox(height: 24)` / `12` / `12` in `home_screen.dart` produce an uneven vertical rhythm.
- No density strategy for the settings list, which is the longest surface in the app.

### Iconography
- **There are effectively no icons.** Home has none. Error has none. The mode badge is text-only. Settings
  rows are text-only. Modern apps of this class use icons as the primary scanning aid; their absence is a
  large part of why the UI reads as unfinished.

### Radius, shadow, elevation, depth
- Radii are inline and inconsistent: `12` (caption container), `16` (mode badge), default on `Card`.
- No elevation system. The only depth cues are a raw scrim `Color(0xB3000000)` and default `Card` elevation.
- M3 ships a seven-step shape scale and tonal elevation; neither is used.

### Information architecture and cognitive load
- Home presents a paragraph before the action. Recognition over recall argues for the action first, with
  supporting text secondary.
- The Privacy-Mode-unavailable message sits between the primary and secondary buttons, interrupting the
  action group.
- Settings is a flat list with no grouping hierarchy, despite containing mode, captions, haptics, strobe,
  language, retention, erasure, and the recording notice. That is at least four distinct concerns.

### Feedback states
- Loading: bare `CircularProgressIndicator` plus text. No skeletons anywhere, so perceived performance is
  poor on first paint of any list.
- Error: dead end, no retry (C4).
- Empty: the caption empty state is a single line of placeholder text; acceptable but unstyled.
- Success: no success affordance at all. "Speaking at your door" is a text state with no completion cue,
  which matters because the user cannot hear that the reply played.

### Micro-interactions and motion
- None beyond stock ink (C6). No press feedback on the hero action, no caption entry, no state transitions.
- Positively: because nothing is animated, nothing currently violates reduced motion. Any motion added must
  check `MediaQuery.disableAnimations`.

### Touch targets and gestures
- Buttons use `Padding(vertical: 12)` inside `FilledButton`, which lands near but not provably at 48dp.
  Nothing in the codebase asserts a 48dp minimum.
- No swipe or long-press affordances where they would help (for example dismissing a transcript row).

### Focus and keyboard
- No `FocusTraversalGroup`, no explicit focus order, no visible focus ring customization. For a product whose
  users may rely on external keyboards or switch access, this is a real gap.

### Responsive and adaptive
- No breakpoints, no `LayoutBuilder`, no orientation handling. The conversation screen puts video in a
  `Stack` with the caption region in a `Column`; in landscape on a phone the caption area will be badly
  squeezed, which is precisely the orientation someone props a phone in to read captions.
- No tablet consideration.

### Dark mode and theme quality
- No dark theme (C1). The conversation screen is effectively a hardcoded dark island.

### Component consistency
- Four different inline "status message" treatments (`_StatusPanel`, `_ErrorPanel`, the Captions-Only banner,
  the Privacy-Mode line). No shared component.
- `_ModeBadge` is a bespoke pill that exists nowhere else.

### Perceived performance
- No skeletons, no optimistic states, no staged reveal. The first frame of any data-bearing surface is empty.

### Accessibility (the strongest area, worth protecting)
- Semantics labels and `liveRegion` on status panels, mode badge, caption region, and controls: present and
  correct. Keep all of it.
- Enforced 4.5:1 caption floor and the 200% clamp: present, tested, must survive any refactor.
- Gaps: no focus management, no `MediaQuery.disableAnimations` handling (moot today, critical once motion is
  added), and no asserted minimum target size.

### Flutter and mobile specifics
- `useMaterial3: true` is set, which is correct, but essentially none of M3's system is used.
- `SafeArea` is applied on home and conversation. Good.
- Watermark-safe insets (`watermark_safe_area.dart`) are a thoughtful, product-specific constraint. Preserve.
- No `SystemUiOverlayStyle` control, so status-bar icon contrast against the near-black conversation screen is
  left to chance.
- Navigation is raw `Navigator.push` with `MaterialPageRoute` and no custom transitions.
- No `Cupertino` adaptation anywhere despite shipping on iOS.
- Lists are plain `Column`s inside scroll views rather than builders, which will not scale for transcript
  history.

---

## 5. Specific recommendations

### `app/lib/design/` (new)
- `tokens.dart`: a 4dp-based spacing scale, a radius scale aligned to M3's shape steps, an elevation scale,
  and motion tokens (durations and curves) with a single `reducedMotion` helper.
- `colors.dart`: full light and dark `ColorScheme`s plus a `ThresholdSemanticColors` extension carrying
  `captionSurface`, `captionProvisional`, `live`, `recording`, `success`, `warning`, `danger`.
- `typography.dart`: an explicit scale with size, weight, height, and letter spacing per role.
- `theme.dart`: a `ThemeData` factory for light and dark including component themes for the widgets listed
  in section 3.1.
- `components/`: `StatusBanner` (info/warning/danger/success variants), `PrimaryActionCard`, `SectionHeader`,
  `EmptyState`, `Pill`, `SkeletonBlock`.

### `main.dart`
Wire `theme`, `darkTheme`, and `themeMode: ThemeMode.system`. Set `SystemUiOverlayStyle` per brightness.

### `home_screen.dart`
Hero `PrimaryActionCard` with a doorbell icon, a large label, and a live status line. Move Settings to an
`AppBar` action. Move the Privacy-Mode notice into a `StatusBanner` below the hero, out of the action group.
Remove the unused import and unused local flagged by the analyzer.

### `conversation_screen.dart`
Replace `_StatusPanel`/`_ErrorPanel` with themed components; give the error state an icon, a cause, a primary
"Try again", and a secondary escape. Wrap the state panels in an `AnimatedSwitcher` using motion tokens with
reduced-motion respect. Re-style `_ModeBadge` as the shared `Pill` with a semantic "live" color. Replace the
raw `0xB3000000` scrim with a themed scrim. Keep `watermarkSafeInsets()` exactly as-is. Add a landscape layout
that keeps captions readable.

### `caption_surface.dart`
Keep the emphasis logic and the enforced foreground and clamp. Change only the expression: per-turn speaker
attribution, a defined caption container from the theme, and a provisional treatment that is more than alpha.

### `captions_only_screen.dart`
The banner becomes `StatusBanner(variant: info)`. Keep the exact copy and the "Open Ring app" action; give
that action an icon and proper button weight.

### `settings_screen.dart`
Group into sections with `SectionHeader`: Captions, Alerts, Language, Privacy and data. Keep every control and
every semantics label. Make "Delete all my data" visually `danger`.

### `permission_prompt.dart`, `recording_notice_screen.dart`
Adopt the shared components so the consent and permission surfaces match the rest of the app.

### Tooling
Add `app/analysis_options.yaml` including `package:flutter_lints/flutter.yaml`, promote the current warnings to
errors, and fix all 17 reported issues including deleting the generated `test/widget_test.dart` that
references a nonexistent `MyApp`.

---

## 6. Priority roadmap

**Phase 1, foundation (largest payoff, unblocks the rest)**
1. `analysis_options.yaml` and clear all 17 analyzer issues to zero.
2. `app/lib/design/` tokens, colors, typography, theme factory.
3. Wire light and dark into `main.dart` with `themeMode: system`.

**Phase 2, the surfaces that judges see**
4. Home screen hero redesign.
5. Caption surface redesign (the product's centerpiece).
6. Conversation screen state panels, error recovery, mode pill, scrim.

**Phase 3, consistency**
7. Shared `StatusBanner` adopted by Captions-Only, offline, Privacy-Mode, permissions.
8. Settings grouping and danger styling.
9. Consent and permission surfaces onto the system.

**Phase 4, refinement**
10. Motion with reduced-motion respect.
11. Landscape and tablet layouts.
12. Skeletons for perceived performance; focus traversal; asserted 48dp targets.

---

## 7. Design principles to enforce going forward

1. **No literal in a screen.** Every color, size, radius, duration, and spacing value comes from a token. A
   raw hex or a raw font size in a widget file is a defect.
2. **Accessibility is a constraint, not a feature.** The 4.5:1 caption floor, the 200% clamp, semantics
   labels, and live regions are non-negotiable. A visual change that weakens them is rejected, however good
   it looks.
3. **Motion carries meaning or it does not ship.** Every animation must communicate a state change, and
   every animation must check reduced motion. This product's users cannot hear a cue; motion is a
   substitute channel, not ornament.
4. **Every failure offers a way forward.** No dead-end error states, ever.
5. **One concept, one component.** If two surfaces show a status message, they use the same component with
   different semantics.
6. **The hero action is unmistakable.** On any screen, the primary action should be identifiable in under a
   second.
7. **Dark is first-class.** Both schemes are designed and tested, not derived by accident.
8. **The analyzer is the floor, not the ceiling.** `dart analyze` stays at zero issues.
