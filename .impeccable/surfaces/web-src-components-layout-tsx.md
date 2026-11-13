---
version: 1
slug: "web-src-components-layout-tsx"
primary_target: "web/src/components/Layout.tsx"
related_targets: ["web/src/pages/Dashboard.tsx"]
---

# App shell and all screens

Scope: the whole web app (shell, Dashboard, Activity, Bills, Paychecks, Spending, Debts, Envelopes, Login, sheets). Mode: Operate.
Audience and job: the owner, on a phone at night or at a desk on payday; read safe-to-spend and what's due, log a purchase in seconds.
Constraints: every number is a view column; no count-up or interpolated money values. Dark only (user confirmed). Maximal motion (user confirmed), all of it off under Reduce Motion. Touch targets 40px+.

## Direction contract

seed: none (pinned)

FORM: Pinned by the user: "give the whole project a futuristic glassmorphism styling UI, following same color schemes, animations where you can, really push that HUD feel", applied to the existing app's screens. Confirmed: Dark only; Maximal motion.

THESIS: A night instrument cluster made of smoked glass with lit pine seams. Refuses the flat light admin card grid.
OWN-WORLD: Near-black ground with drifting pine, teal and cold-blue light fields behind frosted, beveled glass panels; 1px white-alpha edges, a top-lit seam per panel, pine as the light source; status colors glow only where they carry meaning. System sans, tabular figures.
STORY: The eye lands on safe-to-spend, lit brightest; everything else sits one step dimmer behind glass.
FIRST VIEWPORT: Glass rail or floating glass dock, page title over a drawn lit rule, the Safe-to-spend panel as the brightest object with a reticle (ring of light plus brackets) around its figure; net position (unlit) and the four status tiles stacked beside it.
SIGNATURE: Lit seams: every panel's top edge carries pine light that travels along it; the active nav item is lit by the same light, and the dock indicator glides between tabs.
RISK: Glass and blur cost GPU on phones; blur is capped and ambient motion is transform-only.
