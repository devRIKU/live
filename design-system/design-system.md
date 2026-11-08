# Lively Design System

**Version 1.0.0 · 2026-10-21**

Token source of truth: [`tokens.css`](./tokens.css) · machine-readable mirror: [`tokens.json`](./tokens.json) · live gallery: [`styleguide.html`](./styleguide.html)

---

## 1. Why this system exists

The chat UI started as a single HTML file with values inline. That works until you need the same accent in three places, or a dark mode, or a second surface. This system exists so that **a value is decided once**.

It is deliberately not a general-purpose component library. It is the system *for this product*: an Apple-HIG-shaped assistant chat, with three effects borrowed from brands that actually solved this problem.

---

## 2. Lineage

| Source | What we took | Where it shows up |
|---|---|---|
| **Apple HIG** | Semantic colour roles, shape taxonomy (fixed / capsule / concentric), material translucency, type scale, ~1.3× leading, 44pt targets | The whole structural layer — surfaces, fills, separators, shape radii, motion curves |
| **Sarvam AI** | The continuous **blue→orange spectrum** as a *signal of flow*, not decoration | `--flow-spectrum`, the streaming caret, the generation bar, the aurora |
| **Mistral AI** | **Chunky-pixel emblem** construction (monochrome sprite + one accent pixel), hairline architectural grid | The LF pixel monogram, the arch grid behind the empty state |

Values from Sarvam and Mistral were extracted from their published CSS and brand pages rather than recalled — see `sources.extractedTokens` in `tokens.json`.

---

## 3. Architecture

```
Layer 1 · PRIMITIVE    raw values, no meaning          --p-*, --s-*, --r-*, --t-*, --e-*, --d-*
Layer 2 · SEMANTIC     role names, theme-aware         --canvas, --text-primary, --fill-2, --spec-hi
Layer 3 · COMPONENT    bindings per part              --composer-radius, --popover-shadow, --send-size
──────────────────────
EFFECTS               the special treatments           --flow-spectrum, --spec-ring, --pixel-grid
MOTION                durations + easings              --d-*, --ease-*
```

**The rule:** component CSS may only reference **semantic** and **component** tokens. A primitive name appearing in a component stylesheet is a bug.

```css
/* ✗ primitive leakage */  background: #007aff;
/* ✓ semantic */           background: var(--accent);
```

Light and dark are the **same token names** with different values. A component never branches on theme.

### 3.1 Files

| File | Owns |
|---|---|
| `design-system/tokens.css` | Every token. The single source of truth. |
| `design-system/motion.css` | Keyframes, motion utilities, the reduced-motion policy. |
| `design-system/lively-app.css` | The application shell — sidebar, thread, composer, popovers, account menu, settings dialog. Extracted verbatim from `Chat UI v3.html`. |
| `design-system/lively-settings.js` | The account menu and the settings dialog, shared by the app and the mockups. |
| `design-system/design-system.md` | This document. |
| `design-system/tokens.json` | The machine-readable mirror of the tokens, effects and rules. |
| `design-system/styleguide.html` | A live gallery of the tokens and effects. |

The shell has **one definition**. `Chat UI v3.html` and the milestone mockups in `openall-mockups/` both load
`lively-app.css` and the same markup, so a change to the shell reaches every screen at once. Nothing is
re-implemented per screen.

```
openall-mockups/
  shell.js      the shell markup, extracted from Chat UI v3.html
  engine.js     one engine, nine screens — data, render, behaviour
  mockups.css   only the surfaces a milestone adds
  m1.html … m9.html   thin shells, one per milestone
  index.html    the gallery
```

---

## 4. Colour

### 4.1 Semantic roles

