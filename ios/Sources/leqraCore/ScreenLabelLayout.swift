import CoreGraphics
import Foundation

/// Keep readable tank identities apart in screen space, including zoomed-out maps.
public enum ScreenLabelLayout {
    public struct Label {
        public let id: Int
        public let frame: CGRect
        public let local: Bool
        public init(id: Int, frame: CGRect, local: Bool = false) {
            self.id = id
            self.frame = frame
            self.local = local
        }
    }

    public static func place(_ labels: [Label], in viewport: CGRect, gap: CGFloat = 3) -> [Int: CGRect] {
        guard viewport.width > 0, viewport.height > 0 else { return [:] }
        var result: [Int: CGRect] = [:]
        var occupied: [CGRect] = []
        for label in labels.sorted(by: { $0.local != $1.local ? $0.local : $0.id < $1.id }) {
            let width = min(label.frame.width, viewport.width)
            let height = min(label.frame.height, viewport.height)
            func clamped(_ x: CGFloat, _ y: CGFloat) -> CGRect {
                CGRect(
                    x: min(max(viewport.minX, x), viewport.maxX - width),
                    y: min(max(viewport.minY, y), viewport.maxY - height), width: width, height: height)
            }
            let preferred = clamped(label.frame.minX, label.frame.minY)
            if !occupied.contains(where: { $0.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(preferred) }) {
                result[label.id] = preferred
                occupied.append(preferred)
                continue
            }
            var candidates = [preferred]
            for other in occupied {
                candidates.append(clamped(preferred.minX, other.maxY + gap))
                candidates.append(clamped(preferred.minX, other.minY - gap - height))
                candidates.append(clamped(other.minX - gap - width, preferred.minY))
                candidates.append(clamped(other.maxX + gap, preferred.minY))
            }
            var placed = preferred
            var nearest = CGFloat.infinity
            for candidate in candidates {
                let dx = candidate.midX - preferred.midX
                let dy = candidate.midY - preferred.midY
                let distance = dx * dx + dy * dy
                guard distance < nearest || distance == nearest && candidate.minY > placed.minY,
                    !occupied.contains(where: { $0.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(candidate) }
                    )
                else { continue }
                placed = candidate
                nearest = distance
            }
            result[label.id] = placed
            occupied.append(placed)
        }
        return result
    }
}
