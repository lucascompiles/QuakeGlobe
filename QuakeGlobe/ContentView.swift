//
//  ContentView.swift
//  QuakeGlobe
//
//  Created by Lucas on 14/08/26.
//

import SwiftUI
import SceneKit
import SwiftData
import simd

// MARK: - Estado de carregamento

enum LoadState: Equatable {
    case loading
    case loaded
    case failed
}

struct ContentView: View {
    @State private var earthquakes: [Earthquake] = []
    @State private var selectedQuake: Earthquake?
    @State private var loadState: LoadState = .loading
    @State private var lastLoad: Date?
    @State private var showFavorites = false
    @Query private var favorites: [FavoriteQuake]
    @Environment(\.scenePhase) private var scenePhase

    /// Intervalo do auto-refresh. 300s em produção; baixe pra testar.
    private let refreshInterval: TimeInterval = 300

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GlobeView(earthquakes: earthquakes) { quake in
                selectedQuake = quake
            }
            .ignoresSafeArea()
            .background(Color.black)
            .overlay { statusOverlay }

            favoritesButton
                .padding(.trailing, 16)
        }
        .task {
            await loadEarthquakes()
            await autoRefreshLoop()
        }
        .onChange(of: scenePhase) { _, phase in
            // Reabriu o app depois de muito tempo? Atualiza na hora.
            guard phase == .active, let lastLoad else { return }
            if Date().timeIntervalSince(lastLoad) > refreshInterval {
                Task { await loadEarthquakes() }
            }
        }
        .sheet(item: $selectedQuake) { quake in
            QuakeDetailSheet(quake: quake)
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesListView()
                .presentationBackground(.black)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Botão de favoritos

    private var favoritesButton: some View {
        Button {
            showFavorites = true
        } label: {
            Image(systemName: favorites.isEmpty ? "heart" : "heart.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(favorites.isEmpty ? .white : .red)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if !favorites.isEmpty {
                        Text("\(favorites.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.red, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
        }
    }

    // MARK: Overlay de status

    @ViewBuilder
    private var statusOverlay: some View {
        switch loadState {
        case .loading where earthquakes.isEmpty:
            ProgressView("Loading earthquakes…")
                .tint(.white)
                .foregroundStyle(.white)

        case .failed where earthquakes.isEmpty:
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                Text("Unable to Load Earthquakes")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await loadEarthquakes() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.top, 4)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(32)

        default:
            EmptyView()
        }
    }

    // MARK: Carga + refresh

    private func autoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(refreshInterval))
            if Task.isCancelled { break }
            await loadEarthquakes()
        }
    }

    private func loadEarthquakes() async {
        if earthquakes.isEmpty {
            loadState = .loading
        }
        do {
            earthquakes = try await EarthquakeService().fetchRecent()
            loadState = .loaded
            lastLoad = Date()
            print("🌍 \(earthquakes.count) terremotos carregados")
        } catch {
            // Com dados na tela, falha de refresh é silenciosa (dado > erro)
            if earthquakes.isEmpty { loadState = .failed }
            print("❌ Falha ao buscar terremotos: \(error)")
        }
    }
}

// MARK: - Globo 3D com interação própria

struct GlobeView: UIViewRepresentable {
    let earthquakes: [Earthquake]
    let onSelect: (Earthquake) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()

