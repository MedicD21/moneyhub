---
name: Money Hub
description: Personal paycheck-based budget viewer; database-computed numbers, shown plainly.
colors:
  deep-pine: "#1f6f54"
  deep-pine-ink: "#ffffff"
  deep-pine-soft: "#e3f1ec"
  deep-pine-dark: "#5fc3a0"
  deep-pine-ink-dark: "#0b1f18"
  deep-pine-soft-dark: "#173229"
  ledger-paper: "#f7f7f5"
  ledger-sheet: "#ffffff"
  ledger-tint: "#f0efec"
  ledger-rule: "#e1e0d9"
  ink: "#161615"
  ink-muted: "#5c5b57"
  ink-subtle: "#7a7973"
  dusk-paper: "#121211"
  dusk-sheet: "#1b1b1a"
  dusk-tint: "#252523"
  dusk-rule: "#33332f"
  dusk-ink: "#f0efec"
  dusk-ink-muted: "#b9b8ae"
  dusk-ink-subtle: "#9a998f"
  money-in: "#006300"
  money-in-dark: "#4cc24c"
  ok-wash: "#e7f4e7"
  ok-rule: "#9fd19f"
  caution: "#8a5300"
  caution-wash: "#fdf3dc"
  caution-rule: "#f0c46b"
  overdue: "#b42318"
  overdue-wash: "#fdecea"
  overdue-rule: "#f1a7a0"
  overdue-dark: "#f28b82"
typography:
  display:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "2.25rem"
    fontWeight: 600
    lineHeight: 1.1
    fontFeature: "tnum"
  headline:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 600
    lineHeight: 1.33
    letterSpacing: "-0.025em"
  stat:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "1.875rem"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.025em"
    fontFeature: "tnum"
  title:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 600
    lineHeight: 1.43
  body:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 400
    lineHeight: 1.43
  label:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 500
    lineHeight: 1.33
  micro:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "11px"
    fontWeight: 500
    lineHeight: 1rem
rounded:
  md: "8px"
  lg: "12px"
  xl: "16px"
  full: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
components:
  button-primary:
    backgroundColor: "{colors.deep-pine}"
    textColor: "{colors.deep-pine-ink}"
    typography: "{typography.title}"
    rounded: "{rounded.md}"
    padding: "0 12px"
    height: "40px"
  button-secondary:
    backgroundColor: "{colors.ledger-sheet}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "0 12px"
    height: "40px"
  button-secondary-hover:
    backgroundColor: "{colors.ledger-tint}"
  button-ghost:
    textColor: "{colors.ink-muted}"
    rounded: "{rounded.md}"
    padding: "0 12px"
    height: "40px"
  button-ghost-hover:
    backgroundColor: "{colors.ledger-tint}"
    textColor: "{colors.ink}"
  input:
    backgroundColor: "{colors.ledger-sheet}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "0 12px"
    height: "44px"
  card:
    backgroundColor: "{colors.ledger-sheet}"
    rounded: "{rounded.xl}"
    padding: "16px"
  badge-ok:
    backgroundColor: "{colors.ok-wash}"
    textColor: "{colors.money-in}"
    typography: "{typography.micro}"
    rounded: "{rounded.full}"
    padding: "2px 8px"
  badge-warn:
    backgroundColor: "{colors.caution-wash}"
    textColor: "{colors.caution}"
    typography: "{typography.micro}"
    rounded: "{rounded.full}"
    padding: "2px 8px"
  badge-danger:
    backgroundColor: "{colors.overdue-wash}"
    textColor: "{colors.overdue}"
    typography: "{typography.micro}"
    rounded: "{rounded.full}"
    padding: "2px 8px"
  nav-item-active:
    backgroundColor: "{colors.deep-pine-soft}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    height: "40px"
  fab-add:
    backgroundColor: "{colors.deep-pine}"
    textColor: "{colors.deep-pine-ink}"
    rounded: "{rounded.full}"
    size: "56px"
