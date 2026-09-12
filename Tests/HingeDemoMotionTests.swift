import Foundation

@main
struct HingeDemoMotionTests {
    static func main() {
        for onset in [1.0, 60, 90, 120, 180] {
            let opened = HingeDemoMotion.angle(time: 0, onset: onset)
            let closed = HingeDemoMotion.angle(time: 5, onset: onset)
            assert(EffectAngle.progress(angle: opened, onset: onset) == 0)
            assert(EffectAngle.progress(angle: closed, onset: onset) > 0)
            var previous = opened
            for tick in 0...100 {
                let angle = HingeDemoMotion.angle(time: 1 + Double(tick) * 0.035, onset: onset)
                assert(angle <= previous + 0.00001)
                assert(angle >= 0 && angle <= 180)
                previous = angle
            }
            assert(abs(HingeDemoMotion.angle(time: 10, onset: onset) - opened) < 0.00001)
            assert(abs(HingeDemoMotion.angle(time: 9.9999, onset: onset) - opened) < 0.00001)
        }
        print("PASS: preview uses real effect thresholds, closes smoothly, and loops without a jump")
    }
}
