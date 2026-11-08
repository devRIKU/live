---
name: Lively
description: Local-first AI workspace — precise, warm, tool-like
colors:
  canvas: "light-dark(#ffffff, #0d0c0b)"
  surface: "light-dark(#ffffff, #000000)"
  surface-raised: "light-dark(#ffffff, #1c1c1e)"
  surface-sunken: "light-dark(#fbfaf8, #101012)"
  surface-muted: "light-dark(#eceae7, #2c2c2e)"
  text-primary: "light-dark(#171614, #ffffff)"
  text-secondary: "light-dark(rgba(60,60,67,0.62), rgba(235,235,245,0.62))"
  text-tertiary: "light-dark(rgba(60,60,67,0.38), rgba(235,235,245,0.36))"
  text-inverse: "light-dark(#ffffff, #000000)"
  accent: "light-dark(#007aff, #0a84ff)"
  accent-hover: "light-dark(#0069df, #3d9bff)"
  accent-muted: "light-dark(rgba(0,122,255,0.14), rgba(10,132,255,0.20))"
  accent-text: "light-dark(#0071e3, #64a8ff)"
  flow-indigo: "#393cc1"
  flow-orange: "#d5650f"
  flow-gold: "#eaaf1c"
  flow-periwinkle: "#bed2ff"
  apple-green: "#34c759"
  apple-red: "#ff3b30"
  apple-orange: "#ff9500"
  apple-gray: "#8e8e93"
  flame: "#ff6b00"
  neutral-0: "#ffffff"
  neutral-950: "#0d0c0b"
typography:
  display:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"SF Pro Display\", \"Helvetica Neue\", \"Segoe UI\", Roboto, sans-serif"
    fontSize: "1.875rem"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.022em"
  title:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"SF Pro Display\", \"Helvetica Neue\", \"Segoe UI\", Roboto, sans-serif"
    fontSize: "1.375rem"
    fontWeight: 600
    lineHeight: 1.27
    letterSpacing: "-0.014em"
  headline:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"SF Pro Display\", \"Helvetica Neue\", \"Segoe UI\", Roboto, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 600
    lineHeight: 1.29
    letterSpacing: "-0.011em"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"SF Pro Display\", \"Helvetica Neue\", \"Segoe UI\", Roboto, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.375
    letterSpacing: "0"
  callout:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"SF Pro Display\", \"Helvetica Neue\", \"Segoe UI\", Roboto, sans-serif"
    fontSize: "0.9375rem"
    fontWeight: 400
    lineHeight: 1.33
  subhead:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"SF Pro Display\", \"Helvetica Neue\", \"Segoe UI\", Roboto, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 500
    lineHeight: 1.36
  footnote:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"SF Pro Display\", \"Helvetica Neue\", \"Segoe UI\", Roboto, sans-serif"
    fontSize: "0.8125rem"
    fontWeight: 500
    lineHeight: 1.31
  caption:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"SF Pro Display\", \"Helvetica Neue\", \"Segoe UI\", Roboto, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 400
    lineHeight: 1.33
  micro:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"SF Pro Display\", \"Helvetica Neue\", \"Segoe UI\", Roboto, sans-serif"
    fontSize: "0.6875rem"
    fontWeight: 600
    lineHeight: 1.27
    letterSpacing: "0.04em"
  mono:
    fontFamily: "ui-monospace, Menlo, \"Cascadia Mono\", Consolas, monospace"
    fontSize: "0.6875rem"
    fontWeight: 400
    lineHeight: 1.6
rounded:
  xs: "4px"
  sm: "6px"
  md: "8px"
  lg: "12px"
  xl: "16px"
  2xl: "20px"
  capsule: "999px"
spacing:
  0: "0px"
  1: "4px"
  2: "8px"
  3: "12px"
  4: "16px"
  5: "20px"
  6: "24px"
  8: "32px"
  10: "40px"
  12: "48px"
  16: "64px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "#ffffff"
    rounded: "{rounded.md}"
    padding: "0 13px"
    height: "32px"
  button-secondary:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "0 13px"
    height: "32px"
  button-danger:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.apple-red}"
    rounded: "{rounded.md}"
    padding: "0 13px"
    height: "32px"
  chip:
    backgroundColor: "{colors.fill-1}"
    textColor: "{colors.text-secondary}"
    rounded: "{rounded.capsule}"
    padding: "0 10px"
    height: "28px"
  input:
    backgroundColor: "{colors.surface-sunken}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "0 10px"
    height: "34px"
  badge:
    backgroundColor: "{colors.fill-1}"
    textColor: "{colors.text-secondary}"
    rounded: "{rounded.capsule}"
    padding: "2px 8px"
  composer:
    backgroundColor: "{colors.fill-2}"
    textColor: "{colors.text-primary}"
    rounded: "28px"
    padding: "8px"
    height: "56px"
  card:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.xl}"
    padding: "16px"
