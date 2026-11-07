import SwiftUI

// Keep the sensor bookkeeping separate from drawing, so pauses and jitter are testable.
nonisolated struct HingeLetterMotion {
    static let quietInterval = 0.18
    static let settleDelay: Duration = .seconds(quietInterval)
    static let returnDuration = 0.24
    static let handoffLifetime = 1.0
    private static let handoffHold = 0.12
    private var lastAngle: Double?
    private var lastMovementTime: TimeInterval?
    private var lastSampleAngle: Double?
    private var lastSampleTime: TimeInterval?
    private var directTravel = 0.0
    private var slowTravel = 0.0
    private var extraAmount = 0.0
    private var returnStarted: TimeInterval?
    private var returnLength = Self.returnDuration
    private var handoffStarted: TimeInterval?
    private(set) var amount = 0.0

    var isReturning: Bool { returnStarted != nil }
    var isHandingOff: Bool { handoffStarted != nil }

    // Use the same curve for every letter and the dot, ending exactly at the native layout.
    func displayedAmount(at timestamp: TimeInterval) -> Double {
        if let handoffStarted, timestamp >= handoffStarted + Self.handoffLifetime { return 0 }
        return amount * returnFactor(at: timestamp)
    }

    private func returnFactor(at timestamp: TimeInterval) -> Double {
        guard let started = returnStarted else { return 1 }
        if timestamp >= started + returnLength { return 0 }
        let remaining = 1 - max(0, (timestamp - started) / returnLength)
        return remaining * remaining * remaining
    }

    mutating func beginReturn(at timestamp: TimeInterval) {
        guard !isReturning, !isHandingOff, amount != 0, timestamp.isFinite else { return }
        returnLength = Self.returnDuration
        returnStarted = timestamp
        clearSamples()
    }

    func returnRemaining(at timestamp: TimeInterval) -> TimeInterval {
        guard let returnStarted else { return 0 }
        return max(0, returnStarted + returnLength - timestamp)
    }

    func handoffFallbackDelay(at timestamp: TimeInterval) -> TimeInterval {
        guard let handoffStarted else { return 0 }
        return max(0, handoffStarted + Self.handoffLifetime - timestamp)
    }

    // Duo resizes the same scene. Freeze only its visible deformation, with no disk storage.
    mutating func holdForDisplayChange(at timestamp: TimeInterval) {
        guard timestamp.isFinite, displayedAmount(at: timestamp) != 0 else { reset(); return }
        let remaining = returnStarted.map { max(0, $0 + returnLength - max(timestamp, $0)) } ?? returnLength
        let factor = returnFactor(at: timestamp)
        directTravel *= factor
        slowTravel *= factor
        extraAmount *= factor
        amount *= factor
        returnLength = remaining
        returnStarted = nil
        handoffStarted = handoffStarted ?? timestamp
        clearSamples()
    }

    mutating func resumeAfterDisplayChange(at timestamp: TimeInterval) {
        guard let captured = handoffStarted, !isReturning else { return }
        let budget = captured + Self.handoffLifetime - timestamp
        guard timestamp.isFinite, timestamp >= captured, budget > 0 else { reset(); return }
        // Leave a brief visible glimpse, but never replay stale movement after a long delay.
        let hold = min(Self.handoffHold, max(0, budget - returnLength))
        returnLength = min(returnLength, budget - hold)
        returnStarted = timestamp + hold
    }

    private mutating func clearSamples() {
        lastAngle = nil
        lastMovementTime = nil
        lastSampleAngle = nil
        lastSampleTime = nil
    }

    // Returns true only for a meaningful movement, not repeated samples or sensor noise.
    mutating func update(angle: Double, at timestamp: TimeInterval) -> Bool {
        guard angle.isFinite, timestamp.isFinite else { reset(); return false }
        if let handoffStarted, timestamp >= handoffStarted + Self.handoffLifetime { reset() }
        if let lastSampleTime, timestamp <= lastSampleTime { return false }
        let angle = min(max(angle, 0), .pi)
        let followsPause = lastSampleTime.map { timestamp - $0 > Self.quietInterval } ?? true
        let sampleSpeed: Double
        if let lastSampleAngle, let lastSampleTime {
            sampleSpeed = abs(angle - lastSampleAngle) / (timestamp - lastSampleTime)
        } else { sampleSpeed = 0 }
        lastSampleAngle = angle
        lastSampleTime = timestamp
        guard !followsPause, let previous = lastAngle, let previousTime = lastMovementTime else {
            lastAngle = angle
            lastMovementTime = timestamp
            // Establish a fresh sensor baseline without interrupting an in-flight return.
            return false
        }
        let change = angle - previous
        // Small changes accumulate, so a gentle fold is not mistaken for a stationary hinge.
        guard abs(change) >= .pi / 3600 else { return false }
        if isReturning || isHandingOff {
            // Resume from the position on screen, rather than jumping to the old motion state.
            let factor = returnFactor(at: timestamp)
            directTravel *= factor
            slowTravel *= factor
            extraAmount *= factor
            returnStarted = nil
            handoffStarted = nil
            returnLength = Self.returnDuration
        }
        // The latest sample catches a snap immediately, even after repeated stationary readings.
        let elapsed = timestamp - previousTime
        let speed = max(sampleSpeed, abs(change) / elapsed)
        let relativeSpeed = speed / (.pi / 4)
        let leverage = 1 / (1 + relativeSpeed * relativeSpeed)
        // A small direct response keeps the lettering connected to the hand at every speed.
        directTravel = min(max(directTravel + change / (.pi / 2), -1), 1)
        // Slow travel builds extra displacement; a quick fold cannot bank a large extra offset.
        slowTravel = min(max(slowTravel + change / (.pi / 2) * leverage, -1), 1)
        let targetExtra = slowTravel * leverage
        // Blend the extra response over time, limiting how abruptly a speed change can move text.
        let blend = 1 - exp(-elapsed / 0.16)
        let extraStep = (targetExtra - extraAmount) * blend
        let maximumStep = elapsed * 1.8
        extraAmount += min(max(extraStep, -maximumStep), maximumStep)
        amount = directTravel * 0.12 + extraAmount * 0.88
        lastAngle = angle
        lastMovementTime = timestamp
        return true
    }

    mutating func settle() {
        reset()
    }

    mutating func reset() { self = Self() }
}