        // Câmera explícita (zNear pequeno pra não clipar no zoom máximo)
        let camera = SCNCamera()
        camera.zNear = 0.01
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, context.coordinator.currentDistance)
        scene.rootNode.addChildNode(cameraNode)

        // Luz direcional filha da câmera (face visível acesa) + ambiente
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        let keyNode = SCNNode()
        keyNode.light = key
        cameraNode.addChildNode(keyNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 350
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Container que gira (Terra + nuvens + marcadores)
        let globeNode = SCNNode()
        globeNode.name = "globe"
        globeNode.eulerAngles.y = Float(75.0 * .pi / 180)
        scene.rootNode.addChildNode(globeNode)

        // Terra
        let earth = SCNSphere(radius: 1.0)
        earth.segmentCount = 96

        let material = SCNMaterial()
        material.diffuse.contents = UIImage(named: "earth_texture")
        material.diffuse.mipFilter = .linear
        earth.materials = [material]

        let earthNode = SCNNode(geometry: earth)
        earthNode.name = "earth"
        globeNode.addChildNode(earthNode)

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
        globeNode.addChildNode(cloudsNode)

        let drift = SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 240)
        cloudsNode.runAction(.repeatForever(drift))

        scnView.scene = scene

        // Referências + display link (inércia e zoom suave)
        context.coordinator.scnView = scnView
        context.coordinator.globeNode = globeNode
        context.coordinator.cameraNode = cameraNode
        context.coordinator.startDisplayLink()

        // Gestos
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        scnView.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tap)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        guard let earthNode = uiView.scene?.rootNode
            .childNode(withName: "earth", recursively: true) else { return }
        plotMarkers(on: earthNode)
    }

    // MARK: Plot (marcador visível + proxy de toque invisível)

    private func plotMarkers(on earthNode: SCNNode) {
        earthNode.childNodes
            .filter { $0.name?.hasPrefix("quake_") == true }
            .forEach { $0.removeFromParentNode() }

        for quake in earthquakes {
            let color = quake.severity.uiColor
            let position = surfacePosition(lat: quake.latitude, lon: quake.longitude, radius: 1.01)

            // Marcador visível
            let sphere = SCNSphere(radius: markerRadius(for: quake.magnitude))
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.emission.contents = color
            sphere.materials = [m]
            let vis = SCNNode(geometry: sphere)
            vis.name = "quake_vis_\(quake.id)"
            vis.position = position
            earthNode.addChildNode(vis)

            // Proxy de toque: invisível, ~2x maior — dedo não erra
            let proxy = SCNSphere(radius: max(markerRadius(for: quake.magnitude) * 2.2, 0.035))
            let pm = SCNMaterial()
            pm.colorBufferWriteMask = []          // não desenha nada
            pm.writesToDepthBuffer = false
            proxy.materials = [pm]
            let proxyNode = SCNNode(geometry: proxy)
            proxyNode.name = "quake_\(quake.id)"
            proxyNode.categoryBitMask = 2          // hitTest filtra por isso
            proxyNode.position = position
            earthNode.addChildNode(proxyNode)
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

    // MARK: Coordinator

    final class Coordinator: NSObject {
        var parent: GlobeView
        weak var scnView: SCNView?
        var globeNode: SCNNode?
        var cameraNode: SCNNode?

        private var displayLink: CADisplayLink?

        // Rotação (turntable: yaw no eixo do mundo, pitch na horizontal)
        private var yaw: Float = Float(75.0 * .pi / 180)
        private var pitch: Float = 0
        private var velocityYaw: Float = 0
        private var velocityPitch: Float = 0
        private var inertiaActive = false

        // Zoom suavizado
        var currentDistance: Float = 3.0
        private var targetDistance: Float = 3.0
        private let minDistance: Float = 1.25
        private let maxDistance: Float = 4.0

        init(_ parent: GlobeView) {
            self.parent = parent
        }

        func startDisplayLink() {
            teardown()
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func teardown() {
            displayLink?.invalidate()
            displayLink = nil
        }

        /// Velocidade do pan proporcional ao zoom (expoente 2.0: calibrado no device).
        private var panFactor: Float {
            0.009 * pow(currentDistance / maxDistance, 2.0)
        }

        private func applyOrientation() {
            globeNode?.simdOrientation =
                simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0)) *
                simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        }

        @objc private func tick(_ link: CADisplayLink) {
            let dt = Float(link.targetTimestamp - link.timestamp)

            // Inércia com decay exponencial
            if inertiaActive {
                yaw += velocityYaw * dt
                pitch += velocityPitch * dt
                pitch = min(max(pitch, -1.1), 1.1)

                let decay = exp(-3.5 * dt)
                velocityYaw *= decay
                velocityPitch *= decay

                if abs(velocityYaw) < 0.01, abs(velocityPitch) < 0.01 {
                    inertiaActive = false
                }
                applyOrientation()
            }

            // Zoom interpolado (suave, sem pulo)
            if abs(targetDistance - currentDistance) > 0.001 {
                currentDistance += (targetDistance - currentDistance) * min(1, dt * 12)
                cameraNode?.position = SCNVector3(0, 0, currentDistance)
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.view != nil else { return }

            switch gesture.state {
            case .began:
                inertiaActive = false          // dedo encostou = inércia morre
            case .changed:
                let t = gesture.translation(in: gesture.view!)
                gesture.setTranslation(.zero, in: gesture.view!)
                yaw += Float(t.x) * panFactor
                pitch += Float(t.y) * panFactor
                pitch = min(max(pitch, -1.1), 1.1)
                applyOrientation()
            case .ended:
                let v = gesture.velocity(in: gesture.view!)
                velocityYaw = Float(v.x) * panFactor
                velocityPitch = Float(v.y) * panFactor
                inertiaActive = true           // soltou = desliza e assenta
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else { return }
            targetDistance = min(max(targetDistance / Float(gesture.scale), minDistance), maxDistance)
            gesture.scale = 1
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = scnView else { return }
            let point = gesture.location(in: scnView)

            // Só os proxies (máscara 2) participam — nuvem e Terra não interferem
            let options: [SCNHitTestOption: Any] = [
                SCNHitTestOption.categoryBitMask: 2,
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue
            ]

            guard let hit = scnView.hitTest(point, options: options).first,
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

// MARK: - Card de detalhe (com favorito)

struct QuakeDetailSheet: View {
    let quake: Earthquake
    @Environment(\.modelContext) private var context
    @Query private var matches: [FavoriteQuake]

    init(quake: Earthquake) {
        self.quake = quake
        let id = quake.id
        _matches = Query(filter: #Predicate<FavoriteQuake> { $0.quakeID == id })
    }

    private var isFavorite: Bool { !matches.isEmpty }

    private var magnitudeText: String {
        String(format: "%.1f", quake.magnitude)
    }

    private var coordinatesText: String {
        String(format: "%.1f°%@, %.1f°%@",
               abs(quake.latitude), quake.latitude >= 0 ? "N" : "S",
               abs(quake.longitude), quake.longitude >= 0 ? "E" : "W")
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("M \(magnitudeText)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(quake.severity.color)
                .padding(.top, 24)

            Text(quake.severity.label.uppercased())
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(quake.severity.color.opacity(0.2), in: Capsule())
                .foregroundStyle(quake.severity.color)

            Text(quake.properties.place ?? "Location not reported")
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
                    Text("Depth: \(Int(quake.depthKm)) km")
                } icon: {
                    Image(systemName: "arrow.down.to.line")
                }
                .font(.subheadline)
                .foregroundStyle(.gray)

                Label {
                    Text(coordinatesText)
                } icon: {
                    Image(systemName: "globe")
                }
                .font(.subheadline)
                .foregroundStyle(.gray)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            Button {
                toggleFavorite()
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(isFavorite ? .red : .gray)
                    .padding(20)
            }
        }
        .presentationBackground(.black)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func toggleFavorite() {
        if let existing = matches.first {
            context.delete(existing)
        } else {
            context.insert(FavoriteQuake(from: quake))
        }
        try? context.save()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: FavoriteQuake.self, inMemory: true)
}