| Role | Light | Dark | Used for |
|---|---|---|---|
| `--canvas` | `#ffffff` | `#0d0c0b` | The page behind everything |
| `--surface` | `#ffffff` | `#000000` | Conversation canvas |
| `--surface-raised` | `#ffffff` | `#1c1c1e` | Popovers, menus |
| `--text-primary` | `#171614` | `#ffffff` | Message bodies |
| `--text-secondary` | `rgba(60,60,67,.62)` | `rgba(235,235,245,.62)` | Subtitles, hints |
| `--text-tertiary` | `rgba(60,60,67,.38)` | `rgba(235,235,245,.36)` | Timestamps, metadata |
| `--separator` | `rgba(60,60,67,.24)` | `rgba(84,84,88,.60)` | Hairlines |
| `--fill-1…4` | grey translucents | grey translucents | Chips, buttons, bubbles |
| `--accent` | `#007aff` | `#0a84ff` | Send button, selection, focus |

**Do not** invent a colour at the call site. If a role is missing, add it to `tokens.css` first.

### 4.2 The flow spectrum

```
--flow-spectrum: linear-gradient(90deg,
  #393cc1 0%,   /* Sarvam brand blue   */
  #6a88e2 26%,  /* Sarvam indigo-500   */
  #bed2ff 42%,  /* Sarvam periwinkle   */
  #eaaf1c 66%,  /* Sarvam gold          */
  #d5650f 100%  /* Sarvam brand orange  */
```

> **The rule:** the spectrum is **reserved for flow states** — generating, streaming, syncing. It is never a surface fill, never a card background, never decoration.
>
> If the spectrum is on screen, something is moving. If nothing is moving, the spectrum must not be on screen.

This is the one rule in the system most likely to be broken by accident, because a gradient looks good in almost any position. It looks good because it is *not* decoration — it means something. Keep that meaning.

### 4.3 Why no purple

Indigo `#393cc1` is in the spectrum, so why is the product not "AI-purple"? Because purple appears **only inside the flow spectrum**, never as a surface. A chat interface with purple walls reads as a template; a chat interface with a purple-to-orange thread of light *while generating* reads as a signal.

### 4.4 Two themes, one declaration

There is no light palette and a dark palette. There is one palette that knows it has two states:

```css
--canvas:     light-dark(#ffffff, #0d0c0b);
--separator:  light-dark(rgba(60,60,67,.24), rgba(84,84,88,.60));
```

`light-dark()` reads `color-scheme`, so the declaration resolves at use time:

```css
:root { color-scheme: light dark; }                 /* the OS decides */
:root[data-theme="light"] { color-scheme: light; }  /* the user decides */
:root[data-theme="dark"]  { color-scheme: dark; }
```

The attribute is set by the Settings dialog and stored in `localStorage`. Removing the attribute hands control
back to the device.

**One rule to remember:** `light-dark()` carries **colours**, not shadows. A shadow keeps its geometry and
borrows a theme-aware colour:

```css
--shadow-color-1:   light-dark(rgba(0,0,0,.05), rgba(0,0,0,.50));
--composer-shadow-1: 0 1px 2px var(--shadow-color-1);
```

> Before this the palette lived in two blocks — a light `:root` and a `@media (prefers-color-scheme: dark)`
> override. The two drifted: the component layer's `--composer-shadow` sat *after* the dark block, so dark mode
> was silently using the light shadow. One declaration cannot drift.

---

## 5. Shape

Three types, from the iOS 26 HIG taxonomy. Nothing else is allowed.

| Type | Rule | Example |
|---|---|---|
| **Fixed** | Constant radius regardless of size | Sidebar row `6px`, popover `20px`, bubble `18px` |
| **Capsule** | Radius = half the height | Composer `26px` at `52px` tall; send button `50%` at `36px` |
| **Concentric** | Child radius = parent radius − parent padding | Composer `26px` − padding `8px` = chip `18px` |

The composer is the worked example: a `26px` capsule containing `36px` buttons. A button sitting on the capsule's inner edge needs `26 − 8 = 18px` so the two curves share a centre and read as one shape rather than a button glued onto a pill.

---

## 6. Effects

### 6.1 Specular rim — the fake lighter border

A **true 1px gradient ring** painted on a masked pseudo-element:

