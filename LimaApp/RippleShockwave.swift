import SwiftUI

// A barely visible pressure edge follows the refraction front, then disappears.
struct RippleShockwave: View {
    let elapsed: Double
    let rippleDuration: Double
    let waveWidth: CGFloat
    static let lifetime = 0.28

    var body: some View {
        let progress = min(max(elapsed / Self.lifetime, 0), 1)
        let fade = 1 - progress
        let attack = min(max(elapsed / 0.035, 0), 1)
        let radius = max(0, elapsed / rippleDuration) * waveWidth * 16
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.018), location: 0.35),
                    .init(color: .white.opacity(0.022), location: 0.65),
                    .init(color: .clear, location: 1)
                ],
                center: .center,
                startRadius: max(0, radius - waveWidth * 0.08),
                endRadius: max(radius, 0.001)
            ))
            .frame(width: radius * 2, height: radius * 2)
            .opacity(attack * fade * fade)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
