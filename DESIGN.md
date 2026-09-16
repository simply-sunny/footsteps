# Documentation site design

Scope: `docs/index.html`, `docs/style.css`, `docs/site.js`. Follows the Silk-S1 / Simply Sunny reference required by issues #6–9; not a native app redesign.

- Canvas `#050608`, 48px hairline grid; surface `#0e1116`, border `#303943`.
- Text `#eee`, secondary `#a2abb6`, action/path `#b9d5ff`, duration heat `#f6b96b`.
- System typography matching the sibling docs site; fluid 3.5–6rem title, 1.5–2rem section headings, 15px document body.
- Content max 1160px including gutters. Four metric columns become two below 900px and one below 600px.
- Pill navigation/tabs; 8px panels. Reader has fixed height to prevent document-switch layout shift.
- Visible keyboard focus, arrow-key document tabs, pressed mode state, reduced-motion support, synthetic trajectory labeled in text and SVG description.
- **Keep authored CSS below 100 lines.** Current stylesheet: 62 lines. No CSS framework.
- Avoid unsupported battery/network claims. MapKit network use and unmeasured power consumption remain explicit.

Verification: desktop 1440px and mobile 390px captures; browser assertions in `Tests/site-check.cjs`. Impeccable detector run once: grid advisory is brief-pinned; section-padding warnings contradicted by computed 56px/36px vertical padding. Finish inspection performed inline (no subagent tool available); final reader alignment corrected across headings and body.

Existing logo reused from repository `logo-dark.png`; see `ATTRIBUTION.md`. No generated raster assets.