```css
.u-specular::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  padding: 1px;
  background: var(--spec-ring);
  mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0);
  mask-composite: exclude;
  pointer-events: none;
}
```

The mask punches the content box out, so only the edge survives. The element's own background is untouched.

**Three gradient layers, because one gradient cannot do both jobs.**

| Layer | Job |
|---|---|
| `radial-gradient(… at 0% 0%)` | The light source — a bright pool at the top-left corner |
| `radial-gradient(… at 100% 100%)` | Bounce light off the far corner |
| `linear-gradient(180deg, …)` | The edge-on ramp that darkens the bottom |

A single 148° linear gradient looked correct on a square and **failed on the composer**: the capsule is 720×56, so the gradient's dark stop at 83% landed off the element entirely and the bottom edge never darkened. Corner and edge gradients are computed over the element box, so they behave on wide surfaces.

**Why a mask and not a gradient border.** The `background-clip` trick — face on `padding-box`, edge on `border-box` — needs an **opaque** face to mask the border-box layer. Every glass surface here uses `backdrop-filter`, so the edge bleeds through the interior. The styleguide shows both side by side.

**Why not four inset shadows.** That was the first attempt and it did not work: four flat 1px lines have no falloff, and a white line on a white surface is invisible. The composer's face is only a few percent off the page, so the light had nothing to contrast against. A gradient ring carries the light *through* the falloff and, crucially, makes the bottom-right edge visibly darker than the top-left — that difference is what reads as a lit object rather than an outlined shape.

**Focus re-lights the rim.** `data-focused="true"` swaps the ring for `--spec-ring-focus`, an accent-tinted version. The old design drew a 3.5px blue halo around the whole control, which fought the capsule's own shape; now the light simply changes colour, and the surface keeps its silhouette.

**In dark mode the source dims and the underside goes near-black** (`rgba(0,0,0,.72)`), because that is what a dark glass edge does. The inner far-wall shadow (`--spec-lo-in`) gives the face visible depth.

### 6.2 Sheen — the Liquid Glass sweep

`.u-sheen` adds a moving diagonal highlight that fades in on hover. This is the effect that makes a surface read as *glass* rather than as *a grey box*. Use it on surfaces that lift off the page (popovers, raised buttons). **Not** on the composer — it is on screen constantly and a moving highlight there is noise.

### 6.3 Pixel motif

Mistral's emblem is a chunky pixel sprite in monochrome with exactly one accent pixel. The LF monogram uses the same construction: a pixel-matrix `LF` in `--text-primary` with a single pixel in the flow colour.

```css
--pixel-grid:                     /* 8px pitch, for small accents */
  repeating-linear-gradient(0deg,  var(--pixel-line) 0 1px, transparent 1px 8px),
  repeating-linear-gradient(90deg, var(--pixel-line) 0 1px, transparent 1px 8px);

--arch-grid:                      /* 32px pitch, architectural hairline */
  repeating-linear-gradient(0deg,  var(--arch-line) 0 1px, transparent 1px 32px),
  repeating-linear-gradient(90deg, var(--arch-line) 0 1px, transparent 1px 32px);
```

> **The rule:** exactly **one** accent pixel per pixel emblem. Ambient grid texture stays at or below **0.06** opacity. A pixel grid at full strength is a texture; at 0.05 it is a material.

---

## 7. Type

System font, per HIG: `-apple-system / SF Pro`. On macOS and iOS this is San Francisco. On Windows it resolves to Segoe UI — the two platforms will not be pixel-identical, and that is the correct trade for shipping a system-native feel over a bundled webfont.

| Role | Size / line | Weight | Tracking | Use |
|---|---|---|---|---|
| display | 30 / 36 | 600 | −0.022em | Empty-state headline |
| title | 22 / 28 | 600 | −0.014em | Section titles |
| headline | 17 / 22 | 600 | −0.011em | Composer chip, sidebar title |
| body | 16 / 22 | 400 | 0 | Message bodies |
| callout | 15 / 20 | 400 | — | Empty-state subcopy |
| subhead | 14 / 19 | 400 | — | Popover items, sidebar rows |
| footnote | 13 / 17 | 400 | — | Timestamps, hints |
| caption | 12 / 16 | 400 | — | Metadata |
| micro | 11 / 14 | 500 | — | Group labels |

