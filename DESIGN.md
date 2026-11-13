---
name: Money Hub
description: A night instrument cluster of smoked glass with lit pine seams, over database-computed money figures. Dark only.
colors:
  ground: "#03080a"
  ground-deep: "#010305"
  glass-fill: "rgba(15, 21, 20, 0.6)"
  glass-solid: "#0d1312"
  glass-wash: "rgba(255, 255, 255, 0.05)"
  edge: "rgba(255, 255, 255, 0.085)"
  edge-strong: "rgba(255, 255, 255, 0.15)"
  bevel: "rgba(255, 255, 255, 0.09)"
  ink: "#eef4f1"
  ink-muted: "#a5b2ad"
  ink-subtle: "#7d8a85"
  pine: "#5fc3a0"
  pine-bright: "#8be7c5"
  pine-deep: "#2f8a6b"
  pine-ink: "#03140d"
  pine-wash: "rgba(95, 195, 160, 0.14)"
  seam-light: "rgba(139, 231, 197, 0.75)"
  lamp-red: "#e34948"
  lamp-orange: "#e2652f"
  lamp-peach: "#e9a46c"
  lamp-mint: "#7cc7b4"
  lamp-pine: "#2f8a6b"
  lamp-blue: "#2c6fc0"
  money-in: "#1fb380"
  money-in-wash: "rgba(31, 179, 128, 0.12)"
  money-in-line: "rgba(31, 179, 128, 0.4)"
  caution: "#f5c15a"
  caution-wash: "rgba(245, 193, 90, 0.1)"
  caution-line: "rgba(245, 193, 90, 0.38)"
  alarm: "#f28b82"
  alarm-wash: "rgba(242, 139, 130, 0.1)"
  alarm-line: "rgba(242, 139, 130, 0.4)"
  spending-ember: "#e2652f"
  chart-grid: "rgba(255, 255, 255, 0.08)"
  chart-axis: "rgba(255, 255, 255, 0.18)"
  series-1: "#3987e5"
  series-2: "#d95926"
  series-3: "#199e70"
  series-4: "#c98500"
  series-5: "#d55181"
  series-6: "#008300"
  series-7: "#9085e9"
  series-8: "#e66767"
typography:
  display:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "2.25rem"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "-0.025em"
    fontFeature: "'tnum' 1, 'case' 1"
  headline:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "1.75rem"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.025em"
  title:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.025em"
  figure:
    fontFamily: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "1.25rem"
    fontWeight: 600
    lineHeight: 1.4
    fontFeature: "'tnum' 1, 'case' 1"
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
    lineHeight: 1.45
rounded:
  chip: "10px"
  control: "12px"
  plate: "14px"
  banner: "16px"
  panel: "20px"
  dock: "22px"
  rail: "24px"
  pill: "9999px"
spacing:
  gutter-phone: "16px"
  gutter-tablet: "24px"
  gutter-desktop: "40px"
  panel-pad: "16px"
  panel-pad-wide: "20px"
  grid-gap: "16px"
  control-pad-x: "14px"
components:
  button-primary:
    backgroundColor: "{colors.pine}"
    textColor: "{colors.pine-ink}"
    rounded: "{rounded.control}"
    padding: "0 14px"
    height: "40px"
    typography: "{typography.title}"
  button-secondary:
    backgroundColor: "{colors.glass-wash}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0 14px"
    height: "40px"
  button-ghost:
    textColor: "{colors.ink-muted}"
    rounded: "{rounded.control}"
    padding: "0 14px"
    height: "40px"
  button-add-orb:
    backgroundColor: "{colors.pine}"
    textColor: "{colors.pine-ink}"
    rounded: "{rounded.pill}"
    size: "56px"
  panel-glass:
    backgroundColor: "{colors.glass-fill}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
    padding: "16px"
  input-well:
    backgroundColor: "rgba(0, 0, 0, 0.32)"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0 12px"
    height: "44px"
  chip-icon:
    backgroundColor: "{colors.pine-wash}"
    textColor: "{colors.pine-bright}"
    rounded: "{rounded.chip}"
    size: "32px"
  badge-ok:
    backgroundColor: "{colors.money-in-wash}"
    textColor: "{colors.money-in}"
    rounded: "{rounded.pill}"
    padding: "2px 8px"
    typography: "{typography.micro}"
  badge-caution:
    backgroundColor: "{colors.caution-wash}"
    textColor: "{colors.caution}"
    rounded: "{rounded.pill}"
    padding: "2px 8px"
    typography: "{typography.micro}"
  badge-alarm:
    backgroundColor: "{colors.alarm-wash}"
    textColor: "{colors.alarm}"
    rounded: "{rounded.pill}"
    padding: "2px 8px"
    typography: "{typography.micro}"
  badge-neutral:
    backgroundColor: "{colors.glass-wash}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "2px 8px"
    typography: "{typography.micro}"
  nav-item:
    textColor: "{colors.ink-muted}"
    rounded: "{rounded.control}"
    padding: "0 12px"
    height: "44px"
  nav-item-active:
    backgroundColor: "{colors.pine-wash}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0 12px"
    height: "44px"
  chart-plate:
    rounded: "{rounded.plate}"
    padding: "12px 6px 4px"
  meter-track:
    backgroundColor: "rgba(0, 0, 0, 0.4)"
    rounded: "{rounded.pill}"
    height: "6px"