---

# Design System: Money Hub

## Overview

**Creative North Star: "The Ledger at Dusk"**

Money Hub is a bookkeeper's ledger read under a lamp. Warm paper in daylight, warm near-black at night, and figures that sit still on the page. The interface does no persuading: it lays out what the database computed, in a fixed order, so the eye goes to the number and then to what's due next.

Components are crisp and utilitarian. Hairline rules separate things, one deep pine accent marks the single thing you can act on, and status color (in, caution, overdue) is the only other color allowed to speak. Density is moderate: phone-first stacks of cards, small labels over large tabular figures, and 40px minimum touch targets. Dusk (dark mode) is a peer of daylight, not an inversion: every token has a tuned dark value.

**Key Characteristics:**
- Warm neutral paper and ink in both themes, never pure white-on-black or blue-gray.
- One accent, Deep Pine, for primary actions, the active nav item and focus rings.
- Tabular figures everywhere money appears.
- Flat surfaces; a near-invisible shadow on cards, real shadow only on things that float.
- System font stack; hierarchy comes from size and weight, not typeface.

## Colors

A warm-neutral ledger palette with one evergreen accent and three status signals. Every role has a light (Ledger) and dark (Dusk) value, switched by `prefers-color-scheme` through CSS custom properties in `web/src/index.css`.

### Primary
- **Deep Pine** (light `deep-pine`, dark `deep-pine-dark`): primary buttons, the + add button, the active bottom-tab label, accent card borders and every focus ring. Text on it uses `deep-pine-ink` / `deep-pine-ink-dark`.
- **Pine Wash** (`deep-pine-soft` / `deep-pine-soft-dark`): the active sidebar item and accent badges. A selected state, never a decorative fill.

### Neutral
- **Ledger Paper / Dusk Paper** (`ledger-paper` / `dusk-paper`): page background.
- **Ledger Sheet / Dusk Sheet** (`ledger-sheet` / `dusk-sheet`): cards, sheets, inputs, sidebar and bars.
- **Ledger Tint / Dusk Tint** (`ledger-tint` / `dusk-tint`): hover fills, segmented-control tracks, the amount field well, neutral badges.
- **Ledger Rule / Dusk Rule** (`ledger-rule` / `dusk-rule`): every border and divider; also the chart grid.
- **Ink / Dusk Ink** (`ink` / `dusk-ink`): headings, values, primary text.
- **Muted Ink** (`ink-muted` / `dusk-ink-muted`): labels, descriptions, inactive nav, axis ticks.
- **Subtle Ink** (`ink-subtle` / `dusk-ink-subtle`): placeholders and chart overflow series only.

### Status
- **Money In** (`money-in` / `money-in-dark`): positive amounts (with a leading +) and "ok" badges. Money out stays neutral ink.
- **Caution** (`caution`, with `caution-wash` and `caution-rule`): warning banners and badges, such as due-soon bills.
- **Overdue** (`overdue` / `overdue-dark`, with `overdue-wash` and `overdue-rule`): danger banners, badges, danger-toned stats and card borders.

### Charts
Charts use a separate eight-step categorical palette (`--series-1` to `--series-8`, light and dark steps) plus `--income` and `--spending`, defined in `web/src/index.css` and applied through `web/src/components/chartTheme.ts`. Order is fixed; past eight series fall back to Subtle Ink. These colors live only inside charts.

### Named Rules
**The Neutral Spend Rule.** Money out is never red. Red means overdue or an error, not "you spent money". Only money in gets color.

**The One Pine Rule.** Deep Pine marks what you can act on or where you are. It is never a background for content or a decorative stripe.

**The Dusk Parity Rule.** No color ships without its dark value. Add new colors as CSS custom properties with both steps, never as raw hex in a component.

## Typography

**Display Font:** system-ui (with -apple-system, Segoe UI, Roboto, Helvetica Neue, Arial)
**Body Font:** same stack
**Label/Mono Font:** none; numbers use `tabular-nums` on the same stack

