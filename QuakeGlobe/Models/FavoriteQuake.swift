//
//  FavoriteQuake.swift
//  QuakeGlobe
//
//  Created by Lucas on 14/08/26.
//

import Foundation
import SwiftData

@Model
final class FavoriteQuake {
    @Attribute(.unique) var quakeID: String
    var magnitude: Double
    var place: String
    var time: Double          // epoch ms; 0 = sem timestamp
    var latitude: Double
    var longitude: Double
    var depthKm: Double

    init(from quake: Earthquake) {
        self.quakeID = quake.id
        self.magnitude = quake.magnitude
        self.place = quake.properties.place ?? "Location not reported"
        self.time = quake.properties.time ?? 0
        self.latitude = quake.latitude
        self.longitude = quake.longitude
        self.depthKm = quake.depthKm
    }

    /// Snapshot volta a ser Earthquake pra reutilizar o card de detalhe.
    var earthquake: Earthquake {
        Earthquake(
            id: quakeID,
            geometry: .init(coordinates: [longitude, latitude, depthKm]),
            properties: .init(mag: magnitude, place: place, time: time > 0 ? time : nil)
        )
    }
}