// Transform the drawn letters, leaving SwiftUI's wrapping, spacing and accessibility intact.
nonisolated struct HingeLetterRenderer: TextRenderer {
    var amount: Double
    var maximumDisplacement: CGFloat
    var seed = 0
    // Separate wordmark letters share one centre; ordinary text uses each laid-out line.
    var outwardPosition: Double? = nil

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard amount != 0 else {
            for line in layout { context.draw(line) }
            return
        }
        var index = seed
        let travel = maximumDisplacement * amount
        let spread = maximumDisplacement * abs(amount)
        for line in layout {
            let lineBounds = line.typographicBounds.rect
            for run in line {
                for letter in run {
                    let phase = Double(index) * 0.65 + 0.55
                    let bounds = letter.typographicBounds.rect
                    let position = outwardPosition.map { CGFloat($0) }
                        ?? (bounds.midX - lineBounds.midX) / max(lineBounds.width / 2, 1)
                    var drawing = context
                    // Spread out from the centre, with a small flowing drift that keeps letters in order.
                    drawing.translateBy(x: bounds.midX + position * spread + sin(phase) * travel * 0.12,
                                        y: bounds.midY + cos(phase * 1.3) * travel * 0.28)
                    drawing.rotate(by: .degrees(sin(phase * 0.9) * 3 * amount))
                    drawing.translateBy(x: -bounds.midX, y: -bounds.midY)
                    drawing.draw(letter)
                    index += 1
                }
            }
        }
    }
}
