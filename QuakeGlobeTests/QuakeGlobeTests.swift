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
