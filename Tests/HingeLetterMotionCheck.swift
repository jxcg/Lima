import Foundation

// swiftc LimaApp/HingeLetterMotion.swift Tests/HingeLetterMotionCheck.swift -o /tmp/lima-hinge-check
@main
struct HingeLetterMotionCheck {
    static func fold(speed: Double, travel: Double = 60, samplesPerSecond: Double = 60) -> HingeLetterMotion {
        var motion = HingeLetterMotion()
        precondition(!motion.update(angle: .pi, at: 0), "The initial pose must not animate")
        let duration = travel / speed
        let samples = Int(ceil(duration * samplesPerSecond))
        for step in 1...samples {
            let time = duration * Double(step) / Double(samples)
            _ = motion.update(angle: .pi - speed * time * .pi / 180, at: time)
        }
        return motion
    }

    static func main() {
        let gentle = abs(fold(speed: 5).amount)
        let moderate = abs(fold(speed: 45).amount)
        let snap = abs(fold(speed: 600).amount)
        precondition(gentle > moderate && moderate > snap, "Slower folding must produce more letter movement")
        precondition(gentle > 0.6 && (0.06...0.10).contains(snap),
                     "Quick snapping must retain a small, visible response")
        precondition(abs(fold(speed: 5, travel: 30).amount) < gentle,
                     "Continued gentle folding must build more movement")
        for rate in [30.0, 60, 120] {
            precondition(abs(abs(fold(speed: 5, samplesPerSecond: rate).amount) - gentle) < 0.01,
                         "Response must use elapsed time, not the number of sensor updates")
        }
        var motion = HingeLetterMotion()
        precondition(!motion.update(angle: 1, at: 0))
        for step in 1...8 {
            precondition(!motion.update(angle: 1 + Double(step) * 0.0001, at: Double(step) * 0.01))
        }
        precondition(motion.update(angle: 1.001, at: 0.09), "Very slow movement must survive the jitter filter")
        precondition(!motion.update(angle: 1.001, at: 0.1), "A repeated pose must not prolong motion")
        let before = motion.amount
        precondition(!motion.update(angle: 2, at: 0.08) && motion.amount == before, "Ignore out-of-order samples")
        motion.settle()
        precondition(motion.amount == 0, "Stopping must restore the exact normal placement")
        precondition(!motion.update(angle: 0.5, at: 100) && motion.amount == 0,
                     "A long stationary pause must not make the next fast snap look slow")
        precondition(motion.update(angle: 1.5, at: 100.02) && (0.06...0.10).contains(abs(motion.amount)))
        let afterSnap = motion.amount
        precondition(motion.update(angle: 1.51, at: 100.12) && abs(motion.amount - afterSnap) < 0.02,
                     "Slowing down after a snap must not reveal a large stored displacement")
        let paused = motion.amount
        precondition(!motion.update(angle: 1.51, at: 100.15) && motion.amount == paused,
                     "Stationary samples must not create delayed catch-up")
        precondition(!motion.update(angle: .nan, at: 101) && motion.amount == 0)
        precondition(!motion.update(angle: 1, at: .nan) && motion.amount == 0)
        precondition(!motion.update(angle: 1, at: 0))
        for step in 1...200 { precondition(!motion.update(angle: 1, at: Double(step) * 0.1)) }
        precondition(motion.update(angle: 2, at: 20.01) && (0.06...0.10).contains(abs(motion.amount)),
                     "A snap after a long stationary hold must keep the same restrained response")
        precondition(abs(fold(speed: 5, travel: 180).amount) <= 1, "Keep displacement bounded")
        var peakChange = 0.0
        for rate in [30.0, 60, 120] {
            var changing = HingeLetterMotion()
            var angle = Double.pi, time = 0.0
            _ = changing.update(angle: angle, at: time)
            // Slow pull, rapid movement, slow pull again, then reverse direction.
            for (speed, seconds) in [(5.0, 2.0), (600.0, 0.1), (5.0, 1.0), (-5.0, 1.0)] {
                let steps = Int((seconds * rate).rounded())
                for _ in 0..<steps {
                    let previous = changing.amount
                    time += 1 / rate
                    angle -= speed * .pi / 180 / rate
                    _ = changing.update(angle: angle, at: time)
                    let step = abs(changing.amount - previous)
                    peakChange = max(peakChange, step)
                    precondition(step * rate < 2.7,
                                 "Speed changes must blend without an abrupt jump or collapse")
                }
            }
            changing.settle()
            precondition(changing.amount == 0, "Blending must not delay the final snap back")
        }
        print(String(format: "Same 60° fold: 5°/s = %.4f, 45°/s = %.4f, 600°/s = %.6f displacement", gentle, moderate, snap))
        print(String(format: "Largest change per update across slow/fast/slow/reversing inputs: %.4f", peakChange))
        print("PASS: immediate subtle response, smooth speed changes, slow leverage, sample-rate independence and exact stop")

        var returning = fold(speed: 5)
        let displaced = returning.amount
        returning.beginReturn(at: 20)
        precondition(returning.isReturning && returning.displayedAmount(at: 20) == displaced,
                     "The return must begin at the displayed letter position")
        let halfway = abs(returning.displayedAmount(at: 20 + HingeLetterMotion.returnDuration / 2))
        precondition(halfway > 0 && halfway < abs(displaced), "The return must animate through intermediate positions")
        var previous = abs(displaced)
        for step in 0...24 {
            let value = abs(returning.displayedAmount(at: 20 + Double(step) * HingeLetterMotion.returnDuration / 24))
            precondition(value <= previous, "The return must never bounce or overshoot")
            previous = value
        }
        precondition(returning.displayedAmount(at: 20 + HingeLetterMotion.returnDuration) == 0,
                     "The return must finish exactly at the native placement")
        returning.settle()
        precondition(!returning.isReturning && returning.amount == 0, "Stop rendering when the return is done")

        var interrupted = fold(speed: 5)
        interrupted.beginReturn(at: 20)
        let beforeRepeat = interrupted.displayedAmount(at: 20.08)
        interrupted.beginReturn(at: 20.08)
        precondition(interrupted.displayedAmount(at: 20.08) == beforeRepeat,
                     "Repeated end-pose updates must not restart the return")
        precondition(!interrupted.update(angle: 1, at: 20.08), "A fresh sensor baseline must not interrupt the return")
        let visible = interrupted.displayedAmount(at: 20.10)
        precondition(interrupted.update(angle: 1.001, at: 20.10) && !interrupted.isReturning)
        precondition(abs(interrupted.amount - visible) < 0.01,
                     "Resuming hinge motion must continue from the visible position, without a jump")
        interrupted.beginReturn(at: 21)
        interrupted.reset()
        precondition(interrupted.displayedAmount(at: 21) == 0 && !interrupted.isReturning,
                     "Reduced motion and lifecycle resets must still restore the text immediately")
        print("PASS: animated return, intermediate positions, no overshoot, exact finish and interruption continuity")

        for delay in [0.0, 0.05, 0.25, 0.6, 0.9, 1.2] {
            var handoff = fold(speed: 5)
            let visible = handoff.displayedAmount(at: 20)
            handoff.holdForDisplayChange(at: 20)
            precondition(handoff.isHandingOff && !handoff.isReturning, "Hidden handoff must not animate")
            if delay < HingeLetterMotion.handoffLifetime {
                precondition(handoff.displayedAmount(at: 20 + delay) == visible, "Display switch must preserve the same deformation")
            }
            handoff.resumeAfterDisplayChange(at: 20 + delay)
            if delay < HingeLetterMotion.handoffLifetime {
                precondition(handoff.displayedAmount(at: 20 + delay) == visible, "New display must begin at the retained position")
                precondition(handoff.returnRemaining(at: 20 + delay) <= HingeLetterMotion.handoffLifetime - delay + 0.00001)
            } else {
                precondition(!handoff.isHandingOff && handoff.amount == 0, "Long backgrounding must not replay stale movement")
            }
            precondition(handoff.displayedAmount(at: 21) == 0, "Handoff must always finish within one second")
        }
        var midReturn = fold(speed: 5)
        midReturn.beginReturn(at: 20)
        let partlyReturned = midReturn.displayedAmount(at: 20.08)
        midReturn.holdForDisplayChange(at: 20.08)
        midReturn.resumeAfterDisplayChange(at: 20.4)
        precondition(abs(midReturn.displayedAmount(at: 20.4) - partlyReturned) < 0.000001,
                     "Handoff must preserve an in-flight return's position")
        precondition(midReturn.returnRemaining(at: 20.4) < HingeLetterMotion.returnDuration + 0.1,
                     "An interrupted return must keep its remaining duration, rather than restarting")
        midReturn.holdForDisplayChange(at: 20.6)
        midReturn.resumeAfterDisplayChange(at: 20.9)
        precondition(midReturn.displayedAmount(at: 21.08) == 0, "Repeated resize events cannot extend the original handoff deadline")
        for destination in [90.0, 140.0] {
            var resumed = fold(speed: 5)
            resumed.settle()
            let start = 120.0 * Double.pi / 180
            precondition(!resumed.update(angle: start, at: 30) && resumed.amount == 0)
            for step in 1...120 {
                let angle = (120 + (destination - 120) * Double(step) / 120) * Double.pi / 180
                _ = resumed.update(angle: angle, at: 30 + Double(step) / 30)
            }
            precondition(abs(resumed.amount) > 0.05, "Movement after resting at 120° must respond in either direction")
            precondition((resumed.amount > 0) == (destination > 120), "New movement must use the new resting pose")
        }
        print("PASS: display delays 0–1.2s, retained return progress, bounded lifetime and fresh movement from 120° to 90°/140°")

        // Match the view's callbacks with scenePhase remaining active throughout the switch.
        var closedFirst = fold(speed: 5)
        let beforeClosed = closedFirst.amount
        closedFirst.holdForDisplayChange(at: 20) // Closed: capture, do not resume yet.
        precondition(closedFirst.handoffFallbackDelay(at: 20) == HingeLetterMotion.handoffLifetime)
        precondition(!closedFirst.isReturning && closedFirst.displayedAmount(at: 20.6) == beforeClosed,
                     "A delayed destination layout must not lose the deformation before it appears")
        closedFirst.holdForDisplayChange(at: 20.6) // Destination geometry acknowledges the handoff.
        closedFirst.resumeAfterDisplayChange(at: 20.6)
        precondition(closedFirst.displayedAmount(at: 20.6) == beforeClosed)
        precondition(closedFirst.displayedAmount(at: 21) == 0)

        var geometryFirst = fold(speed: 5)
        geometryFirst.holdForDisplayChange(at: 20) // Trait/layout update arrives first.
        geometryFirst.resumeAfterDisplayChange(at: 20)
        let duringReturn = geometryFirst.displayedAmount(at: 20.2)
        if !geometryFirst.isHandingOff { geometryFirst.holdForDisplayChange(at: 20.2) } // Closed callback.
        precondition(geometryFirst.displayedAmount(at: 20.2) == duringReturn,
                     "Closed after geometry must not restart or freeze the return")
        precondition(geometryFirst.displayedAmount(at: 20.36) == 0)
        var noGeometrySignal = fold(speed: 5)
        noGeometrySignal.holdForDisplayChange(at: 20)
        let fallback = 20 + noGeometrySignal.handoffFallbackDelay(at: 20)
        precondition(noGeometrySignal.displayedAmount(at: fallback - 0.001) == noGeometrySignal.amount)
        noGeometrySignal.settle() // The pending timeout only expires; it cannot start a hidden return.
        precondition(noGeometrySignal.displayedAmount(at: 21) == 0,
                     "Missing destination callbacks must discard stale state without an animation loop")
        var lateGeometry = fold(speed: 5)
        let lateVisible = lateGeometry.amount
        lateGeometry.holdForDisplayChange(at: 20)
        precondition(lateGeometry.handoffFallbackDelay(at: 20) > 0.9,
                     "The timeout must not animate before a 900ms destination switch")
        lateGeometry.holdForDisplayChange(at: 20.9)
        lateGeometry.resumeAfterDisplayChange(at: 20.9)
        precondition(lateGeometry.displayedAmount(at: 20.9) == lateVisible)
        precondition(lateGeometry.displayedAmount(at: 21) == 0)
        var inputBeforeActivation = fold(speed: 5)
        inputBeforeActivation.holdForDisplayChange(at: 20)
        precondition(!inputBeforeActivation.update(angle: 2, at: 21.2) && inputBeforeActivation.amount == 0,
                     "A fresh hinge sample before activation must not revive an expired handoff")
        precondition(inputBeforeActivation.update(angle: 2.001, at: 21.22) && abs(inputBeforeActivation.amount) < 0.01)
        print("PASS: closed-before-geometry, geometry-before-closed and missing-geometry callback orders")
    }
}
