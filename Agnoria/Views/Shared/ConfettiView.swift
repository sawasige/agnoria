import SwiftUI

/// 紙吹雪（§4.3.1 [v1.5]）。画面上端から数秒間降らせて止まる。装飾なので当たり判定も VoiceOver も持たない。
/// 粒子は Canvas で描き、TimelineView で時間だけ進める（View を粒子の数だけ作らない）
struct ConfettiView: View {
    var duration: TimeInterval = 3.5
    private let particles: [Particle]
    private let start = Date()

    init(duration: TimeInterval = 3.5, count: Int = 90) {
        self.duration = duration
        var rng = SystemRandomNumberGenerator()
        particles = (0..<count).map { _ in Particle(using: &rng) }
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { gc, size in
                guard t < duration else { return }
                for p in particles {
                    let age = t - p.delay
                    guard age > 0 else { continue }
                    // 落下（初速 + 重力）と横揺れ。終わり際は薄く消える
                    let y = (p.speed * age + 0.5 * 0.35 * age * age) * size.height - 20
                    let x = (p.x + sin(age * p.swayFreq + p.phase) * p.sway) * size.width
                    guard y < size.height + 20 else { continue }
                    let fade = max(0, min(1, (duration - t) / 0.6))
                    let rect = CGRect(x: -p.size / 2, y: -p.size * 0.3, width: p.size, height: p.size * 0.6)
                    var ctx = gc
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(age * p.spin + p.phase))
                    ctx.opacity = fade
                    let path = p.round ? Path(ellipseIn: rect) : Path(rect)
                    ctx.fill(path, with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct Particle {
        let x: Double          // 0...1
        let delay: Double
        let speed: Double      // 画面高さ/秒
        let sway: Double       // 横揺れの幅（画面幅比）
        let swayFreq: Double
        let phase: Double
        let spin: Double
        let size: CGFloat
        let round: Bool
        let color: Color

        static let palette: [Color] = [.accentColor, .green, .orange, .yellow, .pink, .mint]

        init(using rng: inout SystemRandomNumberGenerator) {
            x = Double.random(in: 0...1, using: &rng)
            delay = Double.random(in: 0...1.2, using: &rng)
            speed = Double.random(in: 0.12...0.3, using: &rng)
            sway = Double.random(in: 0.01...0.05, using: &rng)
            swayFreq = Double.random(in: 2...5, using: &rng)
            phase = Double.random(in: 0...(2 * .pi), using: &rng)
            spin = Double.random(in: -4...4, using: &rng)
            size = CGFloat.random(in: 8...14, using: &rng)
            round = Bool.random(using: &rng)
            color = Self.palette.randomElement(using: &rng) ?? .accentColor
        }
    }
}
