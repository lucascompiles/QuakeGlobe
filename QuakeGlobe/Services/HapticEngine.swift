//
//  HapticEngine.swift
//  QuakeGlobe
//
//  Created by Lucas on 19/08/26.
//

import CoreHaptics

final class HapticEngine {
    static let shared = HapticEngine()

    private var engine: CHHapticEngine?
    private var isStarted = false

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()

            // Auto-recupera se o sistema derrubar o engine (background, etc.)
            engine.resetHandler = { [weak self] in
                guard let self else { return }
                try? self.engine?.start()
                self.isStarted = true
            }
            engine.stoppedHandler = { [weak self] _ in
                self?.isStarted = false
            }

            try engine.start()
            self.engine = engine
            isStarted = true
        } catch {
            print("⚠️ HapticEngine failed to start: \(error)")
        }
    }

    /// Escada tátil 2.5 a 10.0 com assinaturas estruturais no topo:
    /// M2.5-6  = tick a trovão (escada aprovada)
    /// M6-8    = trovão mais longo
    /// M8      = choque + pausa + réplica (2 ondas)
    /// M9      = + terceiro tremor (3 ondas, cascata)
    /// M10     = CRESCENDO (o único que sobe) + cascata completa
    func play(magnitude: Double, enabled: Bool) {
        guard enabled, isStarted, let engine else { return }

        // Escada base 2.5-6.0
        let n = Float(max(0, min(1, (magnitude - 2.5) / 3.5)))
        // Headroom 6.0-8.0 (duração); acima de 8, estrutura assume
        let extra = Float(max(0, min(1, (magnitude - 6.0) / 2.0)))

        let intensity = 0.45 + n * 0.55
        let sharpness = max(0.25, 0.85 - n * 0.6)

        var events: [CHHapticEvent] = []

        // CHOQUE PRINCIPAL: pulsos decaindo + rumble grave
        let pulses = 1 + Int(n * 4) + Int(extra * 2)
        for i in 0..<pulses {
            let decay = pow(0.75, Float(i))
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * decay),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: TimeInterval(Double(i) * 0.09)
            ))
        }

        if n > 0.4 {
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
                ],
                relativeTime: 0,
                duration: 0.25 + TimeInterval(n) * 0.45 + TimeInterval(extra) * 0.6
            ))
        }

        var cursor = 0.25 + TimeInterval(n) * 0.45 + TimeInterval(extra) * 0.6

        // M10: CRESCENDO por cima do choque (o único padrão que SOBE)
        if magnitude >= 10.0 {
            let steps: [(Float, TimeInterval)] = [(0.5, 0.0), (0.8, 0.6), (1.0, 1.2)]
            for (value, start) in steps {
                events.append(CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: value),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
                    ],
                    relativeTime: start,
                    duration: 0.6
                ))
            }
            // Pico: pulso máximo no topo do crescendo
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ],
                relativeTime: 1.8
            ))
            cursor = 1.9
        }

        // RÉPLICA (M8+): pausa + rumble + pulsos
        if magnitude >= 8.0 {
            let aftershockStart = cursor + 0.35
            let power: Float = magnitude >= 9.0 ? 0.85 : 0.7
            let length: TimeInterval = magnitude >= 9.0 ? 1.2 : 0.9

            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: power),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
                ],
                relativeTime: aftershockStart,
                duration: length
            ))
            for i in 0..<2 {
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: power * pow(0.75, Float(i))),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                    ],
                    relativeTime: aftershockStart + TimeInterval(Double(i) * 0.1)
                ))
            }
            cursor = aftershockStart + length

            // TERCEIRO TREMOR (M9+): a cascata que o M8 não tem
            if magnitude >= 9.0 {
                let thirdStart = cursor + 0.3
                events.append(CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: thirdStart,
                    duration: 0.6
                ))
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35)
                    ],
                    relativeTime: thirdStart
                ))
            }
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("⚠️ Haptic playback failed: \(error)")
        }
    }
}
