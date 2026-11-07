import CoreGraphics

// Finds room for a single content group without crossing a fold or camera region.
enum AvailableRegion {
    static func welcome(in bounds: CGRect, excluding reserved: [CGRect],
                        divisions: [CGRect], preferRightHandPane: Bool,
                        minimumPaneWidth: CGFloat) -> CGRect {
        let fallback = largest(in: bounds, excluding: reserved)
        guard preferRightHandPane else { return fallback }

        // The inactive fold remains a useful boundary when the display is flat.
        let division = divisions.map { $0.intersection(bounds) }.filter {
            !$0.isNull && $0.height > $0.width && $0.minX > bounds.minX && $0.maxX < bounds.maxX
        }.min { abs($0.midX - bounds.midX) < abs($1.midX - bounds.midX) }
        let rightEdgeOfFold = division?.maxX ?? bounds.midX
        let rightHalf = CGRect(x: rightEdgeOfFold, y: bounds.minY,
                               width: bounds.maxX - rightEdgeOfFold, height: bounds.height)
        let right = largest(in: rightHalf, excluding: reserved)
        guard !right.isEmpty, right.width >= minimumPaneWidth else { return fallback }
        return right
    }

    static func largest(in bounds: CGRect, excluding reserved: [CGRect]) -> CGRect {
        guard !bounds.isEmpty, !bounds.isNull else { return .zero }
        var candidates = [bounds]

        for region in reserved {
            candidates = candidates.flatMap { candidate -> [CGRect] in
                let overlap = candidate.intersection(region)
                guard !overlap.isNull, overlap.width > 0 || overlap.height > 0 else { return [candidate] }

                // Keep each clear strip. They may overlap; the largest wins below.
                return [
                    CGRect(x: candidate.minX, y: candidate.minY,
                           width: overlap.minX - candidate.minX, height: candidate.height),
                    CGRect(x: overlap.maxX, y: candidate.minY,
                           width: candidate.maxX - overlap.maxX, height: candidate.height),
                    CGRect(x: candidate.minX, y: candidate.minY,
                           width: candidate.width, height: overlap.minY - candidate.minY),
                    CGRect(x: candidate.minX, y: overlap.maxY,
                           width: candidate.width, height: candidate.maxY - overlap.maxY)
                ].filter { !$0.isEmpty }
            }
        }

        return candidates.max { first, second in
            let firstArea = first.width * first.height
            let secondArea = second.width * second.height
            if firstArea != secondArea { return firstArea < secondArea }
            // Stable ties favour the lower or right-hand pane.
            if first.midY != second.midY { return first.midY < second.midY }
            return first.midX < second.midX
        } ?? CGRect(origin: bounds.origin, size: .zero)
    }
}
