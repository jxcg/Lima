import CoreGraphics

// swiftc LimaApp/AvailableRegion.swift Tests/AvailableRegionCheck.swift -o /tmp/lima-region-check
// /tmp/lima-region-check
@main
struct AvailableRegionCheck {
    static func main() {
        let outer = CGRect(x: 0, y: 0, width: 320, height: 500)
        let inner = CGRect(x: 0, y: 0, width: 600, height: 500)
        let bookFold = CGRect(x: 290, y: 0, width: 20, height: 500)
        let tableFold = CGRect(x: 0, y: 240, width: 600, height: 20)
        let camera = CGRect(x: 270, y: 0, width: 50, height: 40)

        precondition(AvailableRegion.largest(in: outer, excluding: []) == outer)
        precondition(AvailableRegion.largest(in: inner, excluding: []) == inner)
        precondition(AvailableRegion.largest(in: inner, excluding: [bookFold])
                     == CGRect(x: 310, y: 0, width: 290, height: 500))
        precondition(AvailableRegion.largest(in: inner, excluding: [tableFold])
                     == CGRect(x: 0, y: 260, width: 600, height: 240))
        precondition(AvailableRegion.largest(in: inner, excluding: [CGRect(x: 300, y: 0, width: 0, height: 500)])
                     == CGRect(x: 300, y: 0, width: 300, height: 500))

        let cases: [(CGRect, [CGRect])] = [
            (outer, [camera]),
            (inner, [bookFold, camera]),
            (inner, [tableFold, camera]),
            (CGRect(x: 17, y: 9, width: 560, height: 460), [bookFold, camera]),
            (CGRect(x: 0, y: 0, width: 150, height: 500), [camera]),
            (inner, [CGRect(x: -10, y: -10, width: 30, height: 520)])
        ]
        for (bounds, reserved) in cases {
            let available = AvailableRegion.largest(in: bounds, excluding: reserved)
            precondition(bounds.contains(available), "Content must stay inside the safe area")
            for region in reserved {
                precondition(available.intersection(region).isEmpty,
                             "Content must avoid both the camera and the fold")
            }
        }
        // Closing and reopening must recalculate from the current space, not cached dimensions.
        for (bounds, reserved) in [(inner, [bookFold]), (outer, []), (inner, [])] {
            let available = AvailableRegion.largest(in: bounds, excluding: reserved)
            precondition(!available.isEmpty)
            if reserved.isEmpty { precondition(available == bounds) }
        }
        precondition(AvailableRegion.largest(in: inner, excluding: [inner]).isEmpty)
        precondition(AvailableRegion.largest(in: .zero, excluding: []).isEmpty)
        print("PASS: outer/inner layouts, vertical/horizontal folds, cameras, asymmetric safe areas and resizing")

        let open = AvailableRegion.welcome(in: inner, excluding: [], divisions: [],
                                           preferRightHandPane: true, minimumPaneWidth: 250)
        precondition(open.usesRightHandPane && open.frame == CGRect(x: 300, y: 0, width: 300, height: 500))
        let closed = AvailableRegion.welcome(in: outer, excluding: [], divisions: [],
                                             preferRightHandPane: false, minimumPaneWidth: 250)
        precondition(!closed.usesRightHandPane && closed.frame == outer)
        let narrow = AvailableRegion.welcome(in: outer, excluding: [], divisions: [],
                                             preferRightHandPane: true, minimumPaneWidth: 250)
        precondition(!narrow.usesRightHandPane && narrow.frame == outer)
        let book = AvailableRegion.welcome(in: inner, excluding: [bookFold], divisions: [bookFold],
                                           preferRightHandPane: true, minimumPaneWidth: 250)
        precondition(book.usesRightHandPane && book.frame.minX == bookFold.maxX)
        let horizontal = AvailableRegion.welcome(in: inner, excluding: [tableFold], divisions: [tableFold],
                                                 preferRightHandPane: true, minimumPaneWidth: 250)
        precondition(horizontal.usesRightHandPane && horizontal.frame == CGRect(x: 300, y: 260, width: 300, height: 240))
        let inactiveFold = CGRect(x: 330, y: 0, width: 10, height: 500)
        let flat = AvailableRegion.welcome(in: inner, excluding: [], divisions: [inactiveFold],
                                           preferRightHandPane: true, minimumPaneWidth: 250)
        precondition(flat.usesRightHandPane && flat.frame.minX == inactiveFold.maxX)
        let largeType = AvailableRegion.welcome(in: inner, excluding: [], divisions: [],
                                                preferRightHandPane: true, minimumPaneWidth: 400)
        precondition(!largeType.usesRightHandPane && largeType.frame == inner)
        let rightBlocked = CGRect(x: 300, y: 0, width: 300, height: 500)
        let blocked = AvailableRegion.welcome(in: inner, excluding: [rightBlocked], divisions: [],
                                              preferRightHandPane: true, minimumPaneWidth: 250)
        precondition(!blocked.usesRightHandPane && blocked.frame.maxX <= rightBlocked.minX)
        let rightCamera = CGRect(x: 540, y: 0, width: 60, height: 60)
        let occluded = AvailableRegion.welcome(in: inner, excluding: [rightCamera], divisions: [],
                                               preferRightHandPane: true, minimumPaneWidth: 250)
        precondition(occluded.usesRightHandPane && occluded.frame.minX >= inner.midX
                     && occluded.frame.intersection(rightCamera).isEmpty)
        print("PASS: right-hand wide placement, compact/narrow fallback, active/inactive folds, cameras and text-size constraints")
    }
}
