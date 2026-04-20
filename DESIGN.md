# Atriarch DESIGN.md — Range Console

Design system for the Atriarch reactive target training app.

**Scope:** Gate 1 ships LIGHT theme only (outdoor-readable, primary per CEO doc). DARK theme + ambient-light auto-toggle land in Gate 2. See addendum §7.2 in the implementation plan for the toggle rules.

**Authority:**
- CEO design doc: `~/.gstack/projects/AtriarchTraining-Atriarch/jeremygill-feature-system-v2-design-20260419-133046.md`
- Eng plan: `~/.gstack/projects/AtriarchTraining-Atriarch/eng-plans/2026-04-20-atriarch-v2-engineering-plan.md`
- Design review addendum v2: see end of `docs/superpowers/plans/2026-03-31-atriarch-implementation.md`

When this file conflicts with the addendum or the CEO/eng docs, those win. Update here when a decision changes.

---

## Aesthetic

Industrial instrument. Range console vibe — serious tool, not a marketing site, not a consumer toy.

**First-5-seconds (visceral):** brand moment is the timer and the STOP button. Not chrome. Not gradients.

**5-minutes (behavioral):** screens do one job each. Trainer finds the next action without thinking.

**5-year (reflective):** aesthetically bulletproof — no trends that date the app inside a year.

---

## Color tokens

### LIGHT theme (Gate 1 — primary, outdoor-readable)

```
--l-bg-base:         #FFFFFF
--l-bg-elevated:     #F2F5FA
--l-bg-card:         #E8EDF5
--l-border:          #C3CBD9
--l-text-primary:    #0A0D12    (contrast 18.4:1 vs bg-base — AAA)
--l-text-secondary:  #3A4355    (contrast 9.3:1 vs bg-base — AAA)
--l-text-tertiary:   #6A7388    (contrast 4.8:1 vs bg-base — AA, use for non-essential only)

--l-status-armed:        #B76E00  (amber)
--l-status-live:         #0E7A3E  (green)
--l-status-hit:          #1E4FC7  (blue)
--l-status-violation:    #B3001F  (deep red — no-shoot hit)
--l-status-late:         #B36F00  (warm orange)
--l-status-offline:      #6A7388  (grey)
--l-status-unreachable:  #B3001F  (same red as violation — it matters)
```

### DARK theme (Gate 2 — indoor / low-ambient, secondary)

```
--d-bg-base:         #0A0D12
--d-bg-elevated:     #141820
--d-bg-card:         #1A1F2A
--d-border:          #2A3140
--d-text-primary:    #E8EDF5
--d-text-secondary:  #8892A8
--d-text-tertiary:   #4A5365

--d-status-armed:        #F5A623
--d-status-live:         #39D98A
--d-status-hit:          #5B9BFF
--d-status-violation:    #FF3B4D
--d-status-late:         #FFB547
--d-status-offline:      #4A5365
--d-status-unreachable:  #FF3B4D
```

### Group-color palette (5 groups, for §7.3 Preview Groups)

Used on WS2812 LEDs AND on in-app group tints. Tested for deuteranope/protanope distinguishability.

| Group | LED (CRGB) | In-app tint (LIGHT) | In-app tint (DARK) |
|-------|-----------|---------------------|--------------------|
| G1 magenta | `CRGB(255, 0, 120)` | `#C71585` | `#FF3DB0` |
| G2 cyan    | `CRGB(0, 200, 255)` | `#0891B2` | `#22D3EE` |
| G3 yellow  | `CRGB(255, 200, 0)` | `#B45309` | `#FACC15` |
| G4 purple  | `CRGB(140, 0, 255)` | `#6D28D9` | `#A78BFA` |
| G5 lime    | `CRGB(140, 255, 0)` | `#4D7C0F` | `#84CC16` |

**Sim Daltonism pass pending** (addendum §11) — may adjust magenta/purple pairing before firmware lock.

---

## Typography