---

# Design System: Lively

## Overview

**Creative North Star: "The Lab Notebook"**

Lively is a local-first AI workspace built for one person doing focused work. Its visual system combines Apple HIG's semantic color roles and material layers, Sarvam AI's blue-to-orange flow spectrum, and Mistral AI's warm paper canvas and pixel motifs into a single coherent language. The result is precise, warm, and tool-like — a notebook that thinks, not a showroom.

The interface is calm and dense without being cluttered. Surfaces are flat at rest, separated by hairline borders and tonal shifts rather than shadows. Motion is purposeful and fast (90–520ms), using deceleration curves that feel machined, not playful. The primary accent (System Blue) is functional — it means "interactive" and nothing more. The flow spectrum (indigo to orange) is reserved for flow states only: streaming, progress, and generation. It never appears as a surface fill.

**Key Characteristics:**
- Warm-leaning neutral ramp (Mistral paper register) with Apple HIG semantic roles
- System Blue as the sole functional accent; Sarvam spectrum as a rare signal
- Tonal layering for depth — surfaces shift, shadows are ambient and state-driven
- Fixed radii taxonomy (4/6/8/12/16/20px + capsule) — no arbitrary corners
- 4px spacing grid with named stops (s-1 through s-16)
- Rem-based type scale from 0.6875rem to 1.875rem, system font stack
- Two themes via `light-dark()` — no duplicate palette
- Motion tokens with named durations and easings; reduced-motion respected
- Pixel motif and architectural grid as subtle texture overlays

## Colors

The palette is warm-neutral at its base, with a single functional accent and a reserved spectrum for flow states.