**Character:** The platform's own face, so the app reads like a native tool on the phone. Weight 600 and tight tracking carry headings; everything else is 400–500.

### Hierarchy
- **Display** (600, 2.25rem, 1.1, tabular): the amount being typed in the add/edit sheet.
- **Stat** (600, 1.875rem emphasized / 1.25rem normal, tight tracking, tabular): headline figures such as safe-to-spend and balances.
- **Headline** (600, 1.5rem, tight tracking): page titles, one per page.
- **Title** (600, 0.875rem): card and sheet headings.
- **Body** (400, 0.875rem): rows, descriptions, buttons (500).
- **Label** (500, 0.75rem, muted): stat labels, field labels, card subtitles.
- **Micro** (500, 11px; 10.5px in the bottom tab bar): badges and tab labels only.

### Named Rules
**The Tabular Rule.** Every money value renders with tabular figures, so columns of amounts align digit for digit.

**The 16px Input Rule.** Inputs are 1rem on phones (0.875rem from `sm` up) so iOS Safari never zooms on focus.

## Layout

Phone first. Below `md` (768px): a sticky top bar with the brand, a fixed six-tab bottom bar (56px tall, safe-area padded), and a floating 56px + button above it. Both bars hide while the on-screen keyboard is open. From `md` up: a fixed 240px sidebar with full labels, and the + button moves to the bottom-right corner.

Content sits in a centered column (max 72rem) with 16px side padding on phones, 24px from `sm`, 40px from `lg`. Page rhythm runs on a 4px base: 8–12px gaps inside cards and rows, 16px between stacked cards, 20px card padding from `sm` up (16px on phones). Definition-list rows (label left, value right, 6px vertical padding) are the default way to show a set of figures.

## Elevation & Depth

Flat, with tonal layering. Depth comes from paper → sheet → tint steps and hairline rules, not shadow. Cards carry a barely-there 1px shadow to lift them off the paper. Real shadow is reserved for things that float above content.

### Shadow Vocabulary
- **Sheet rest** (`box-shadow: 0 1px 2px rgba(0,0,0,0.04)`): cards and collapsible cards.
- **Float** (Tailwind `shadow-lg`): the + add button.
- **Overlay** (Tailwind `shadow-xl`): the add/edit transaction sheet, over a 50% black scrim.

### Named Rules
**The Only-Floaters-Cast Rule.** Only elements that float over content (the + button, the sheet) get a visible shadow. Nothing in the page flow does. The one exception is HUD instrumentation (charts and meters, see Components), which carries its own bevel and lit glow.

## Shapes

Rounded but not soft. Controls (buttons, inputs, nav items) use 8px corners; banners and segmented controls 12px; cards and the bottom sheet 16px (top corners only on phones). Badges and the + button are fully round. Every container gets a 1px rule border; focus is a 2px Deep Pine outline offset 2px (1px on inputs).

## Components

### Buttons
Crisp and utilitarian: fixed 40px height, 12px horizontal padding, medium weight, color-only transitions.
- **Shape:** gently rounded (8px).
- **Primary:** Deep Pine fill, white (dark: deep-green) text. Hover drops opacity to 90%.
- **Secondary:** sheet fill, 1px rule border, ink text; hover fills with tint.
- **Ghost:** no fill, muted text; hover fills with tint and darkens to ink.
- **Focus / Disabled:** 2px Deep Pine outline offset 2px; disabled at 50% opacity with a not-allowed cursor.

### Badges
- **Style:** fully round pill, 1px border, 11px medium text, 2px × 8px padding, no wrap.
- **Tones:** neutral and muted (tint fill), ok (green wash), warn (caution wash), danger (overdue wash), accent (pine wash with pine border). The border always matches the tone's rule color.