| Token | Font | Usage |
|-------|------|-------|
| `--font-mono` | JetBrains Mono | All numerals — timer, timing values, stats, event log timestamps |
| `--font-sans` | Inter Tight | Labels, headers, body copy |

**Not** Roboto. **Not** plain Inter. **Not** the Material default.

**Scale (pt):** 12 · 14 · 16 · 20 · 28 · 48 · 96 (timer hero)

**Weights:** 300 (hero numerals) · 500 (body) · 700 (headers)

**Delivery (Gate 1):** via `google_fonts` package, lazy-fetched on first use and cached. Works offline after first connection. **Before field test (Gate 4):** bundle `.ttf` files in `assets/fonts/` and switch to declared-asset loading so the app works on the range even if the phone has never touched WiFi.

---

## Spacing scale

`4 · 8 · 12 · 16 · 24 · 32 · 48 · 64`

No ad-hoc values. `AtriarchSpacing.md` = 16, etc.

---

## Radius

| Token | Value | Usage |
|-------|-------|-------|
| `--radius-sm` | 4 | Inputs, chips |
| `--radius-md` | 8 | Cards, buttons |
| `--radius-lg` | 12 | Sheets, large surfaces |

**No pill buttons. No circles** — except the STOP panic button at 200pt, which is a deliberate physical metaphor.

---

## Motion budget

Four intentional motions. Nothing decorative.

1. **Connection banner slide-in/out** — 300ms ease-out
2. **DRILL ACTIVE breathe-pulse** — 2s loop, opacity 0.75→1.0→0.75
3. **STOP ring-fill on press-hold** — 800ms linear (addendum §7.1)
4. **Theme cross-fade on auto-toggle** — 400ms (Gate 2)

`MediaQuery.disableAnimations` = breathe stops, STOP becomes single-tap, cross-fade is instant, banner is instant.

---

## Touch targets

- **Minimum:** 44pt (Apple HIG)
- **Primary action:** 56pt (START, rename confirm, wizard Continue)
- **STOP:** 200pt circle
- **IncDec buttons:** 44pt min each

Gloved thumb and phone-in-grease-stained-hands don't forgive small touch targets.

---

## Contrast

- Body text ≥ **7:1** (AAA) against base bg
- Large text ≥ 4.5:1
- Status colors against their backgrounds audited at each theme

Light-theme-at-max-brightness is the sun use case. Dark-theme is indoor/dusk only.

---

## Iconography (allowlist)

Material Symbols rounded, locked set:

```
bluetooth, bluetooth_disabled, refresh, flash_on, gps_fixed,
check_circle, warning, home, block, gpp_good, gpp_bad,
ios_share, volume_up, photo_camera, groups, person,
play_arrow, chevron_right, more_vert, edit, delete, settings
```

New icons require updating this doc first.

---

## Accessibility rules

- Every IconButton: `tooltip` + `Semantics(label:)` with an intent verb
- Color is never the only signal — status is double-encoded (color + icon + text)
- Reduce Motion: respected per motion budget above
- Dynamic Type: respected up to 1.3× scale factor; clamped above (timer clips otherwise)
- VoiceOver: test pass on primary flows before field test; drill-event announcements opt-in in Settings

---

## Outdoor rule

When the auto-theme (Gate 2) flips to LIGHT:
1. Restore prior manual brightness as a fallback
2. Force `ScreenBrightness.setScreenBrightness(1.0)` (via `screen_brightness` package)
3. Revert on backgrounding or leaving drill/setup context

Light-theme-without-max-brightness is NOT the design. Both pieces ship together.

---

## Implementation

See `lib/theme/atriarch_theme.dart`. All tokens are exposed via `ThemeExtension<AtriarchTokens>`. Access in widgets:

```dart
final tokens = Theme.of(context).extension<AtriarchTokens>()!;
Container(color: tokens.statusLive, ...)
```

Never use `Colors.blue` or hex literals in widgets. Always go through tokens. CI (future) should grep-gate against `Colors\.` imports in `lib/screens/` and `lib/widgets/`.
