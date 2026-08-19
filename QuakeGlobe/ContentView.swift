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

// MARK: - Pedido de voo (fly-to)

struct FlyRequest {
    let id = UUID()          // token: cada pedido voa uma única vez
    let quake: Earthquake
    let arc: Bool            // true = vai-e-vem (favoritos); false = aproxima direto (marcador)
}

// MARK: - Pedido de zoom externo (fechar card = 50%)

struct ZoomRequest {
    let id = UUID()
    let distance: Float
}

// MARK: - SCNView que sente o dedo encostar (cancela voo no touch-down)

final class GlobeSCNView: SCNView {
    var onTouchDown: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchDown?()
        super.touchesBegan(touches, with: event)
    }
}

// MARK: - Elemento de VoiceOver ativável

final class QuakeAccessibilityElement: UIAccessibilityElement {
    var onActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

// MARK: - RNG com seed (céu determinístico, mesmo céu em todo launch)

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct ContentView: View {
    @State private var earthquakes: [Earthquake] = []
    @State private var selectedQuake: Earthquake?
    @State private var loadState: LoadState = .loading
    @State private var lastLoad: Date?
    @State private var showFavorites = false
    @State private var flyRequest: FlyRequest?
    @State private var zoomRequest: ZoomRequest?
    @State private var suppressDismissZoom = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @Query private var favorites: [FavoriteQuake]
    @Environment(\.scenePhase) private var scenePhase

    /// Intervalo do auto-refresh. 300s em produção; baixe pra testar.
    private let refreshInterval: TimeInterval = 300

    /// Régua de zoom: 0% = 4.0 (globo mínimo), 50% = 2.85, 100% = 1.7 (pouso).
    /// REGRA: 2.85 é o recuo de dismiss; 4.0 é SOMENTE cancel de voo.
    private let midZoomDistance: Float = 2.85

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GlobeView(
                earthquakes: earthquakes,
                flyRequest: flyRequest,
                zoomRequest: zoomRequest,
                onSelect: { quake in
                    if selectedQuake != nil {
                        // REGRA: marcador com card aberto = fecha + 50%
                        closeCard()
                    } else {
                        // REGRA: marcador direto = aproxima sem recuo
                        flyRequest = FlyRequest(quake: quake, arc: false)
                    }
                },
                onFlyComplete: { quake in
                    selectedQuake = quake      // card abre no pouso
                },
                onEmptyTap: {
                    // REGRA: fora do card = fecha + 50%
                    if selectedQuake != nil {
                        closeCard()
                    }
                }
            )
            .ignoresSafeArea()
            .background(Color.black)
            .overlay { statusOverlay }

            // Botões sempre vivos e visíveis
            VStack(alignment: .trailing, spacing: 12) {
                hapticsButton
                favoritesButton
            }
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
        .sheet(item: selectedQuakeBinding) { quake in
            QuakeDetailSheet(quake: quake)
                .onAppear {
                    HapticEngine.shared.play(magnitude: quake.magnitude, enabled: hapticsEnabled)
                }
                // Fundo interativo: o globo e os botões respondem com o card aberto
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesListView { quake in
                showFavorites = false
                flyRequest = FlyRequest(quake: quake, arc: true)   // REGRA: favoritos = vai-e-vem
            }
            .presentationBackground(.black)
            .presentationDetents([.medium, .large])
            // Arrasto rola a lista primeiro; o sheet só expande pelo indicador.
            .presentationContentInteraction(.scrolls)
        }
    }

    /// REGRA: fecha o card E aplica a recuadinha de 50%.
    /// Nunca usa 4.0: o globo mínimo é exclusividade do cancel de voo.
    private func closeCard() {
        selectedQuake = nil
        zoomRequest = ZoomRequest(distance: midZoomDistance)
    }

    /// Binding que detecta o fechamento do sheet (swipe). O coração
    /// suprime o zoom: ele espera o próximo favorito pra recuar no voo.
    private var selectedQuakeBinding: Binding<Earthquake?> {
        Binding(
            get: { selectedQuake },
            set: { newValue in
                let wasOpen = selectedQuake != nil
                selectedQuake = newValue
                if wasOpen && newValue == nil {
                    if suppressDismissZoom {
                        suppressDismissZoom = false
                    } else {
                        zoomRequest = ZoomRequest(distance: midZoomDistance)
                    }
                }
            }
        )
    }

