//
//  ContentView.swift
//  QuakeGlobe
//
//  Created by Lucas on 14/08/26.
//

import SwiftUI
import SceneKit

struct ContentView: View {
    @State private var earthquakes: [Earthquake] = []

    var body: some View {
        GlobeView(earthquakes: earthquakes)
            .ignoresSafeArea()
            .background(Color.black)
            .task { await loadEarthquakes() }
    }

    private func loadEarthquakes() async {
        do {
            earthquakes = try await EarthquakeService().fetchRecent()
            print("🌍 \(earthquakes.count) terremotos carregados")
        } catch {
            print("❌ Falha ao buscar terremotos: \(error)")
        }
    }
}

struct GlobeView: UIViewRepresentable {
    let earthquakes: [Earthquake]

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()

        let earth = SCNSphere(radius: 1.0)
        earth.segmentCount = 96

        let material = SCNMaterial()
        material.diffuse.contents = UIImage(named: "earth_texture")
        material.diffuse.mipFilter = .linear
        earth.materials = [material]

        let earthNode = SCNNode(geometry: earth)
        earthNode.name = "earth"
        scene.rootNode.addChildNode(earthNode)

        scnView.scene = scene
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let earthNode = uiView.scene?.rootNode
            .childNode(withName: "earth", recursively: false) else { return }
        plotMarkers(on: earthNode)
    }

    // MARK: - Plot de terremotos

    private func plotMarkers(on earthNode: SCNNode) {
        earthNode.childNodes
            .filter { $0.name?.hasPrefix("quake_") == true }
            .forEach { $0.removeFromParentNode() }

        for quake in earthquakes {
            let sphere = SCNSphere(radius: markerRadius(for: quake.magnitude))
            let color = markerColor(for: quake.magnitude)
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color
            sphere.materials = [material]

            let node = SCNNode(geometry: sphere)
            node.name = "quake_\(quake.id)"
            node.position = surfacePosition(lat: quake.latitude, lon: quake.longitude, radius: 1.01)
            earthNode.addChildNode(node)
        }
    }

    /// Escala exponencial: M2.5 minúsculo, M6+ salta aos olhos.
    private func markerRadius(for magnitude: Double) -> CGFloat {
        CGFloat(min(0.010 * pow(1.4, magnitude - 2.5), 0.05))
    }

    /// Cor por faixa: laranja (fraco) → vermelho (forte).
    private func markerColor(for magnitude: Double) -> UIColor {
        switch magnitude {
        case ..<4.0:
            return UIColor(red: 1.0, green: 0.70, blue: 0.20, alpha: 1)
        case ..<5.5:
            return UIColor(red: 1.0, green: 0.35, blue: 0.10, alpha: 1)
        default:
            return UIColor(red: 1.0, green: 0.10, blue: 0.10, alpha: 1)
        }
    }

    /// lat/lon → posição 3D na superfície (textura equiretangular padrão).
    private func surfacePosition(lat: Double, lon: Double, radius: Double) -> SCNVector3 {
        let latR = lat * .pi / 180
        let lonR = lon * .pi / 180
        let x = radius * cos(latR) * sin(lonR)
        let y = radius * sin(latR)
        let z = radius * cos(latR) * cos(lonR)
        return SCNVector3(Float(x), Float(y), Float(z))
    }
}

#Preview {
    ContentView()
}
