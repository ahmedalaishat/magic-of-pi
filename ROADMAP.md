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

## Phase 3 — Share
- [ ] **Export video**: record a mode playing (incl. Spotlight / camera moves) to Photos or share sheet.
- [ ] **Save as wallpaper**: high-resolution still of the current drawing.

## Phase 4 — Reach
- [ ] **AR**: place the 3D Walk or 3D Spring in the room (RealityKit + ARKit).
- [ ] **Home-screen widget**: one new chord of π per hour.
- [ ] **Compare numbers**: run the visuals with e, √2 and φ next to π.

## Production readiness (alongside the phases)
- [ ] **Source control**: git repository, .gitignore (build/ already ignored).
- [ ] **Release build**: optimised configuration; profile all modes on device at max speed.
- [ ] **Privacy manifest** (PrivacyInfo.xcprivacy): no data collected, no tracking.
- [ ] **Accessibility**: VoiceOver labels on all controls, Reduce Motion (no auto camera moves,
      static splash), Dynamic Type for text, sufficient contrast.
- [ ] **iPad**: layouts for larger screens and landscape (the app already builds for iPad).
- [ ] **Persistence**: remember last mode, settings and speeds between launches.
- [ ] **Tests**: unit tests for the maths (π digits, closest approach, near-miss detection,
      Fourier outline) and UI smoke tests that launch every mode.
- [ ] **Swift 6 language mode**: strict concurrency (the code is already close; a few warnings).
- [ ] **Localisation**: English first; Arabic as a candidate (right-to-left layout check).
- [ ] **Distribution** (deferred): Apple Developer Program account, TestFlight beta, App Store
      listing (screenshots, preview video from the export feature, description, keywords), review notes.