---

# Design System: Money Hub

## Overview

**Creative North Star: "The Night Instrument Cluster"**

Money Hub is a dashboard you read in the dark: smoked glass panels floating over a near-black navy-teal ground and a band of out-of-focus lamps that runs warm to cold (red, orange, peach, mint, pine, blue), with one thin vertical line of pine light. Pine is the interface light: it travels each panel's seam, lights the active nav item, glides under the dock tab, and pools brightest behind the one number that matters on a screen: Safe-to-spend. Everything else sits one step dimmer.

The world is dense but quiet. Panels are frosted and beveled, edges are 1px white-alpha lines, and color is rationed: status hues (green, amber, coral) glow only where they carry meaning, and money out is never painted red. Figures are system sans with tabular digits, so columns of money align digit for digit and nothing pretends to be a display face. Motion is maximal (seams travel, halos turn, fields drift, panels rise into place), and all of it stops under Reduce Motion without hiding a single figure.

This replaces the earlier light/dark "Ledger at Dusk" system entirely. There is no light theme. The flat, light admin card grid is the explicit rejection.

**Key Characteristics:**
- Dark only; one material (smoked glass), one light source (pine).
- A single lit hero figure per screen: Safe-to-spend, in a reticle over a beacon.
- Green means money in. Red means overdue, shortfall or error. Spending is orange.
- System sans, tabular figures, tight tracking on headings.
- Maximal ambient and arrival motion, transform-only where it loops, fully off under Reduce Motion.
- HUD instrumentation for data: chart plates with corner brackets, lit gradients, readout tooltips, lit meters.

## Colors

A near-black pine-tinted ground, translucent glass over it, one pine light, and three status hues used sparingly.

### Primary
- **Pine Light** (pine): the accent and light source. Primary buttons, the add orb, icon chips by default, focus outlines, checkbox accent, meter fills, the page-title rule.
- **Seam Pine** (pine-bright): the brightest pine. Seams, the active nav dot and dock indicator, reticle ring, halo ring, focused field edge, caret. Used as light, rarely as a fill.
- **Deep Pine** (pine-deep): the shaded end of lit gradients (primary button, orb).
- **Pine Ink** (pine-ink): text and icons on lit pine surfaces.
- **Pine Wash** (pine-wash): tinted backgrounds for the accent badge and active nav.

### Secondary
- **Money-In Green** (money-in): the one green. Money in, positive amounts, income series in charts, the next paycheck figure, ok badges. Also exposed as `--income`.
- **Spending Ember** (spending-ember): the spending series in charts. Orange, never red.

### Tertiary
- **Caution Amber** (caution): stale data, review queues, needs-attention states.
- **Alarm Coral** (alarm): overdue bills, shortfall and overspent states, low balances, errors. Its wash and line tokens tint danger panels, badges and banners.
- **Lamp Matrix** (lamp-red → lamp-blue): the background only. Drawn on a canvas by `LampField` as an LED wall: every lamp on a 24px grid (18px on phones) shows as a dark socket, and lit lamps form one wide band (about 14 rows tall) whose centre sways gently and whose thickness breathes slowly, quantised to the grid. Colour runs warm to cold left to right; the ribbon's core burns hotter. Each lit lamp is a crisp lens with a bright core, coloured body, thin halo and small specular; only the far-left edge is slightly soft. A faint blurred bloom of the ramp sits behind. Capped at 30fps, paused when hidden, a single still frame under Reduce Motion. These colors never carry meaning and never appear on panels or data.
- **Cold Blue** (series-1): the far arc of the reticle and halo rings.