### Primary
- **System Blue** (light-dark(#007aff, #0a84ff)): The sole functional accent. Means "interactive" — links, primary buttons, focus rings, active states. Never decorative.

### Secondary (Flow Spectrum)
- **Sarvam Indigo** (#393cc1): The cool anchor of the flow spectrum. Used in flow-state gradients and the aurora background.
- **Sarvam Periwinkle** (#bed2ff): Light stop of the flow spectrum. Accent highlights in flow states.
- **Sarvam Gold** (#eaaf1c): Mid-spectrum. Warning-adjacent flow emphasis.
- **Sarvam Orange** (#d5650f): The warm terminus of the flow spectrum. Generation, streaming, progress.

### Tertiary (System Tints)
- **Apple Green** (#34c759): Success states, connected badges, completed indicators.
- **Apple Red** (#ff3b30): Error states, danger actions, failed badges.
- **Apple Orange** (#ff9500): Warning states, needs-key badges, partial results.
- **Apple Gray** (#8e8e93): Neutral/inactive states, disabled badges.
- **Flame** (#ff6b00): Mistral heritage accent. Used sparingly for emphasis.

### Neutral
- **Neutral 0** (#ffffff): Light canvas and surface base.
- **Neutral 25** (#fbfaf8): Warm paper — sunken surfaces in light theme.
- **Neutral 100** (#eceae7): Muted surfaces, fills.
- **Neutral 200** (#dedbd6): Borders, dividers.
- **Neutral 500** (#77726b): Tertiary text.
- **Neutral 600** (#565149): Secondary text in dark theme.
- **Neutral 800** (#262320): Primary text in light theme.
- **Neutral 900** (#171614): Deep text.
- **Neutral 950** (#0d0c0b): Dark canvas.

### Named Rules
**The One Voice Rule.** System Blue is used on ≤10% of any given screen. Its rarity is the point — if everything is blue, nothing signals interactivity.

**The Flow Reserve Rule.** The Sarvam spectrum (indigo→periwinkle→gold→orange) appears only in flow states: streaming, progress, generation. It is never a surface fill, never a button, never a badge.

**The Warm Paper Rule.** Neutrals lean warm (Mistral register), not cool gray. Even dark mode uses warm-leaning blacks (#0d0c0b, #171614), not pure #000.

## Typography

**Display Font:** System sans stack (-apple-system, BlinkMacSystemFont, SF Pro Text, SF Pro Display, Helvetica Neue, Segoe UI, Roboto, sans-serif)
**Body Font:** Same system stack (no secondary family — one voice)
**Label/Mono Font:** ui-monospace, Menlo, Cascadia Mono, Consolas, monospace

**Character:** The type is invisible by design. System fonts render natively on every platform, load instantly, and feel like the OS. No custom web fonts, no FOUT. Hierarchy comes from size and weight contrast within a single family, not from font pairing.

### Hierarchy
- **Display** (700, 1.875rem, 1.2): Page titles, hero headings. Used sparingly.
- **Title** (600, 1.375rem, 1.27): Section headers, overlay titles.
- **Headline** (600, 1.0625rem, 1.29): Card titles, feature headings.
- **Body** (400, 1rem, 1.375): Primary reading text. Max line length 65–75ch.
- **Callout** (400, 0.9375rem, 1.33): Emphasized body, intro paragraphs.
- **Subhead** (500, 0.875rem, 1.36): Section labels, group headers.
- **Footnote** (500, 0.8125rem, 1.31): Secondary metadata, button labels.
- **Caption** (400, 0.75rem, 1.33): Timestamps, help text.
- **Micro** (600, 0.6875rem, 1.27, 0.04em tracking): Badges, status labels, uppercase utility text.
- **Mono** (400, 0.6875rem, 1.6): Code, terminal output, tool names, API keys.

### Named Rules
**The One Family Rule.** One sans-serif family for everything. Hierarchy comes from size and weight, not font pairing. Mono is the only exception, reserved for code and technical identifiers.

**The Rem Scale Rule.** All font sizes use rem units so text respects user browser settings. Line heights are unitless ratios.

## Layout

The layout is a two-column shell: a 244px sidebar (collapsible) and a main content area. The main area centers content at a 720px max-width column. Popovers and panes float above.

**Spacing rhythm:** 4px base grid with named stops (s-1: 4px through s-16: 64px). Components use s-2 (8px), s-3 (12px), s-4 (16px) for internal padding; s-5 (20px) and s-6 (24px) for section gaps.

**Responsive breakpoints:** 1080px (pane narrows), 860px (sidebar becomes overlay, research overlay goes full-screen), 560px (compact header, demo badge hidden), 320px (minimum supported). Touch targets expand to 44px at coarse pointers.

**Density:** Comfortable but not spacious. The app is a tool — information density is preferred over marketing whitespace. Conversation messages are 26px apart; settings rows are 12px apart.

## Elevation & Depth

Tonal layering, not shadows. Depth is conveyed through surface color shifts (canvas → surface → raised → sunken → muted) and hairline borders (0.5px–1px). Shadows appear only as ambient response to state: hover, focus, elevation, or floating surfaces.

**Shadow Vocabulary:**
- **Ambient low** (`0 1px 2px rgba(0,0,0,.05), 0 1px 1px rgba(0,0,0,.03)`): Resting elevation for cards and popovers.
- **Ambient mid** (`0 2px 8px rgba(0,0,0,.07), 0 1px 2px rgba(0,0,0,.04)`): Hovered surfaces.
- **Ambient high** (`0 12px 34px rgba(0,0,0,.16), 0 2px 8px rgba(0,0,0,.07)`): Floating surfaces (popovers, overlays).
- **Ambient max** (`0 24px 64px rgba(0,0,0,.22), 0 6px 16px rgba(0,0,0,.09)`): Modals and dialogs.

**Named Rules**
**The Flat-By-Default Rule.** Surfaces are flat at rest. Shadows appear only as a response to state (hover, elevation, focus). No decorative drop shadows.

**The Specular Rim Rule.** Translucent surfaces (sidebar, glass) get a 1px gradient border built with a mask — a true light-source rim, not four flat lines. The light source is top-left, falloff through edge-on, refraction into shadow at bottom-right.

## Shapes

The form language is HIG-inspired: fixed radii for small controls, capsules for pills, concentric radii for nested elements.

**Radius taxonomy:**
- 4px (xs): small badges, chips, inline code
- 6px (sm): small buttons, icon buttons
- 8px (md): buttons, inputs, cards
- 12px (lg): panels, popovers
- 16px (xl): dialogs, overlays
- 20px (2xl): large surfaces
- 999px (capsule): pills, tags, status badges

**Borders:** 0.5px hairlines for subtle separation, 1px for standard borders, 2px for focus/active emphasis. Borders use `--separator` (translucent) not solid colors.

**Corners:** Concentric — child radius = parent radius − padding. The composer capsule (28px) contains chips (20px) because 28 − 8 = 20.

## Components

### Buttons
- **Shape:** 8px radius, 32px height, 0 13px padding.
- **Primary:** System Blue fill, white text, transparent border. Hover darkens to accent-hover.
- **Secondary:** Surface fill, primary text, 1px separator border. Hover fills with fill-1.
- **Danger:** Surface fill, red text, red-tinted border. Hover fills with 10% red.
- **States:** hover (fill shift), active (scale 0.96), focus (2px accent outline), disabled (reduced opacity).

### Chips
- **Shape:** Capsule (999px), 28px height, 0 10px padding.
- **Style:** fill-1 background, secondary text, 1px separator border.
- **States:** hover (fill-2), selected (accent fill, white text).

### Cards / Containers
- **Corner:** 8–16px radius depending on size.
- **Background:** surface-raised (light) / #1c1c1e (dark).
- **Shadow:** Ambient low at rest, ambient mid on hover.
- **Border:** 1px separator, or specular rim for glass surfaces.
- **Padding:** 16px standard, 12px compact.

### Inputs / Fields
- **Style:** 8px radius, 34px height, 0 10px padding. Sunken background, 1px separator border. Mono font for keys/secrets.
- **Focus:** Accent border + 3.5px accent-muted glow ring.
- **Error:** Red border, red text below (role="alert").
- **Disabled:** Reduced opacity, no interaction.

### Badges
- **Shape:** Capsule, 2px 8px padding.
- **Tones:** ok (green), warn (orange), bad (red), neutral (gray). Small-caps micro text.
- **States:** static labels, not interactive.

### Navigation
- **Sidebar:** 244px wide, glass background with specular rim. Collapses to overlay at ≤860px. Conversation list with hover-revealed actions.
- **Settings nav:** Vertical list, 44px touch targets on coarse pointers, aria-current for active section.

### Research Overlay
- **Shape:** Full surface, absolute inset 0, z-index 30 (60 on mobile). Flex column: header (title + badge + close) + scrollable body.
- **Body:** Max-width 720px centered. Stages, callouts, sources, report, partial summaries.
- **States:** Connecting (badge), Running (badge + stages), Complete/Partial (green badge), Failed (red badge + error callout), Demo (neutral badge + simulated callout).

### Composer
- **Shape:** 28px radius capsule, 56px min height. Fill-2 background, focus shifts to fill-3.
- **Children:** Chips (20px radius, concentric), send button (34px circle, accent fill), voice button, model chip.
- **Shadow:** Composer shadow (1px + 6px) for the refracting bottom edge.

## Do's and Don'ts

### Do:
- **Do** use System Blue only for interactive elements. Its rarity is the signal.
- **Do** use the flow spectrum (indigo→orange) only for flow states: streaming, progress, generation.
- **Do** keep surfaces flat at rest. Shadows are state-driven, never decorative.
- **Do** use `light-dark()` for all theme-aware colors. Never duplicate the palette.
- **Do** use the system font stack. No custom web fonts, no FOUT.
- **Do** use rem for font sizes so text respects user preferences.
- **Do** use the 4px spacing grid. No arbitrary values.
- **Do** use concentric radii (child = parent − padding).
- **Do** label demo/simulated data visibly. Never let it masquerade as real.
- **Do** surface errors with `role="alert"` and actionable messages.
- **Do** respect `prefers-reduced-motion` (global kill is the accepted pattern here).

### Don't:
- **Don't** use System Blue decoratively. If it's not interactive, it's not blue.
- **Don't** use the flow spectrum as a surface fill, button, or badge.
- **Don't** add decorative drop shadows. Flat at rest, always.
- **Don't** introduce a second font family. One sans + mono, that's it.
- **Don't** use arbitrary spacing values. Stick to the named stops.
- **Don't** use pure black (#000) or pure white (#fff) for large surfaces — use the neutral ramp.
- **Don't** put gray text on colored backgrounds — use a shade of that color or transparency.
- **Don't** use bounce or elastic easing. Deceleration only.
- **Don't** animate layout properties (width, height, top, left) — use transform/opacity.
- **Don't** use gradient text. It's an AI slop tell.
- **Don't** use glassmorphism as a default. It's reserved for the sidebar and specific surfaces.
- **Don't** hide errors or loading states. Surface them visibly.
- **Don't** use generic placeholder copy. Be specific and helpful.