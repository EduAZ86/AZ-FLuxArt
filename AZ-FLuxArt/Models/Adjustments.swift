import Foundation

struct Adjustments: Equatable {
    var brightness: Double = 0      // -1 ... 1
    var contrast: Double = 1        // 0 ... 2
    var saturation: Double = 1      // 0 ... 2
    var exposure: Double = 0        // -2 ... 2
    var temperature: Double = 0     // -100 ... 100

    static let identity = Adjustments()

    var isIdentity: Bool {
        abs(brightness) < 0.001
            && abs(contrast - 1) < 0.001
            && abs(saturation - 1) < 0.001
            && abs(exposure) < 0.001
            && abs(temperature) < 0.001
    }

    mutating func reset() {
        self = .identity
    }
}