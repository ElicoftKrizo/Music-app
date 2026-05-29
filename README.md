# CustomPlayer

A sideloadable iOS media player with Spotify Canvas–style adaptive UI, AVAudioPlayer audio engine, CHHapticEngine AHAP sync, and high-frequency lyric clock — built entirely in the cloud via GitHub Actions.

## Repository Structure

```
CustomPlayer/
├── Project.swift                        # Tuist 4.x project manifest
├── Sources/
│   └── ContentView.swift                # Full SwiftUI app — single-file architecture
├── Resources/
│   ├── music.mp3                        # ← DROP YOUR TRACK HERE
│   ├── haptic.ahap                      # ← DROP YOUR AHAP PATTERN HERE
│   ├── canvas.mp4                       # ← DROP YOUR 8-SECOND LOOP HERE (optional)
│   └── cover.png  (or cover.jpg)        # ← DROP YOUR ALBUM ART HERE
└── .github/
    └── workflows/
        └── build.yml                    # GitHub Actions cloud build pipeline
```

## Quick Start

1. Add your media assets to `Resources/`
2. Push to `main` or `master`
3. GitHub Actions runs automatically on `macos-14`
4. Download `CustomPlayer-unsigned-ipa` from the Actions run's Artifacts section
5. Sideload with **AltStore**, **Sideloadly**, or **TrollStore**

## Adaptive UI Logic

| Condition | Layout |
|---|---|
| `canvas.mp4` present in bundle | Looping video background (Spotify Canvas mode) · dark overlay · floating lyrics center · thumbnail artwork in lower-third |
| `canvas.mp4` absent | Static dark maroon gradient · large artwork upper-center · lyrics below artwork |

## Requirements for Local Development

- Xcode 15+
- Tuist 4.x (`mise install`)
- Run `tuist generate` then open `CustomPlayer.xcworkspace`
