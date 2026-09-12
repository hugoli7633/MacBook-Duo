import Foundation

enum EffectAngle {
    static func progress(angle: Double, onset: Double, strength: Double = 1) -> Double {
        guard angle.isFinite, onset.isFinite, onset > 0,
              strength.isFinite, strength > 0 else { return 0 }
        let fraction = min(1, max(0, angle) / onset)
        return 1 - pow(fraction, 1 / strength)
    }
}