    // MARK: Botão de haptics

    private var hapticsButton: some View {
        Button {
            hapticsEnabled.toggle()
        } label: {
            Image(systemName: hapticsEnabled ? "waveform" : "waveform.slash")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(hapticsEnabled ? "Haptics enabled" : "Haptics disabled")
        .accessibilityHint("Toggles vibration feedback.")
    }

    // MARK: Botão de favoritos

    private var favoritesButton: some View {
        Button {
            if selectedQuake != nil {
                // REGRA: coração com card aberto = fecha SEM recuar + favoritos
                suppressDismissZoom = true
                selectedQuake = nil
                Task {
                    try? await Task.sleep(for: .seconds(0.35))
                    showFavorites = true
                }
            } else {
                showFavorites = true
            }
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
        .accessibilityLabel("Favorites")
        .accessibilityHint("Shows your saved earthquakes.")
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
        let previousCount = earthquakes.count

        if earthquakes.isEmpty {
            loadState = .loading
        }
        do {
            let newEarthquakes = try await EarthquakeService().fetchRecent()
            earthquakes = newEarthquakes
            loadState = .loaded
            lastLoad = Date()

            // Haptic no terremoto mais forte do refresh (se houver novos)
            if newEarthquakes.count > previousCount, let strongest = newEarthquakes.max(by: { $0.magnitude < $1.magnitude }) {
                HapticEngine.shared.play(magnitude: strongest.magnitude, enabled: hapticsEnabled)
            }

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
    let flyRequest: FlyRequest?
    let zoomRequest: ZoomRequest?
    let onSelect: (Earthquake) -> Void
    let onFlyComplete: (Earthquake) -> Void
    let onEmptyTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = GlobeSCNView()
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

        // Céu estrelado procedural: esfera invertida ao fundo, parallax de 10%
        let stars = SCNSphere(radius: 40)
        stars.segmentCount = 48

        let starMaterial = SCNMaterial()
        starMaterial.diffuse.contents = UIColor.black
        starMaterial.diffuse.mipFilter = .linear   // sem cintilar ao girar
        starMaterial.lightingModel = .constant
        starMaterial.cullMode = .front             // renderiza o lado de dentro
        stars.materials = [starMaterial]

        let starNode = SCNNode(geometry: stars)
        starNode.name = "stars"
        scene.rootNode.addChildNode(starNode)

        // Container que gira (Terra + nuvens + marcadores)
        let globeNode = SCNNode()
        globeNode.name = "globe"
        globeNode.eulerAngles.y = Float(75.0 * .pi / 180)
        scene.rootNode.addChildNode(globeNode)

        // Terra (nasce preta; textura preparada entra em seguida)
        let earth = SCNSphere(radius: 1.0)
        earth.segmentCount = 96

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.black
        material.diffuse.mipFilter = .linear
        earth.materials = [material]

        let earthNode = SCNNode(geometry: earth)
        earthNode.name = "earth"
        globeNode.addChildNode(earthNode)

        // Nuvens (preto no blend aditivo = invisível até preparar)
        let clouds = SCNSphere(radius: 1.06)
        clouds.segmentCount = 96

        let cloudMaterial = SCNMaterial()
        cloudMaterial.diffuse.contents = UIColor.black
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

        // Decode fora da main + céu procedural 4K + upload antecipado pra GPU.
        Task {
            async let earthImage: UIImage? = Self.preparedImage("earth_texture")
            async let cloudsImage: UIImage? = Self.preparedImage("earth_clouds")
            async let starsImage: UIImage? = Self.starfieldImage()
            let (preparedEarth, preparedClouds, preparedStars) = await (earthImage, cloudsImage, starsImage)
            if let preparedEarth { material.diffuse.contents = preparedEarth }
            if let preparedClouds { cloudMaterial.diffuse.contents = preparedClouds }
            if let preparedStars { starMaterial.diffuse.contents = preparedStars }

            // Pré-carrega texturas e pipelines Metal antes do primeiro render.
            scnView.prepare([scene]) { _ in }
        }

        // Referências + display link (inércia, zoom suave e fly-to)
        context.coordinator.scnView = scnView
        context.coordinator.globeNode = globeNode
        context.coordinator.cameraNode = cameraNode
        context.coordinator.starNode = starNode
        context.coordinator.startDisplayLink()

        // REGRA: touch-down durante VOO = cancela e recua ao globo mínimo.
        // Fora de voo, este handler não faz nada.
        scnView.onTouchDown = { context.coordinator.cancelFly() }

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

    /// Decode assíncrono: a imagem chega pronta pra GPU, sem travar a main.
    private static func preparedImage(_ name: String) async -> UIImage? {
        await UIImage(named: name)?.byPreparingForDisplay()
    }

    /// Céu procedural 4K: estrelas REDONDAS e nítidas, glow em gradiente
    /// radial, três camadas de profundidade, wrap horizontal sem emenda,
    /// seed fixa. Sem asset, sem Single Scale.
    private static func starfieldImage() async -> UIImage? {
        let w: CGFloat = 4096
        let h: CGFloat = 2048
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1                            // pixels reais, sem scale de tela

        let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
            let cg = ctx.cgContext
            var rng = SeededGenerator(seed: 42)

            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))

            // Estrela redonda: núcleo em elipse AA + halo em gradiente radial
            func drawStar(x: CGFloat, _ y: CGFloat, radius: CGFloat, alpha: CGFloat, color: UIColor, glow: CGFloat) {
                if glow > 0 {
                    let colors = [
                        color.withAlphaComponent(alpha * 0.35).cgColor,
                        color.withAlphaComponent(0).cgColor
                    ] as CFArray
                    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                 colors: colors,
                                                 locations: [0, 1]) {
                        cg.drawRadialGradient(gradient,
                                              startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                              endCenter: CGPoint(x: x, y: y), endRadius: radius * glow,
                                              options: [])
                    }
                }
                cg.setFillColor(color.withAlphaComponent(alpha).cgColor)
                cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                          width: radius * 2, height: radius * 2))
            }

