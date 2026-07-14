---
name: Tela Adaptive
colors:
  surface: '#0b1326'
  surface-dim: '#0b1326'
  surface-bright: '#31394d'
  surface-container-lowest: '#060e20'
  surface-container-low: '#131b2e'
  surface-container: '#171f33'
  surface-container-high: '#222a3d'
  surface-container-highest: '#2d3449'
  on-surface: '#dae2fd'
  on-surface-variant: '#c7c4d7'
  inverse-surface: '#dae2fd'
  inverse-on-surface: '#283044'
  outline: '#908fa0'
  outline-variant: '#464554'
  surface-tint: '#c0c1ff'
  primary: '#c0c1ff'
  on-primary: '#1000a9'
  primary-container: '#8083ff'
  on-primary-container: '#0d0096'
  inverse-primary: '#494bd6'
  secondary: '#c3c0ff'
  on-secondary: '#1d00a5'
  secondary-container: '#3626ce'
  on-secondary-container: '#b3b1ff'
  tertiary: '#ffb783'
  on-tertiary: '#4f2500'
  tertiary-container: '#d97721'
  on-tertiary-container: '#452000'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e1e0ff'
  primary-fixed-dim: '#c0c1ff'
  on-primary-fixed: '#07006c'
  on-primary-fixed-variant: '#2f2ebe'
  secondary-fixed: '#e2dfff'
  secondary-fixed-dim: '#c3c0ff'
  on-secondary-fixed: '#0f0069'
  on-secondary-fixed-variant: '#3323cc'
  tertiary-fixed: '#ffdcc5'
  tertiary-fixed-dim: '#ffb783'
  on-tertiary-fixed: '#301400'
  on-tertiary-fixed-variant: '#703700'
  background: '#0b1326'
  on-background: '#dae2fd'
  surface-variant: '#2d3449'
typography:
  display-lg:
    fontFamily: Geist
    fontSize: 56px
    fontWeight: '700'
    lineHeight: 64px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Geist
    fontSize: 40px
    fontWeight: '600'
    lineHeight: 48px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Geist
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: 0.05em
  label-sm:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  rail-width: 72px
  sidebar-width: 280px
  gutter-lg: 24px
  margin-desktop: 40px
  margin-tablet: 32px
  container-max: 1440px
---

## Brand & Style
The design system is a high-performance, developer-centric environment optimized for large-format displays. It targets technical professionals and power users who require high information density without cognitive overload. 

The style is **Modern Corporate** with a technical edge, leaning into a refined dark aesthetic. It emphasizes structural clarity and precision. The emotional response is one of focused immersion—using deep backgrounds and sharp, vibrant accents to guide the eye toward critical actions and data points. On larger screens, the design expands to utilize increased horizontal real estate, transitioning from simple stacks to sophisticated multi-pane layouts.

## Colors
The palette is rooted in a deep "Midnight" dark mode. 

- **Primary (Electric Indigo):** Used exclusively for high-priority interactive elements, active states, and focus indicators.
- **Surface Container:** A critical mid-tone slate used to distinguish side panels, navigation rails, and modal overlays from the base background.
- **Neutral:** A range of grays from deep charcoal to cool slate, used to establish hierarchy in text and non-interactive borders.
- **Accents:** Feedback colors (success, error, warning) should be used sparingly, maintaining the high-contrast relationship against the dark substrate.

## Typography
Typography in this design system scales to accommodate the increased viewing distance typical of tablet and desktop usage. 

- **Geist** provides a sharp, technical feel for headlines, using tight letter-spacing to maintain impact.
- **Inter** ensures maximum legibility for long-form content and UI labels.
- **JetBrains Mono** is utilized for metadata, labels, and code snippets, reinforcing the developer-centric brand narrative.
- On large screens, `display-lg` is reserved for landing moments or dashboard summaries. For standard interior pages, `headline-md` serves as the primary view title.

## Layout & Spacing
This design system utilizes a **Fluid Grid with fixed structural elements**. 

- **Navigation Rail:** On screens wider than 1024px, a 72px fixed-width navigation rail is introduced on the far left. It houses top-level app icons.
- **Surface Containers:** Side panels (e.g., file trees, property inspectors) use a fixed width of 280px and sit within a "Surface Container" layer, visually distinct from the main canvas.
- **Content Area:** The main workspace is fluid but constrained to a 1440px max-width to maintain line-length readability.
- **Gutter & Margins:** A 24px gutter is standard across all 12 columns. Margins increase from 32px on tablets to 40px on large desktops to provide "breathing room" in wide layouts.

## Elevation & Depth
Depth is created through **Tonal Layering** rather than traditional shadows. 

1. **Level 0 (Background):** The deepest hex, used for the primary application canvas.
2. **Level 1 (Surface Container):** A slightly lighter tint used for the Navigation Rail and Sidebars. This creates a clear functional split without the visual noise of heavy shadows.
3. **Level 2 (Cards/Modules):** Elements that sit atop the surface container or background use a subtle 1px border (#334155) to define their edges.
4. **Interactive Elevation:** Only active modals or floating popovers receive an ambient shadow (20% opacity, 12px blur) to signal they are "outside" the primary layout flow.

## Shapes
The shape language is **Soft** and disciplined. A 0.25rem (4px) base radius is applied to buttons and inputs to maintain a professional, slightly architectural look. Larger containers and cards use 0.5rem (8px). This subtle rounding prevents the UI from feeling aggressive while remaining significantly more structured than consumer-focused "round" systems.

## Components
- **Navigation Rail:** Contains vertically stacked icons with 12px padding. Active states are indicated by an Indigo vertical bar (3px width) on the left edge.
- **Buttons:** Primary buttons are solid Electric Indigo with white text. Secondary buttons use a "Ghost" style with an Indigo border and transparent background.
- **Cards:** Cards should have no background fill when sitting on a Surface Container; instead, use a 1px border. When sitting on the Background, they take on the Surface Container color.
- **Inputs:** Dark backgrounds with a 1px slate border. On focus, the border transitions to Electric Indigo with a subtle outer glow.
- **Side Panels:** Use a vertical divider (1px) rather than a shadow to separate from the main content. Ensure they are collapsible to a minimized "icon-only" state to maximize workspace.
- **Chips:** Monospaced text (JetBrains Mono) inside high-contrast, low-roundedness containers for status tags or filters.