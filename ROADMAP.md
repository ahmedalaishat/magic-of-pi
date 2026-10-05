# π Visualizer — Roadmap

Goal: a production App Store app that shows the magic of π. Four modes exist today (Chords, Rods,
3D Walk, 3D Spring) with Spotlight, camera moves and full screen.

## Phase 1 — First impression and identity
- [x] **Splash screen**: Fourier rods draw the π glyph live, it glows, the digits stream in, then it
      fades into the app. Tap to skip; respects Reduce Motion.
- [x] **Launch screen**: black, so the app opens straight into the splash without a white flash.
- [x] **App icon**: glowing π over the digit ring and chords (1024 px; regenerate with
      `python3 tools/make_icon.py PiVisualizer/Assets.xcassets/AppIcon.appiconset/AppIcon.png`).
- [x] **Name**: "Magic of π".

## Phase 2 — Make it an experience
- [x] **π music**: each digit plays a note on a pentatonic scale, synced with drawing and haptics;
      close calls play a chord. Mute toggle, respects the silent switch.
- [x] **"Why?" cards**: one short tap-to-read explanation per mode (why rods never close, why the
      digits look random, what 355/113 means).
- [x] **Find your birthday in π**: searches 10,000,000 digits (bundled packed, 5 MB; regenerate with
      tools/pack_digits.py), tries other ways of writing a date, shows the match in context with honest
      odds, and can walk the 3D Walk to it (matches within 100,000 digits).

## Onboarding
- [x] **Welcome card**: one-time tips after the splash.

## Phase 3 — Share
- [x] **Export video**: ⏺ in the control bar records the visualization (cropped, with music) to an MP4;
      preview with Share and Save to Photos.
- [x] **Save as wallpaper**: options → Save as wallpaper (1290 × 2796).

## Phase 4 — Reach
- [x] **AR**: options → View in AR in 3D Walk and 3D Spring (ARKit + SceneKit).
- [ ] **Home-screen widget**: one new chord of π per hour. Needs a widget extension target (add via
      Xcode → New Target → Widget Extension), not hand-edited into the project.
- [x] **Compare numbers**: Chords and 3D Walk can draw e, √2 or φ (1,000,000 digits each).

## Production readiness (alongside the phases)
- [x] **Source control**: git repository with .gitignore.
- [ ] **Release build**: optimised configuration; profile all modes on device at max speed.
- [x] **Privacy manifest** (PrivacyInfo.xcprivacy): no data collected, no tracking; required-reason APIs declared.
- [x] **Accessibility**: VoiceOver labels and values for controls and visualizations; Reduce Motion
      (static splash, no automatic camera orbits). Dynamic Type: system fonts throughout.
- [x] **iPad**: layout scales to iPad (checked on iPad Pro 13-inch). Landscape: still to review.
- [x] **Persistence**: remembers the last mode and each mode's settings between launches.
- [x] **Tests**: unit tests for the maths (PiVisualizerTests, Swift Testing). UI smoke tests: to do.
- [ ] **Swift 6 language mode**: strict concurrency (the code is already close; a few warnings).
- [ ] **Localisation**: English first; Arabic as a candidate (right-to-left layout check).
- [ ] **Distribution** (deferred): Apple Developer Program account, TestFlight beta, App Store
      listing (screenshots, preview video from the export feature, description, keywords), review notes.