Leading is ~1.3–1.375×. Body copy stays inside 35–50 characters per line.

---

## 8. Motion

Motion lives in its own layer: **`design-system/motion.css`**. It holds the keyframes, the utility classes and the
reduced-motion policy. `tokens.css` holds only the values. Nothing else defines an animation.

### 8.1 The four jobs

Motion in this product does exactly four things. Anything that does not do one of them is animation debt.

| Job | What it means | Example |
|---|---|---|
| **Feedback** | Confirm the interface heard you | Send button wakes when the composer has text |
| **Continuity** | Explain where a thing went or came from | Artifact panel slides in from its own edge |
| **State** | Make a change of state legible | Provider dot crossfades to *rate-limited* |
| **Focus** | Point at the one thing that matters now | The approval gate reveals its arguments in order |

### 8.2 The focal moment

There is exactly one authored sequence in the product: **the approval gate**. A tool call arrives mid-stream, the
stream pauses, and the permission request materialises with its tool name, target and exact arguments revealing
line by line, then the Allow and Deny buttons last.

The motion exists to make you read it. You are authorising something that will run outside the chat, and a
staged reveal is the only way to make sure that happens. Everything else in `motion.css` is supporting motion.

### 8.3 Durations

Distance and consequence decide the number. Feedback is fast, layout change is slower, an authored entrance is
slowest.

| Token | Value | Use |
|---|---|---|
| `--d-instant` | `90ms` | Press release, colour tick |
| `--d-fast` | `140ms` | Hover, chip state |
| `--d-base` | `180ms` | Routine state change, toggle |
| `--d-slow` | `260ms` | Popover, panel, layout shift |
| `--d-slower` | `380ms` | Overlay enter, drawer, message arrival |
| `--d-entrance` | `520ms` | Authored focal entrance |

Exit is faster than entrance. Entrance uses `--ease-out-expo`.

### 8.4 Easing

| Token | Curve | Use |
|---|---|---|
| `--ease-out` | `cubic-bezier(.23,1,.32,1)` | Anything entering. Starts fast, feels responsive. |
| `--ease-out-quart` | `cubic-bezier(.25,1,.5,1)` | Small surfaces. |
| `--ease-out-quint` | `cubic-bezier(.22,1,.36,1)` | General purpose emphasis. |
| `--ease-out-expo` | `cubic-bezier(.16,1,.3,1)` | Entrances, staged reveals. |
| `--ease-in-out` | `cubic-bezier(.77,0,.175,1)` | Movement on screen. |
| `--ease-ios` | `cubic-bezier(.32,.72,0,1)` | Drawers, sheets, slider knobs, progress. |
| `--ease-spring` | `cubic-bezier(.22,1.08,.36,1)` | Overshoot ≈ 0.08. A whisper, not a bounce. |

**Never `ease-in` on a UI element.** It delays the first movement — the exact moment the user is watching.

> `--ease-spring` was `cubic-bezier(.34,1.36,.64,1)` in v1 — a 0.36 overshoot. Above roughly 0.1 it reads as dated
> for a serious product tool, so it was redefined to 0.08. The name stayed; the behaviour did not.

### 8.5 Rules

- **Only `transform` and `opacity` animate.** Animating `width`, `height`, `padding` or `margin` triggers layout.
  Progress bars scale on `X`; they never animate their width.
- **Never animate from `scale(0)`.** Nothing in the real world appears from nothing. Start at `scale(.96)` with
  opacity, or `translateY(8px)` with opacity.
- **Never animate a keyboard-initiated action.** A user pressing a key hundreds of times a day wants the state,
  not a performance.
- **Only one loop is allowed to run without a reason:** the live status dot. It says *this is running*. A
  decorative loop is noise.
