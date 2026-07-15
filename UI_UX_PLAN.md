# tela UI/UX plan

The Stitch screens are the visual reference, not a second product spec. tela's
working product model stays intact: search belongs to Browse, explicit content
stays discreet, and the core loop remains browse → preview → set.

## Current status

The adaptive shell, Browse and filter redesign, Favorites/local-library polish,
card-based responsive Settings, and compact/expanded Detail layouts are built.
Detail includes download, favorite, share, full-screen preview, and the fixed
Set wallpaper action. Automated phone-width and expanded-width coverage is in
place; the final visual judgment still belongs on real phone and tablet
hardware.

## Product principles

1. **The wallpaper is the interface.** Chrome stays quiet, grids stay dense,
   and colour comes primarily from the work being browsed.
2. **One obvious primary action.** Browse prioritizes search and filters;
   detail prioritizes Set wallpaper; settings save immediately.
3. **Progressive disclosure.** Common choices remain visible while advanced
   filters, storage overrides, and metadata stay one gesture away.
4. **Adaptive, not stretched.** Phones use bottom navigation and stacked
   content. Wider layouts use a rail and, where useful, two panes.
5. **Privacy is part of the UX.** The private library remains behind Settings
   rather than becoming a prominent home-screen destination.

## Information architecture

- **Browse** — search, sorting tabs, filters, and the wallpaper grid.
- **Favorites** — the offline shelf of wallpapers intentionally kept.
- **Settings** — account, browse defaults, download history/routing, and the
  private library.
- Detail, linked listings, history, and private library are focused child
  routes; primary navigation does not compete with their tasks.

## Delivery slices

### 1. Foundation and Browse

- Adaptive bottom navigation / navigation rail.
- Material You-aware midnight fallback palette and shared component styling.
- Search-first app bar, pill sorting tabs, 12px masonry rhythm, and 16px tiles.
- Clear loading, empty, offline, refresh, and selected-filter feedback.

### 2. Detail

- Phone: immersive preview with a stable bottom action area and metadata below.
- Tablet: preview and actions/metadata in a two-pane composition.
- Tap-to-hide chrome, smooth grid-to-preview continuity, and download/share as
  secondary actions.

### 3. Favorites, private library, and history

- Give Favorites an editorial shelf header and consistent grid treatment.
- Keep private content structurally discreet and preserve the secure-window
  and lock behavior.
- Make downloaded/local/missing-file state legible without covering imagery.

### 4. Settings and filters

- Group settings into tonal cards with concise section explanations.
- Keep immediate persistence, but make selection state and consequences clear.
- Rework the large filter sheet into scannable sections with a sticky result
  action and useful active-filter summary.

### 5. Polish and validation

- Motion, haptics where meaningful, 48dp targets, dynamic type, contrast, and
  screen-reader labels.
- Verify phone, small tablet, and large tablet layouts on real hardware.
- Re-check the ≤3 tap core loop and all privacy-sensitive transitions.

## Breakpoints

- **Compact (< 840dp):** bottom navigation, stacked screens, two-column minimum
  wallpaper grid.
- **Expanded (≥ 840dp):** navigation rail, increased grid columns, and optional
  two-pane detail/settings layouts.
