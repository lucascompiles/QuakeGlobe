//
//  QuakeGlobeTests.swift
//  QuakeGlobeTests
//
//  Created by Lucas on 14/08/26.
//

import Foundation
import Testing
@testable import QuakeGlobe

struct EarthquakeDecodingTests {

    let sampleJSON = Data("""
    {
      "features": [
        {
          "id": "test1",
          "geometry": { "type": "Point", "coordinates": [-118.24, 34.05, 12.5] },
          "properties": { "mag": 4.7, "place": "Greater Los Angeles", "time": 1700000000000 }
        },
        {
          "id": "test2",
          "geometry": { "type": "Point", "coordinates": [139.69, 35.68] },
          "properties": { "mag": null, "place": "Tokyo", "time": 1700000000000 }
        }
      ]
    }
    """.utf8)

    @Test func decodesFeatures() throws {
        let feed = try JSONDecoder().decode(EarthquakeFeed.self, from: sampleJSON)
        #expect(feed.features.count == 2)
    }

    @Test func mapsCoordinatesAndMagnitude() throws {
        let feed = try JSONDecoder().decode(EarthquakeFeed.self, from: sampleJSON)
        let quake = feed.features[0]
        #expect(quake.longitude == -118.24)
        #expect(quake.latitude == 34.05)
        #expect(quake.depthKm == 12.5)
        #expect(quake.magnitude == 4.7)
    }

    @Test func nullMagnitudeFallsBackToZero() throws {
        let feed = try JSONDecoder().decode(EarthquakeFeed.self, from: sampleJSON)
        #expect(feed.features[1].magnitude == 0)
    }
}

struct SeverityTests {

    private func makeQuake(mag: Double?) -> Earthquake {
        Earthquake(
            id: "t",
            geometry: .init(coordinates: [0, 0, 10]),
            properties: .init(mag: mag, place: nil, time: nil)
        )
    }

    @Test func severityThresholds() {
        #expect(makeQuake(mag: 3.9).severity == .minor)
        #expect(makeQuake(mag: 4.0).severity == .moderate)
        #expect(makeQuake(mag: 5.4).severity == .moderate)
        #expect(makeQuake(mag: 5.5).severity == .strong)
        #expect(makeQuake(mag: nil).severity == .minor)
    }
}

struct FavoriteQuakeTests {

    @Test func snapshotRoundTrip() {
        let quake = Earthquake(
            id: "t1",
            geometry: .init(coordinates: [-118.24, 34.05, 12.5]),
            properties: .init(mag: 4.7, place: "Greater Los Angeles", time: 1700000000000)
        )
        let fav = FavoriteQuake(from: quake)

        #expect(fav.earthquake.id == "t1")
        #expect(fav.earthquake.magnitude == 4.7)
        #expect(fav.earthquake.latitude == 34.05)
        #expect(fav.earthquake.longitude == -118.24)
        #expect(fav.earthquake.depthKm == 12.5)
        #expect(fav.earthquake.date != nil)
    }
}
