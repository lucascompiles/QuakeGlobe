//
//  EarthquakeService.swift
//  QuakeGlobe
//
//  Created by Lucas on 14/08/26.
//

import Foundation

struct EarthquakeService {
    enum ServiceError: Error {
        case badURL
        case badStatus(Int)
    }

    /// M2.5+ nas últimas 24h: densidade boa sem poluir o globo.
    private let feedURL = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson"

    func fetchRecent() async throws -> [Earthquake] {
        guard let url = URL(string: feedURL) else { throw ServiceError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw ServiceError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        return try JSONDecoder().decode(EarthquakeFeed.self, from: data).features
    }
}
