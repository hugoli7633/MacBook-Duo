import Foundation

enum HingeDemoMotion {
    static func angle(time: Double, onset: Double) -> Double {
        let upper = min(180, max(110, onset + 20))
        let lower = max(0, onset * 0.32)
        let phase = time.truncatingRemainder(dividingBy: 10)
        let fraction: Double
        if phase < 1 { fraction = 0 }
        else if phase < 4.5 { fraction = (1 - cos((phase - 1) / 3.5 * .pi)) / 2 }
        else if phase < 5.5 { fraction = 1 }
        else if phase < 9 { fraction = (1 + cos((phase - 5.5) / 3.5 * .pi)) / 2 }
        else { fraction = 0 }
        return upper + (lower - upper) * fraction
    }
}