- **Stagger only siblings that arrive as a list.** `--stagger-step: 60ms`, capped at `--stagger-cap: 320ms` so
  the last item never arrives late.

### 8.6 Reduced motion

Under `prefers-reduced-motion: reduce`, **keep the state change, drop the travel**.

- Opacity transitions stay — they carry comprehension.
- Transform, clip-path and filter motion goes.
- The streaming caret stays **visible and solid**, because it carries "still generating" — information, not
  decoration. It is the test case for the whole policy.
- Loops stop; a live dot becomes a static, legible dot.
- A skeleton becomes a plain block, not a frozen shimmer.
- Progress jumps to its value instead of sweeping.

---

## 9. Component contracts

### Composer
- `28px` capsule, `56px` min height, `8px` padding
- Children at `20px` radius (concentric: 28 − 8)
- Send button is a `34px` circle — capsule geometry
- **One control at the left, the field in the middle, every secondary control grouped at the right** with the primary action outermost. The effort chip lives in that right cluster, not between the `+` and the text — a chip parked at the left pushes the start of every line you type.
- The effort chip owns its popover, so the popover can anchor to the trigger exactly rather than to the composer
- Send states: **muted** (nothing to send) → **ready** (accent, arrow wakes from `scale(.86)` on the spring curve) → **stop** (accent, arrow crossfades to a rounded square)
- Focus re-lights the rim instead of drawing a halo around the capsule

### Popover
- `20px` radius, hairline border, elevation 3
- **Scales from its trigger**, not from centre (`transform-origin` at the trigger corner)
- Dismissed by outside click and by `Escape`

### Sidebar
- `244px`, translucent material, `backdrop-filter: saturate(180%) blur(20px)`
- Rows: `6px` radius, `13px` text
- Below `860px` it becomes an overlay drawer with a scrim

### Message hierarchy
- Assistant: **plain text, no bubble** — the reply is the page
- User: `--fill-1` bubble, right-aligned, `18px` radius

### Account menu
- The profile row in the sidebar footer is a **button**, not a label. It opens a menu upward, anchored to the
  row, with `transform-origin: 0 100%` so it scales from its own corner.
- Three items only: **Settings**, **Keyboard shortcuts**, **Reset demo**. Destructive items carry `data-tone="danger"`.
- `Reset demo` is two-step: the first click arms it and says so, the second acts. A destructive action that
  takes one click is a trap.
- Implemented once in `design-system/lively-settings.js` and used by the app and every mockup.

### Settings dialog
- A **modal**, not a sidebar page — settings are a detour, not a place you live.
- `720px` wide, a `178px` nav column and a scrolling content column. On narrow screens the nav becomes a
  horizontal strip above the content.
- Controls are limited to three kinds: **segmented** (theme), **switch** (a boolean), and **field** (a string).
  Anything else is a sign the setting is not a setting.
- Every control writes to `localStorage` and takes effect **immediately** — no Save button for switches, and
  the Save button on the text fields confirms what it did.
- The dialog lives outside `.ds-reset`, so it carries its own font, box model and button reset.

---

## 10. Checklist

Before merging any surface:

- [ ] No primitive token referenced outside `tokens.css`
- [ ] No colour invented at the call site
- [ ] Radii from fixed / capsule / concentric only
- [ ] Flow spectrum only in a flow state
- [ ] At most one accent pixel per pixel emblem
- [ ] Ambient texture at or below 0.06 opacity
- [ ] Only `transform` and `opacity` animate; UI animation under 300ms
- [ ] `prefers-reduced-motion` keeps the caret visible and all states legible
- [ ] Both themes checked; no theme branching in components
- [ ] Keyboard: `Escape` closes popovers, slider is arrow-key operable, focus is visible
- [ ] Touch targets at least 44×44
- [ ] Every button does something observable — no dead affordances
- [ ] Every menu is operable by pointer **and** keyboard, and closes on `Escape` and on outside click
- [ ] Anything destructive asks twice