### Neutral
- **Night Ground** (ground → ground-deep): the page, painted only on `<html>` so the ambient layer shows through.
- **Smoked Glass** (glass-fill, glass-solid): panel fill at 60% over a 20px blur; the solid variant for the brand mark tile, native options, skip link.
- **Glass Wash** (glass-wash): hover rows, neutral badges, secondary buttons.
- **Edge / Edge Strong** (edge, edge-strong): 1px panel and control borders; strong on hover and on readouts.
- **Ink / Muted / Subtle** (ink, ink-muted, ink-subtle): figures and titles; labels and secondary copy; placeholders and quiet metadata.
- **Chart grid and axis** (chart-grid, chart-axis): dotted HUD grid (`2 5` dash) and axis lines.
- **Categorical series** (series-1 … series-8): validated palette, fixed order, never cycled; a ninth series falls back to ink-subtle.

### Named Rules
**The One Green Rule.** Money-In Green is the only green that carries meaning, and it means money in. Money out stays neutral ink. Red never marks an ordinary outflow; it is reserved for overdue, shortfall, overspent and error states, and a negative net position (owner confirmed).

**The Ember Series Rule.** Spending in charts is Spending Ember (orange), paired against Money-In Green income. A red spending series is wrong.

**The Status-When-Active Rule.** Icon chips are pine (or muted neutral) at rest and take caution or alarm hue only while that status is actually active (an overdue count above zero, items to review). A chip that is amber or coral with nothing wrong is lying.

**The Glow-Means-Meaning Rule.** Status hues glow (badge glow, tinted seams, danger beacon) only where they carry a state. Decoration glows pine.

## Typography

**Display Font:** system-ui (with -apple-system, Segoe UI, Roboto, Helvetica Neue, Arial, sans-serif)
**Body Font:** the same system stack
**Label/Mono Font:** none; figures use the system sans with tabular and case-sensitive features (`'tnum' 1, 'case' 1`).

**Character:** Plain, native and exact. The glass and light carry the atmosphere; the type stays out of the way so money reads instantly. A custom display face was considered and deliberately not adopted.

### Hierarchy
- **Display** (600, 2.25rem phone / 2.5rem sm / 3.25rem lg, 1.1, tight tracking): the hero figure only, lit with a soft text-glow of its own color. Safe-to-spend.
- **Headline** (600, 1.75rem / 2rem sm, 1.25, tight): page titles over the drawn rule; also the unlit secondary headline figure (net position).
- **Title** (600, 0.875rem, tight): panel titles and collapsible summaries.
- **Figure** (600, 1.25rem, tabular): ordinary stats in tiles.
- **Body** (400, 0.875rem): rows, descriptions, banner copy. Row values are tabular and right-aligned.
- **Label** (500, 0.75rem, muted): stat labels, field labels, subtitles, legends, chart ticks (11px).
- **Micro** (500, 11px; dock labels 10.5px): badges and dock tab names.

### Named Rules
**The Tabular Rule.** Every money figure and count uses tabular figures so digits align in columns and figures never jitter when values change.

**The No Count-Up Rule.** Figures arrive with a blur-and-tracking settle (`figure-in`), never with counting or interpolated values. The number on screen is always the database's number.

## Layout

Mobile first. On phones: a sticky glass top bar (brand + sign out), content with a 16px gutter, a floating glass dock pinned 10px above the safe-area bottom with six tabs, and the add orb floating above the dock at the right. Bottom padding on main clears dock and orb (11rem + safe area). Dock and orb hide while the on-screen keyboard is open so they never cover the field being typed in.

From `md` (768px): a floating glass rail, 240px wide, inset 12px on all sides, replaces bar and dock; content shifts right by 16.5rem and centers at max 72rem (6xl) with 24px (sm) and 40px (lg) gutters. The orb moves to 32px from the bottom-right corner.

Content is a stack of glass panels in 16px-gap grids; panels pad 16px (20px from sm). The dashboard pairs the Safe-to-spend panel with a stack of net position and four status tiles beside it. Panels stagger in (40ms steps, capped at 400ms). Touch targets are at least 40px (buttons 40px, nav items 44px, dock tabs 52px, inputs 44px on phones).

## Elevation & Depth

