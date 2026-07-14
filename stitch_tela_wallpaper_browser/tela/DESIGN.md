---
name: Tela
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
  secondary: '#b9c8de'
  on-secondary: '#233143'
  secondary-container: '#39485a'
  on-secondary-container: '#a7b6cc'
  tertiary: '#ffb2b7'
  on-tertiary: '#67001b'
  tertiary-container: '#ff516a'
  on-tertiary-container: '#5b0017'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e1e0ff'
  primary-fixed-dim: '#c0c1ff'
  on-primary-fixed: '#07006c'
  on-primary-fixed-variant: '#2f2ebe'
  secondary-fixed: '#d4e4fa'
  secondary-fixed-dim: '#b9c8de'
  on-secondary-fixed: '#0d1c2d'
  on-secondary-fixed-variant: '#39485a'
  tertiary-fixed: '#ffdadb'
  tertiary-fixed-dim: '#ffb2b7'
  on-tertiary-fixed: '#40000d'
  on-tertiary-fixed-variant: '#92002a'
  background: '#0b1326'
  on-background: '#dae2fd'
  surface-variant: '#2d3449'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  title-md:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 16px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  gutter: 12px
  margin-mobile: 16px
  margin-desktop: 32px
---

## Brand & Style
The design system is built for a premium, utility-driven wallpaper browser that prioritizes content immersion. The brand personality is focused and quiet, acting as a sophisticated gallery frame for high-resolution imagery. 

The aesthetic follows a **Modern Corporate** approach with a heavy influence from **Material 3 (Material You)**. It utilizes a deep, monochromatic foundation to let wallpaper colors pop, while employing subtle motion and glass-like overlays to create a sense of high polish. The UI should feel invisible until needed, emphasizing ease of use through a "dead-simple" interaction model.

## Colors
The palette is rooted in a deep charcoal and slate foundation to minimize light bleed and maximize the perceived contrast of the wallpapers. 

- **Primary (Electric Indigo):** Used for critical actions, active states, and focus indicators.
- **Surface Tones:** A range of slates (Slate 800-950) are used to create structural depth without using pure black.
- **Dynamic Color:** This design system fully supports Material You. When enabled, the Electric Indigo primary and slate neutrals should be mapped to the user's generated color scheme, maintaining the established luminance levels to preserve the dark-mode hierarchy.

## Typography
Inter is selected for its exceptional legibility and neutral, systematic feel. It provides a functional backdrop that doesn't compete with the diverse artistic styles of the wallpapers.

- **Headlines:** Use semi-bold weights with tight tracking to create a premium, editorial feel.
- **Labels:** Use medium weights and slight letter spacing for navigation and metadata to ensure clarity at small sizes.
- **Hierarchy:** Maintain a clear distinction between content titles (Title MD) and functional labels (Label MD) to guide the user's eye toward discovery.

## Layout & Spacing
The layout follows a **Fluid Grid** model optimized for edge-to-edge visual immersion.

- **Wallpaper Grid:** Use a staggered (masonry) grid for the main feed. This accommodates various aspect ratios and creates a dynamic, high-end browsing experience. 
- **Guttering:** Keep gutters tight (12px) to minimize "white space" between images, making the UI feel like a continuous canvas.
- **Safe Areas:** Ensure content respects the system bars (status and navigation). The bottom navigation bar should utilize a translucent background blur to allow the wallpaper grid to peak through behind it.

## Elevation & Depth
Depth is conveyed through **Tonal Layers** rather than heavy shadows, following Material 3 principles.

- **Level 0 (Background):** The deepest slate, used for the main canvas.
- **Level 1 (Cards/Chips):** A slightly lighter slate surface to distinguish interactive elements from the background.
- **Level 2 (Modals/Bottom Sheets):** Elevated surfaces that use a subtle 1px inner border (low-contrast outline) to define edges against the dark background.
- **Glassmorphism:** Use a 20px backdrop blur on the Top App Bar and Bottom Navigation to maintain context of the scroll position while providing a readable surface for controls.

## Shapes
This design system uses a **Rounded** shape language to feel approachable and modern.

- **Wallpaper Thumbnails:** 1rem (16px) corner radius to soften the edges of the imagery.
- **Buttons & Chips:** Fully pill-shaped for high-touch targets, contrasting against the large rectangular wallpaper blocks.
- **Bottom Sheets:** Only the top corners are rounded (1.5rem) to signify they are anchored to the bottom of the screen.

## Components
- **Staggered Grid:** The primary view. Images should fade in with a subtle scale-up animation to emphasize quality.
- **Filter Chips:** Pill-shaped, using a "Surface Level 1" background when inactive and the "Electric Indigo" primary color when active.
- **Bottom Navigation:** M3-spec navigation with an active indicator (a pill shape behind the icon). Use a backdrop blur effect for the bar container.
- **Action Buttons:** Floating Action Buttons (FABs) for "Set Wallpaper" should be large, centered in bottom sheets, using the primary accent color.
- **Input Fields:** Search bars should be integrated into the top app bar with a subtle slate-900 background and no border.
- **Detail View:** A full-screen immersive mode that hides all UI elements upon a single tap, allowing the user to preview the wallpaper without distraction.