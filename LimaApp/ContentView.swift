import SwiftUI

// The placeholder first screen. Phase 1 replaces it with the test bench (#1).
// `body` describes what the screen shows. SwiftUI redraws it when its data changes.
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var settled = false
    @State private var ripples: [Ripple] = []
    @State private var pendingOpeningReveal = false
    @ScaledMetric(relativeTo: .largeTitle) private var dotSize = 6
    // Follow the lettering's Dynamic Type scale, rather than the window dimensions.
    @ScaledMetric(relativeTo: .largeTitle) private var rippleWidth = 54.0

    private var motionDisabled: Bool { reduceMotion || lowPowerMode }

    var body: some View {
        GeometryReader { geometry in
            let reserved = reservedFrames(in: geometry)
            let divisions = geometry.reservedRegions(kind: .division, options: .includeInactive,
                                                      layoutDirectionBehavior: .fixed).map(reservedFrame)
            let placement = AvailableRegion.welcome(
                in: CGRect(origin: .zero, size: geometry.size), excluding: reserved,
                divisions: divisions, preferRightHandPane: horizontalSizeClass == .regular,
                minimumPaneWidth: rippleWidth * 5
            )
            let available = placement.frame
            TimelineView(.animation(paused: ripples.isEmpty || motionDisabled || scenePhase != .active)) { timeline in
                let values = rippleValues(at: timeline.date)
                let enabled = !ripples.isEmpty && !motionDisabled && scenePhase == .active
                let canvasSize = geometry.size
                let waveWidth = rippleWidth
                let background = Color(uiColor: .systemBackground)
                ScrollView {
                    VStack(spacing: 16) {
                        wordmark
                            .accessibilityHint(motionDisabled ? "" : "Plays a brief ripple.")
                            .accessibilityAction {
                                addRipple(
                                    at: CGPoint(x: available.midX, y: available.midY),
                                    in: geometry.size
                                )
                            }
                        Text("Dictation clean-up keyboard")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .visualEffect { effect, contentGeometry in
                        // Refract only the content, using the canvas as our common ruler.
                        effect.layerEffect(
                            ShaderLibrary.limaRipple(
                                .float2(canvasSize),
                                .float2(contentGeometry.frame(in: .named(RippleSpace.canvas)).origin),
                                .float(waveWidth), .floatArray(values), .color(background)
                            ),
                            maxSampleOffset: CGSize(width: 12, height: 12),
                            isEnabled: enabled
                        )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .named(RippleSpace.canvas)) { location in
                        guard !reserved.contains(where: { $0.contains(location) }) else { return }
                        addRipple(at: location, in: canvasSize)
                    }
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.center, for: .alignment)
                .frame(width: available.width, height: available.height)
                .clipped()
                .position(x: available.midX, y: available.midY)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    ZStack {
                        ForEach(ripples) { ripple in
                            let elapsed = timeline.date.timeIntervalSince(ripple.started)
                            if enabled && ripple.showsShockwave && elapsed >= 0 && elapsed < RippleShockwave.lifetime {
                                RippleShockwave(elapsed: elapsed, rippleDuration: ripple.duration,
                                                waveWidth: waveWidth)
                                    .position(x: ripple.origin.x * canvasSize.width,
                                              y: ripple.origin.y * canvasSize.height)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: placement.usesRightHandPane, initial: true) { _, usesRightHandPane in
                pendingOpeningReveal = usesRightHandPane
                revealOpeningIfNeeded(in: geometry.size, pane: available)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { revealOpeningIfNeeded(in: geometry.size, pane: available) }
            }
        }
        .coordinateSpace(.named(RippleSpace.canvas))
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                if !settled {
                    withAnimation(motionDisabled ? nil : .easeOut(duration: 0.55)) {
                        settled = true
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: motionDisabled) {
            if motionDisabled { ripples.removeAll() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background { ripples.removeAll() }
        }
        .transaction { transaction in
            if motionDisabled || scenePhase != .active {
                transaction.disablesAnimations = true
            }
        }
    }

    private nonisolated enum RippleSpace: Hashable, Sendable {
        case canvas
    }

    private func reservedFrames(in geometry: GeometryProxy) -> [CGRect] {
        let regions = geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
            + geometry.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed)
        return regions.filter(\.isActive).map(reservedFrame)
    }

    private func reservedFrame(_ region: ReservedRegion) -> CGRect {
        let margins = region.margins
        let left = layoutDirection == .rightToLeft ? margins.trailing : margins.leading
        let right = layoutDirection == .rightToLeft ? margins.leading : margins.trailing
        return CGRect(
            x: region.frame.minX - left,
            y: region.frame.minY - margins.top,
            width: region.frame.width + left + right,
            height: region.frame.height + margins.top + margins.bottom
        )
    }

    private func revealOpeningIfNeeded(in size: CGSize, pane: CGRect) {
        guard pendingOpeningReveal else { return }
        if motionDisabled {
            pendingOpeningReveal = false
            return
        }
        guard scenePhase == .active, !pane.isEmpty else { return }
        pendingOpeningReveal = false
        addRipple(at: CGPoint(x: pane.minX, y: pane.midY), in: size, showsShockwave: false)
    }

    private struct Ripple: Identifiable {
        let id = UUID()
        let started = Date()
        // Fractions of the available space keep the origin in place during resizing.
        let origin: CGPoint
        let scale: Float
        let showsShockwave: Bool
        let duration = Double.random(in: 2.2...2.6)
    }

    private func addRipple(at location: CGPoint, in size: CGSize, showsShockwave: Bool = true) {
        guard !motionDisabled, scenePhase == .active, size.width > 0, size.height > 0 else { return }
        // Stay generously sized, with only occasional, subtle variation.
        let scale: Float = Double.random(in: 0..<1) < 0.3
            ? Float.random(in: 1.35...1.55) : 1.45
        let ripple = Ripple(
            origin: CGPoint(x: location.x / size.width, y: location.y / size.height),
            scale: scale, showsShockwave: showsShockwave
        )
        ripples.append(ripple)
        // Each tap expires independently; a later tap never restarts an earlier one.
        Task {
            try? await Task.sleep(for: .seconds(ripple.duration))
            ripples.removeAll { $0.id == ripple.id }
        }
    }

    private func rippleValues(at date: Date) -> [Float] {
        ripples.flatMap { ripple in
            [Float(ripple.origin.x), Float(ripple.origin.y),
             Float(date.timeIntervalSince(ripple.started) / ripple.duration), ripple.scale]
        }
    }

    private var wordmark: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array("Lima".enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .offset(
                        x: settled || motionDisabled ? 0 : (Double(index) - 1.5) * 2,
                        y: settled || motionDisabled ? 0 : (index.isMultiple(of: 2) ? -5 : 5)
                    )
            }
            Circle()
                .fill(.indigo)
                .frame(width: dotSize, height: dotSize)
                .padding(.leading, 3)
        }
        .environment(\.layoutDirection, .leftToRight)
        .font(.largeTitle.bold())
        .foregroundStyle(.primary)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lima")
        .accessibilityAddTraits(.isHeader)
    }
}

// Shows this screen in Xcode's preview canvas. It doesn't ship in the app.
#Preview {
    ContentView()
}