Depth is layered light and glass, not flat tone. Three planes: the ambient layer (navy-teal ground, the canvas LED wall with its swaying band and bloom, one vertical pine line at 22% from the left, an edge vignette, 6% grain), the glass panels floating over it, and overlays (sheets, readouts) above. Every glass panel combines a top bevel highlight, a bottom inner shade, and a soft long drop shadow, plus a 1px lit seam on its top edge. Accent and danger panels add a colored outer bloom.

### Shadow Vocabulary
- **Glass drop** (`box-shadow: inset 0 1px 0 rgba(255,255,255,0.09), inset 0 -1px 0 rgba(0,0,0,0.35), 0 24px 48px -28px rgba(0,0,0,0.9), 0 2px 6px -2px rgba(0,0,0,0.5)`): every glass panel, rail, bar and dock.
- **Accent bloom** (adds `0 0 0 1px rgba(95,195,160,0.06), 0 28px 60px -30px rgba(47,138,107,0.55)`): the hero panel.
- **Danger bloom** (adds `0 28px 60px -30px rgba(242,139,130,0.35)`): panels in an active danger state.
- **Lit button** (`inset 0 1px 0 rgba(255,255,255,0.55), inset 0 -1px 0 rgba(0,0,0,0.2), 0 8px 22px -10px rgba(95,195,160,0.8)`): primary buttons.
- **Well** (`inset 0 1px 2px rgba(0,0,0,0.5), inset 0 -1px 0 rgba(255,255,255,0.03)`): recessed inputs; meter tracks use `inset 0 1px 2px rgba(0,0,0,0.6)`.
- **Plate cast** (`0 1px 1px rgba(0,0,0,0.3), 0 14px 30px -16px rgba(0,0,0,0.8)`): chart plates, lighter than glass.

### Named Rules
**The One Lit Hero Rule.** Exactly one figure per screen is lit: Safe-to-spend on the Dashboard, framed by the reticle (ring of light plus four corner brackets) over a breathing beacon. Secondary headline figures are large but unlit.

**The Capped Blur Rule.** Backdrop blur never exceeds 20px (glass 20px, readout 14px, scrim 6px). Ambient motion is transform-only on a fixed layer. Both protect phone GPUs.

**The Dark Only Rule.** There is one theme. `color-scheme: dark`; no light tokens, no theme switch.

## Shapes

Soft, generous corners that grow with the object: chips 10px, controls and nav items 12px, chart plates 14px, banners 16px, panels 20px, the dock 22px, the rail 24px; badges, meters and the orb are full pills/circles. Borders are 1px white-alpha; colored borders appear only on toned panels, badges and focused fields. HUD corner brackets (10px, 1.5px pine, 4px rounded corner) frame chart plates and the hero reticle. Rings of light are conic gradients masked to a thin band (1.5px for halos, 1px for the reticle), never solid outlines.

## Components

### Buttons
Lit, tactile, and quiet everywhere except the one primary action.
- **Shape:** gently rounded (12px), min height 40px, 14px horizontal padding, 14px medium text.
- **Primary:** a lit pine gradient (pine-bright → pine → pine-deep) with Pine Ink text and a pine glow below. Hover brightens and passes a white sheen across; active presses 1px down.
- **Secondary:** glass (faint white gradient, 1px edge, top bevel). Hover turns the edge pine and adds a 3px pine wash ring.
- **Ghost:** muted text, glass wash on hover.
- **Focus:** 2px pine-bright outline, 2px offset. **Disabled:** 45% opacity.
- **Add orb:** a 56px pine sphere (radial light from the upper left) with a turning halo ring, breathing glow, and scale on hover/press. The one global action.

### Chips
- **Icon chip:** a 32px (40px large) lit tile, 10px radius, tinted from its tone with an inner edge, top highlight and a glow; the icon carries a matching drop-shadow. Default tone pine; muted for neutral subjects; caution/alarm only while that status is active.
- **Badges:** pill, 11px medium, tinted wash + line + text of their tone, with a faint glow of their own color (neutral and muted badges do not glow).

### Cards / Containers
- **Corner Style:** 20px.
- **Background:** smoked glass (72% fill so the lamps never compete with text, white highlight gradient, 20px blur, 150% saturate).
- **Shadow Strategy:** glass drop; accent or danger bloom only on toned panels (see Elevation).
- **Border:** 1px edge; pine at 32% for accent, alarm line for danger.
- **Seam:** a resting 1px pine line on the top edge with a faint pulse that travels it once every 120s, offset per panel, so it reads as a rare event. Danger and warn panels tint the seam.
- **Internal Padding:** 16px, 20px from sm. Title row: chip + title + muted subtitle, optional action on the right.
- **Collapsible variant:** native details/summary with a 48px summary, rotating chevron tile, and a pill count; content mounts only when open.

