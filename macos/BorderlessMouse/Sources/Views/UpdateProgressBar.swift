import SwiftUI

/// Update progress: a graphite track, a sage fill with drifting sparks and a white head.
/// The shown value glides toward the reported one every frame, so sparse download reports
/// and the steps that only creep never make it jump.
struct UpdateProgressBar: View {
    @ObservedObject var progress: UpdateProgress
    var trackHeight: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var follower = ProgressFollower()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let shown = follower.follow(progress.value, at: time, response: reduceMotion ? 0.12 : 0.35)
            ProgressTrack(value: shown, time: reduceMotion ? nil : time, trackHeight: trackHeight)
        }
        .frame(height: trackHeight + 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("Postęp aktualizacji", "Update progress"))
        .accessibilityValue(Text(progress.value, format: .percent.precision(.fractionLength(0))))
    }
}

/// Exponential glide toward the target; never moves backward unless the target restarts.
@MainActor
private final class ProgressFollower {
    private var shown: Double?
    private var lastTime: TimeInterval = 0

    func follow(_ target: Double, at time: TimeInterval, response: Double) -> Double {
        defer { lastTime = time }
        guard let current = shown, target >= current else {
            shown = target
            return target
        }
        let step = min(max(time - lastTime, 0), 0.2)
        var next = current + (target - current) * (1 - exp(-step / response))
        if target - next < 0.0005 { next = target }
        shown = next
        return next
    }
}

private struct ProgressTrack: View {
    let value: Double
    /// Drives the sparks; nil when Reduce Motion is on.
    let time: TimeInterval?
    let trackHeight: CGFloat

    private static let fill = [Color(red: 0.80, green: 0.88, blue: 0.78), DesignTokens.accent, Color(red: 0.36, green: 0.47, blue: 0.35)]
    private static let sparks = Spark.field(count: 12)

    var body: some View {
        Canvas { context, size in
            let height = trackHeight
            let top = (size.height - height) / 2
            let span = max(size.width - height, 1)
            let headX = height / 2 + span * min(max(value, 0), 1)
            context.fill(Path(roundedRect: CGRect(x: 0, y: top, width: size.width, height: height), cornerRadius: height / 2),
                         with: .color(.white.opacity(0.10)))

            // The fill appears over the first few percent instead of popping in as a dot.
            let reveal = smoothstep(value, from: 0.01, to: 0.05)
            if reveal > 0 {
                var fill = context
                fill.opacity = reveal
                fill.clip(to: Path(roundedRect: CGRect(x: 0, y: top, width: headX + height / 2, height: height), cornerRadius: height / 2))
                // The gradient spans the whole track, so the color deepens as the bar grows.
                fill.fill(Path(CGRect(x: 0, y: top, width: size.width, height: height)),
                          with: .linearGradient(Gradient(colors: Self.fill), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)))
                fill.fill(Path(CGRect(x: 0, y: top, width: size.width, height: height * 0.45)), with: .color(.white.opacity(0.14)))
                if let time {
                    for spark in Self.sparks {
                        let x = spark.x * size.width + sin(time * 0.7 + spark.phase) * 2
                        guard x < headX - height / 2 else { continue }
                        let y = top + spark.y * height
                        let twinkle = 0.25 + 0.55 * (0.5 + 0.5 * sin(time * spark.speed + spark.phase))
                        fill.fill(Path(ellipseIn: CGRect(x: x - spark.size / 2, y: y - spark.size / 2, width: spark.size, height: spark.size)),
                                  with: .color(.white.opacity(twinkle)))
                    }
                }
            }

            let head = height - 2
            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 2, y: 1))
            shadowed.fill(Path(ellipseIn: CGRect(x: headX - head / 2, y: top + 1, width: head, height: head)),
                          with: .color(.white.opacity(0.96)))
        }
    }

    private func smoothstep(_ x: Double, from edge0: Double, to edge1: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// A fixed field of sparks; positions come from a small hash so they never reshuffle.
private struct Spark {
    let x: Double
    let y: Double
    let size: CGFloat
    let speed: Double
    let phase: Double

    static func field(count: Int) -> [Spark] {
        (0..<count).map { index in
            func unit(_ salt: Int) -> Double {
                var h = UInt64(index &* 2_654_435_761 &+ salt &* 40_503)
                h ^= h >> 13
                h = h &* 0x5bd1e995
                h ^= h >> 15
                return Double(h % 10_000) / 10_000
            }
            return Spark(x: unit(1), y: 0.2 + unit(2) * 0.6, size: 1.2 + unit(3) * 2.2,
                         speed: 1.5 + unit(4) * 2.5, phase: unit(5) * .pi * 2)
        }
    }
}
