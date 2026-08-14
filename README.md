# QuakeGlobe 🌍

Real-time seismic activity on an interactive 3D globe.

![Globe](screenshots/globe.png)
![Detail card](screenshots/detail.png)

## Features

- Interactive 3D globe (SceneKit) with real Earth texture and drifting cloud layer
- Live earthquake data from the USGS real-time feed (M2.5+, past 24h)
- Markers scaled and colored by magnitude
- Tap any marker for details: magnitude, place, relative time, depth, coordinates
- Custom camera rig: inertia, zoom-proportional pan, smooth pinch zoom

## Stack

- Swift / SwiftUI + UIKit (`UIViewRepresentable`)
- SceneKit for the 3D globe and hit-testing
- async/await + `Codable` for the USGS GeoJSON feed
- Swift Testing for the model layer

## Setup

1. Clone the repo
2. Open `QuakeGlobe.xcodeproj` in Xcode 16+
3. Run on device or simulator (iOS 18+)

## Architecture

    QuakeGlobe/
    ├── Models/             # Earthquake, GeoJSON mapping, severity
    ├── Services/           # EarthquakeService (USGS fetch)
    ├── ContentView.swift   # GlobeView (SceneKit) + detail sheet
    └── QuakeGlobeTests/    # Swift Testing: decoding + severity

## Roadmap

- Auto-refresh feed
- Favorites with SwiftData
- Fly-to animation on search
- Loading/error states and VoiceOver labels