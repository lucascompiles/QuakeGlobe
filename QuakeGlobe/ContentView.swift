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
    @State private var selectedQuake: Earthquake?

    var body: some View {
        GlobeView(earthquakes: earthquakes) { quake in
            selectedQuake = quake
        }
        .ignoresSafeArea()
        .background(Color.black)
        .task { await loadEarthquakes() }
        .sheet(item: $selectedQuake) { quake in
            QuakeDetailSheet(quake: quake)
        }
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

// MARK: - Globo 3D

struct GlobeView: UIViewRepresentable {
    let earthquakes: [Earthquake]
    let onSelect: (Earthquake) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()

        // Terra
        let earth = SCNSphere(radius: 1.0)
        earth.segmentCount = 96

        let material = SCNMaterial()
        material.diffuse.contents = UIImage(named: "earth_texture")
        material.diffuse.mipFilter = .linear
        earth.materials = [material]

        let earthNode = SCNNode(geometry: earth)
        earthNode.name = "earth"
        earthNode.eulerAngles.y = Float(75.0 * .pi / 180)
        scene.rootNode.addChildNode(earthNode)

        // Nuvens
        let clouds = SCNSphere(radius: 1.06)
        clouds.segmentCount = 96

        let cloudMaterial = SCNMaterial()
        cloudMaterial.diffuse.contents = UIImage(named: "earth_clouds")
        cloudMaterial.diffuse.intensity = 0.6
        cloudMaterial.lightingModel = .constant
        cloudMaterial.blendMode = .add
        cloudMaterial.writesToDepthBuffer = false
        clouds.materials = [cloudMaterial]

        let cloudsNode = SCNNode(geometry: clouds)
        cloudsNode.name = "clouds"
        scene.rootNode.addChildNode(cloudsNode)

        let drift = SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 240)
        cloudsNode.runAction(.repeatForever(drift))

        scnView.scene = scene

        // Toque → Coordinator
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        scnView.addGestureRecognizer(tap)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self   // mantém o coordinator em dia
        guard let earthNode = uiView.scene?.rootNode
            .childNode(withName: "earth", recursively: false) else { return }
        plotMarkers(on: earthNode)
    }

    // MARK: Plot

    private func plotMarkers(on earthNode: SCNNode) {
        earthNode.childNodes
            .filter { $0.name?.hasPrefix("quake_") == true }
            .forEach { $0.removeFromParentNode() }

        for quake in earthquakes {
            let sphere = SCNSphere(radius: markerRadius(for: quake.magnitude))
            let color = quake.severity.uiColor
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

    private func markerRadius(for magnitude: Double) -> CGFloat {
        CGFloat(min(0.010 * pow(1.4, magnitude - 2.5), 0.05))
    }

    private func surfacePosition(lat: Double, lon: Double, radius: Double) -> SCNVector3 {
        let latR = lat * .pi / 180
        let lonR = lon * .pi / 180
        let x = radius * cos(latR) * sin(lonR)
        let y = radius * sin(latR)
        let z = radius * cos(latR) * cos(lonR)
        return SCNVector3(Float(x), Float(y), Float(z))
    }

    // MARK: Coordinator (ponte UIKit → SwiftUI)

    final class Coordinator: NSObject {
        var parent: GlobeView

        init(_ parent: GlobeView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = gesture.view as? SCNView else { return }
            let point = gesture.location(in: scnView)

            // FIX: por padrão o hitTest retorna só o acerto mais próximo
            // (sempre a nuvem, que está na frente). .all devolve tudo ao
            // longo do raio; o filtro abaixo pega o marcador.
            let results = scnView.hitTest(
                point,
                options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue]
            )

            guard let hit = results.first(where: { $0.node.name?.hasPrefix("quake_") == true }),
                  let name = hit.node.name,
                  let quake = parent.earthquakes.first(where: { name == "quake_\($0.id)" })
            else { return }

            parent.onSelect(quake)
        }
    }
}

// MARK: - Cores de severidade (camada de apresentação)

extension Earthquake.Severity {
    var uiColor: UIColor {
        switch self {
        case .minor: UIColor(red: 1.0, green: 0.70, blue: 0.20, alpha: 1)
        case .moderate: UIColor(red: 1.0, green: 0.35, blue: 0.10, alpha: 1)
        case .strong: UIColor(red: 1.0, green: 0.10, blue: 0.10, alpha: 1)
        }
    }

    var color: Color {
        switch self {
        case .minor: Color(red: 1.0, green: 0.70, blue: 0.20)
        case .moderate: Color(red: 1.0, green: 0.35, blue: 0.10)
        case .strong: Color(red: 1.0, green: 0.10, blue: 0.10)
        }
    }
}

// MARK: - Card de detalhe

struct QuakeDetailSheet: View {
    let quake: Earthquake

    var body: some View {
        VStack(spacing: 14) {
            Text("M \(quake.magnitude, specifier: "%.1f")")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(quake.severity.color)
                .padding(.top, 24)

            Text(quake.severity.label.uppercased())
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(quake.severity.color.opacity(0.2), in: Capsule())
                .foregroundStyle(quake.severity.color)

            Text(quake.properties.place ?? "Local não informado")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 4) {
                if let date = quake.date {
                    Label {
                        Text(date, format: .relative(presentation: .named))
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                }
                Label {
                    Text("Profundidade: \(Int(quake.depthKm)) km")
                } icon: {
                    Image(systemName: "arrow.down.to.line")
                }
                .font(.subheadline)
                .foregroundStyle(.gray)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .presentationBackground(.black)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    ContentView()
}