### Inputs / Fields
- **Style:** recessed wells: 32% black fill, 1px edge, inner shadow, 12px radius, 44px tall with 16px text on phones (prevents iOS zoom), 40px/14px from sm.
- **Focus:** edge turns pine-bright, fill deepens, 3px pine ring plus a soft pine glow; no default outline.
- **Error:** alarm text below the field with `role="alert"`.

### Navigation
- **Desktop rail:** floating glass column with the brand mark (halo-ringed tile) at top, 44px items in muted text with an 18px icon. Hover washes and nudges the icon right. Active item: pine-wash gradient, inner pine edge, glowing icon, and a pulsing pine dot at the right.
- **Phone dock:** floating glass bar of six tabs (20px icon over a 10.5px label). A pine-tinted indicator glides between tabs (0.55s ease-out) with a short glowing bar of light on its top edge; the active icon glows.

### Hero Figure (signature)
The Stat in emphasis + reticle form: label, then the display figure in a rounded instrument window: a 1px conic ring of pine light (with a cold-blue far arc) that turns every 6s, four corner brackets, and a faint pine fill, over a breathing beacon pool behind the panel. Danger tone swaps ring and beacon to coral.

### Chart Plates (signature)
Every chart sits on a HUD plate: ceramic gradient, 14px radius, a lit seam centered on the top edge, four corner brackets, and one diagonal sweep of light on arrival (1.3s, once). Bars use lit gradients (highlight band, true hue through the middle, shaded edge) so they read as turned solids without losing their hue; areas fade from 32% to 0; lines carry a soft glow. The active point is a solid dot with a pulsing ring. Tooltips are HUD readouts: dark glass at 14px blur with a pine-bright line on the top edge and tabular money lines. Legends sit above the chart in HTML. Series draw in over 900ms, staggered, and not at all under Reduce Motion.

### Meters
A recessed pill track (6px, 8px for md) with a lit fill in pine, money-in, caution or alarm, a glow of its own color, a grow-in on arrival and a periodic white glint. The meter only scales a percentage the view already computed.

### Banners
16px-radius tinted strips (alarm, caution, or neutral glass for info) with a glowing icon tile, a bold title and body copy; alert role for danger and caution, status for info.

## Do's and Don'ts

### Do:
- **Do** keep every color on a `:root` token in `web/src/index.css`; components never use raw hex.
- **Do** make Safe-to-spend the only lit figure on a screen: emphasis plus reticle plus the panel beacon. Other headline figures use the large, unlit size.
- **Do** color money in with Money-In Green (#1fb380) and leave money out in neutral ink; chart spending in Spending Ember (#e2652f).
- **Do** keep icon chips pine or muted at rest and switch them to caution or alarm only while that status is active.
- **Do** put every chart on a HUD plate with brackets, the lit gradients from the HUD defs, a readout tooltip, and the dotted `2 5` grid.
- **Do** use tabular figures for every money value and count.
- **Do** give every looping or arrival animation a reduced-motion path: loops removed, entrances skipped, decorative moving layers hidden. Arrival animations start from a near-visible state so content never depends on an animation finishing.
- **Do** keep backdrop blur at 20px or less and ambient motion transform-only.
- **Do** keep touch targets at 40px or more and money inputs on `inputMode="decimal"` at 16px on phones.

### Don't:
- **Don't** add a light theme or light surfaces; the system is dark only.
- **Don't** paint money out red. Red is for overdue, shortfall, overspent, error states and a negative net position only.
- **Don't** light a second hero figure or put a reticle or beacon on more than one panel per screen.
- **Don't** count up, tween or interpolate money values; no money arithmetic in the browser.
- **Don't** introduce a custom display or web font; the system sans is a deliberate choice.
- **Don't** make the seam pulse frequent: each panel's seam pulses once every 120s, offset per panel, so a pulse is a rare event. Meter glints run on a 40s cycle.
- **Don't** run a full-screen sweeping scan or radar line across the background. The chart plate's single arrival sweep and the skeleton scan are the only sweeps.
- **Don't** animate the ambient layer or any full-screen layer with anything but transform and opacity; never animate layout properties (top, left, width, height) in a loop.
- **Don't** let status hues glow decoratively; amber and coral appear only with an active state.
- **Don't** return to the flat, light admin card grid.
