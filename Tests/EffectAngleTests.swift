import Foundation

@main
struct EffectAngleTests {
    static func main() {
        assert(EffectAngle.progress(angle: 120, onset: 90) == 0)
        assert(EffectAngle.progress(angle: 90, onset: 90) == 0)
        assert(EffectAngle.progress(angle: 89.999, onset: 90) > 0)
        assert(EffectAngle.progress(angle: 89.999, onset: 90) < 0.001)
        assert(EffectAngle.progress(angle: 45, onset: 90) == 0.5)
        assert(EffectAngle.progress(angle: 0, onset: 90) == 1)
        assert(EffectAngle.progress(angle: 75, onset: 60) == 0)
        assert(EffectAngle.progress(angle: 75, onset: 90) > 0)
        for strength in [0.5, 1, 2] {
            assert(EffectAngle.progress(angle: 90, onset: 90, strength: strength) == 0)
            assert(EffectAngle.progress(angle: 0, onset: 90, strength: strength) == 1)
        }
        assert(EffectAngle.progress(angle: 1, onset: 1) == 0)
        assert(EffectAngle.progress(angle: .nan, onset: 90) == 0)
        assert(EffectAngle.progress(angle: 45, onset: 0) == 0)
        print("PASS: blur onset boundary, continuity, lower threshold, strength, invalid inputs")
    }
}
