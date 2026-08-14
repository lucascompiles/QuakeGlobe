//
//  Earthquake.swift
//  QuakeGlobe
//
//  Created by Lucas on 14/08/26.
//

import Foundation

struct EarthquakeFeed: Codable {
    let features: [Earthquake]
}

struct Earthquake: Codable, Identifiable {
    let id: String
    let geometry: Geometry
    let properties: Properties

    struct Geometry: Codable {
        let coordinates: [Double]   // [longitude, latitude, profundidade]
    }

    struct Properties: Codable {
        let mag: Double?
        let place: String?
        let time: Double?
    }

    var longitude: Double { geometry.coordinates[0] }
    var latitude: Double { geometry.coordinates[1] }
    var depthKm: Double { geometry.coordinates.count > 2 ? geometry.coordinates[2] : 0 }
    var magnitude: Double { properties.mag ?? 0 }

    var severity: Severity {
        switch magnitude {
        case ..<4.0: .minor
        case ..<5.5: .moderate
        default: .strong
        }
    }

    var date: Date? {
        guard let time = properties.time else { return nil }
        return Date(timeIntervalSince1970: time / 1000)
    }

    enum Severity {
        case minor, moderate, strong

        /// Copy do app em inglês (portfólio internacional).
        var label: String {
            switch self {
            case .minor: "Minor"
            case .moderate: "Moderate"
            case .strong: "Strong"
            }
        }
    }
}
