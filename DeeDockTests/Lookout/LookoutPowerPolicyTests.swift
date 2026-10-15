import Foundation
import Testing
@testable import DeeDock

/// When the backfill has to wait: Low Power Mode, a warm Mac, or battery power with "Read files on battery too" off.
struct LookoutPowerPolicyTests {
    private func blocker(lowPower: Bool = false, thermal: ProcessInfo.ThermalState = .nominal, onAC: Bool = true,
                         indexOnBattery: Bool = true) -> LookoutBackfillBlocker? {
        LookoutPowerPolicy.backfillBlocker(lowPowerMode: lowPower, thermalState: thermal, onACPower: onAC,
                                           indexOnBattery: indexOnBattery)
    }

    @Test func aCoolMacOnAnyPowerMayBackfill() {
        #expect(blocker() == nil)
        #expect(blocker(thermal: .fair) == nil)
        #expect(blocker(onAC: false) == nil)   // battery is fine by default
    }

    @Test func lowPowerModeAndHeatMakeItWait() {
        #expect(blocker(lowPower: true) == .lowPowerMode)
        #expect(blocker(thermal: .serious) == .warm)
        #expect(blocker(thermal: .critical) == .warm)
        #expect(blocker(lowPower: true, thermal: .critical, onAC: false, indexOnBattery: false) == .lowPowerMode)
        #expect(blocker(thermal: .serious, onAC: false, indexOnBattery: false) == .warm)
    }

    @Test func batteryOnlyCountsWhenReadingOnBatteryIsOff() {
        #expect(blocker(onAC: false, indexOnBattery: false) == .onBattery)
        #expect(blocker(onAC: true, indexOnBattery: false) == nil)
    }
}