### Cards / Containers
- **Corner Style:** 16px.
- **Background:** sheet.
- **Shadow Strategy:** sheet rest only (see Elevation).
- **Border:** 1px rule; overdue rule for danger tone; Deep Pine for accent tone.
- **Internal Padding:** 16px, 20px from `sm`.
- **Collapsible variant:** a native `<details>` with a 48px summary row, rotating chevron, optional right-aligned tabular count; body renders only while open.

### Inputs / Fields
- **Style:** sheet fill, 1px rule, 8px corners, 44px tall on phones (40px from `sm`), 12px padding.
- **Label:** 12px medium muted text stacked above.
- **Focus:** 2px Deep Pine outline offset 1px.
- **Money input:** `inputMode="decimal"`, centered display-size tabular figure in a tint well with a sign glyph (green for income, muted for spending).

### Navigation
- **Sidebar (desktop):** 240px sheet panel, 40px items with 18px icon and label; active item gets Pine Wash and ink text; inactive is muted with tint hover.
- **Bottom tabs (phone):** six equal columns, 20px icon over a 10.5px label; active turns Deep Pine, inactive muted. Envelopes is desktop-only in the bar and reached from the Dashboard on phones.

### Banner
Full-width alert row: 12px corners, tone wash fill with matching rule and text color, 18px icon, bold title over body text. Info tone uses tint and ink.

### HUD Instrumentation (charts and meters, signature)
Charts and meters are the one place the ledger turns into an instrument: ceramic plates with lit seams, in the spirit of white armor with glowing joints. Everything still comes from the existing tokens; no new hues.
- **Plate** (`ChartFrame` in `components/charts.tsx`, `.hud-plate` in `index.css`): 14px corners, a top-lit gradient (`--plate-hi` → `--plate-lo`), an inset bevel highlight, a soft cast shadow, a 1px Deep Pine seam along the top edge, and 10px pine corner brackets. Optional caption row turns it into a `<figure>`.
- **Series** (`components/hudDefs.tsx`): columns are lit from the left and horizontal bars from the top (highlight band, true hue, shaded edge), giving a turned, solid volume. Lines and area strokes get a soft offset glow in their own color (`--glow-mix`, stronger in Dusk). Areas fade from 32% to 0.
- **Grid and axes:** dotted grid (`2 5`), tabular axis numerals.
- **Hover:** a dashed pine cursor and an active point with a pulsing ring.
- **Readout** (`MoneyTooltip`, `.hud-readout`): plate gradient, pine top seam, a ruled label row, tabular values.
- **Meter** (`Meter` in `ui.tsx`): inset track, top-lit fill in accent / pos / warn / danger with a faint glow.
- **Motion (one moment on arrival):** series draw in over 900ms ease-out, staggered; a single light sweep crosses each plate; meters grow from the left and catch one glint. All of it is off under reduced motion (Recharts animation disabled, pulse hidden).

### Add Transaction Sheet (signature)
A bottom sheet on phones, centered dialog from `md`. Income/spending segmented control on a tint track, a large centered amount well, quick date chips, then plain fields. The + button that opens it is the only always-visible Deep Pine element.

## Do's and Don'ts

### Do:
- **Do** take every color from a CSS custom property with light and dark values (`web/src/index.css`).
- **Do** render money through the shared `Money` / `Stat` / `Row` components so tabular figures and sign color stay consistent.
- **Do** keep touch targets at least 40px (44px for phone inputs, 56px for tabs and the + button).
- **Do** use the status tones only for status: ok, caution, overdue.
- **Do** reuse `web/src/components/ui.tsx` primitives before adding new ones.

### Don't:
- **Don't** color money out red or orange; red is for overdue and errors.
- **Don't** add a second accent color or use Deep Pine as a decorative fill.
- **Don't** add shadows to in-flow elements beyond the card's sheet-rest shadow (HUD instrumentation excepted).
- **Don't** spread the HUD treatment (plates, glow, brackets, sweep) beyond charts and meters.
- **Don't** introduce a webfont or a separate numeric font; the system stack with tabular figures is the type system.
- **Don't** use chart series colors outside charts.