            // Wrap horizontal: desenha em x, x-w, x+w = emenda invisível
            func drawWrapped(x: CGFloat, _ y: CGFloat, radius: CGFloat, alpha: CGFloat, color: UIColor, glow: CGFloat) {
                for dx in [-w, 0, w] {
                    drawStar(x: x + dx, y, radius: radius, alpha: alpha, color: color, glow: glow)
                }
            }

            let palette: [UIColor] = [
                .white,
                UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 1),   // azulada
                UIColor(red: 1.0, green: 0.90, blue: 0.75, alpha: 1)    // quente
            ]

            // Camada 1: fundo profundo, ~1400 estrelas pequenas e nítidas
            for _ in 0..<1400 {
                drawWrapped(x: .random(in: 0..<w, using: &rng),
                            .random(in: 0..<h, using: &rng),
                            radius: .random(in: 0.7...1.6, using: &rng),
                            alpha: .random(in: 0.15...0.7, using: &rng),
                            color: palette.randomElement(using: &rng)!,
                            glow: 0)
            }

            // Camada 2: ~140 estrelas médias com halo sutil
            for _ in 0..<140 {
                drawWrapped(x: .random(in: 0..<w, using: &rng),
                            .random(in: 0..<h, using: &rng),
                            radius: .random(in: 1.8...2.8, using: &rng),
                            alpha: .random(in: 0.6...0.95, using: &rng),
                            color: palette.randomElement(using: &rng)!,
                            glow: 3)
            }

            // Camada 3: ~24 brilhantes com glow redondo
            for _ in 0..<24 {
                drawWrapped(x: .random(in: 0..<w, using: &rng),
                            .random(in: 0..<h, using: &rng),
                            radius: .random(in: 3.0...4.2, using: &rng),
                            alpha: 1,
                            color: palette.randomElement(using: &rng)!,
                            glow: 7)
            }
        }
        return await image.byPreparingForDisplay()
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        guard let earthNode = uiView.scene?.rootNode
            .childNode(withName: "earth", recursively: true) else { return }
        plotMarkers(on: earthNode)
        rebuildAccessibility(on: uiView)

        // Pedido novo de fly-to? Decola.
        if let request = flyRequest, request.id != context.coordinator.lastFlyID {
            context.coordinator.lastFlyID = request.id
            let quake = request.quake
            context.coordinator.fly(to: quake, withArc: request.arc) {
                self.onFlyComplete(quake)
            }
        }

        // Pedido novo de zoom externo? Aplica com animação suave.
        if let request = zoomRequest, request.id != context.coordinator.lastZoomID {
            context.coordinator.lastZoomID = request.id
            context.coordinator.setTargetDistance(request.distance)
        }
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

            // Proxy de toque: invisível, ~2x maior, dedo não erra
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

    // MARK: VoiceOver (lista de áudio com ordem estável)

    private func rebuildAccessibility(on scnView: SCNView) {
        // VoiceOver ordena a navegação PELO FRAME. Frames idênticos = ordem
        // instável (repete/trava). Fatias virtuais distintas = navegação
        // estável, mais fortes primeiro, imune à rotação do globo.
        let sorted = earthquakes.sorted { $0.magnitude > $1.magnitude }
        let sliceHeight = scnView.bounds.height / CGFloat(max(sorted.count, 1))

        let elements: [UIAccessibilityElement] = sorted.enumerated().map { index, quake in
            let element = QuakeAccessibilityElement(accessibilityContainer: scnView)
            element.accessibilityLabel = accessibilityLabel(for: quake)
            element.accessibilityHint = "Double tap to open details."
            element.accessibilityTraits = .button
            element.accessibilityFrameInContainerSpace = CGRect(
                x: 0,
                y: CGFloat(index) * sliceHeight,
                width: scnView.bounds.width,
                height: sliceHeight
            )
            element.onActivate = { onSelect(quake) }
            return element
        }
        scnView.accessibilityElements = elements
    }

    private func accessibilityLabel(for quake: Earthquake) -> String {
        var parts = [
            "Magnitude \(String(format: "%.1f", quake.magnitude))",
            quake.severity.label
        ]
        if let place = quake.properties.place {
            parts.append(place)
        }
        if let date = quake.date {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: ", ")
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
        var starNode: SCNNode?

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

        // Fly-to
        var lastFlyID: UUID?
        var lastZoomID: UUID?
        private var flying = false
        private var flyWithArc = false
        private var flyElapsed: Float = 0
        private let flyDuration: Float = 2.2    // cinematográfico e cancelável
        private var flyFrom: (yaw: Float, pitch: Float, dist: Float) = (0, 0, 3)
        private var flyTo: (yaw: Float, pitch: Float, dist: Float) = (0, 0, 1.7)
        private var flyCompletion: (() -> Void)?
        private var swallowNextTap = false

        // Recuo animado (cancel de voo, dismiss de card): smoothstep, assenta suave
        private var zoomAnim: (from: Float, to: Float, elapsed: Float, duration: Float)?

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

        func setTargetDistance(_ distance: Float) {
            animateZoom(to: distance, duration: 0.8)
        }

        private func animateZoom(to target: Float, duration: Float) {
            let clamped = min(max(target, minDistance), maxDistance)
            zoomAnim = (currentDistance, clamped, 0, duration)
        }

        private func applyOrientation() {
            globeNode?.simdOrientation =
                simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0)) *
                simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))

            // Parallax: o céu acompanha a 10% da velocidade do globo
            starNode?.eulerAngles = SCNVector3(pitch * 0.1, yaw * 0.1, 0)
        }

        /// Fly-to: centrar longitude = yaw oposto; latitude com respiro
        /// calibrado (0.22 rad no pouso = ~12% da tela acima do centro).
        /// arc = true (favoritos): vai-e-vem com recuo no meio.
        /// arc = false (marcador): aproxima direto de onde a câmera estiver.
        func fly(to quake: Earthquake, withArc: Bool, completion: @escaping () -> Void) {
            inertiaActive = false
            flying = true
            flyWithArc = withArc
            flyElapsed = 0
            swallowNextTap = false
            zoomAnim = nil
            flyFrom = (yaw, pitch, currentDistance)

            let targetYaw = -Float(quake.longitude * .pi / 180)
            var delta = targetYaw - yaw
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }

            let latRad = Float(quake.latitude * .pi / 180)
            let targetPitch = min(max(latRad - 0.22, -1.1), 1.1)
            flyTo = (yaw + delta, targetPitch, 1.7)
            flyCompletion = completion
        }

        /// REGRA: ÚNICO caminho pro globo mínimo (4.0).
        /// Só executa se estiver voando; touch-down fora de voo é no-op.
        func cancelFly() {
            guard flying else { return }
            flying = false
            flyCompletion = nil
            swallowNextTap = true
            animateZoom(to: maxDistance, duration: 1.0)
        }

        @objc private func tick(_ link: CADisplayLink) {
            let dt = Float(link.targetTimestamp - link.timestamp)

            // Fly-to: interpolação smoothstep (acelera, cruza, assenta)
            if flying {
                flyElapsed += dt
                let t = min(flyElapsed / flyDuration, 1)
                let e = t * t * (3 - 2 * t)

                yaw = flyFrom.yaw + (flyTo.yaw - flyFrom.yaw) * e
                pitch = flyFrom.pitch + (flyTo.pitch - flyFrom.pitch) * e

                if flyWithArc {
                    // Vai-e-vem: Bezier que recua até o meio da faixa no meio
                    // do voo e reaproxima até o pouso em 1.7.
                    let midPull = (minDistance + maxDistance) / 2
                    let c = min((4 * midPull - flyFrom.dist - flyTo.dist) / 2, maxDistance)
                    let u = 1 - t
                    currentDistance = u * u * flyFrom.dist + 2 * u * t * c + t * t * flyTo.dist
                } else {
                    // Aproximação direta: chega de onde estiver, como pouso de voo
                    currentDistance = flyFrom.dist + (flyTo.dist - flyFrom.dist) * e
                }

                cameraNode?.position = SCNVector3(0, 0, currentDistance)
                applyOrientation()

                if t >= 1 {
                    flying = false
                    targetDistance = currentDistance
                    flyCompletion?()
                    flyCompletion = nil
                }
            } else if inertiaActive {
                // Inércia com decay exponencial
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

            // Zoom: recuo animado (smoothstep) tem prioridade;
            // senão, lerp do pinch.
            if !flying {
                if var za = zoomAnim {
                    za.elapsed += dt
                    let t = min(za.elapsed / za.duration, 1)
                    let e = t * t * (3 - 2 * t)
                    currentDistance = za.from + (za.to - za.from) * e
                    cameraNode?.position = SCNVector3(0, 0, currentDistance)
                    if t >= 1 {
                        zoomAnim = nil
                        targetDistance = za.to
                    } else {
                        zoomAnim = za
                    }
                } else if abs(targetDistance - currentDistance) > 0.001 {
                    currentDistance += (targetDistance - currentDistance) * min(1, dt * 12)
                    cameraNode?.position = SCNVector3(0, 0, currentDistance)
                }
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.view != nil else { return }

            switch gesture.state {
            case .began:
                // Arrasto durante voo também cancela (único caso que vai a 4.0)
                cancelFly()
                swallowNextTap = false
                inertiaActive = false
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
            // Toque que cancelou o voo não abre card
            if swallowNextTap {
                swallowNextTap = false
                return
            }

            // Segurança extra: se por algum motivo ainda estiver voando
            if flying {
                cancelFly()
                return
            }

            guard let scnView = scnView else { return }
            let point = gesture.location(in: scnView)

            // Só os proxies (máscara 2) participam: nuvem e Terra não interferem.
            let options: [SCNHitTestOption: Any] = [
                SCNHitTestOption.categoryBitMask: 2,
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue
            ]

            guard let hit = scnView.hitTest(point, options: options).first,
                  let name = hit.node.name,
                  let quake = parent.earthquakes.first(where: { name == "quake_\($0.id)" })
            else {
                parent.onEmptyTap()
                return
            }

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
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
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
