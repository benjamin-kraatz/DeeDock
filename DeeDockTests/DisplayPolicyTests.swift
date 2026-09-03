import Foundation
import Testing

@MainActor
struct DisplayPolicyTests {
    @Test("Identity collisions stay session-local until disconnection")
    func identities() {
        var resolver = DisplayIdentityResolver()
        let first = resolver.resolve([1: "same", 2: "same", 3: "unique", 4: nil])
        #expect(first[1] != first[2])
        #expect(first[1]?.hasPrefix("session.") == true)
        #expect(first[4]?.hasPrefix("session.") == true)
        #expect(first[3] == "display.unique")
        #expect(resolver.resolve([1: "same", 3: "unique"])[1] == first[1])
        _ = resolver.resolve([3: "unique"])
        #expect(resolver.resolve([1: "same", 3: "unique"])[1] == "display.same")
    }

    @Test("Reconciliation excludes mirror followers and disabled displays while focus follows the pointer")
    func focusAndMirroring() {
        let primary = DisplayFixtures.screen("primary", runtimeID: 1, x: 0, primary: true)
        let left = DisplayFixtures.screen("left", runtimeID: 2, x: -1600)
        let mirror = DisplayFixtures.screen("mirror", runtimeID: 3, x: 0, mirror: 1)
        let enabled = DisplayPolicy.enabled([left, mirror, primary]) { _ in true }
        #expect(enabled.map(\.id) == [primary.id, left.id])
        #expect(DisplayPolicy.focusTarget(displays: enabled, pointer: CGPoint(x: -200, y: 100)) == left.id)
        #expect(DisplayPolicy.focusTarget(displays: enabled, pointer: CGPoint(x: 9000, y: 0)) == primary.id)
        let onlyLeft = DisplayPolicy.enabled([primary, left, mirror]) { $0 != primary.id }
        #expect(DisplayPolicy.focusTarget(displays: onlyLeft, pointer: .zero) == left.id)
        #expect(DisplayPolicy.enabled([primary, left]) { _ in false }.isEmpty)
        #expect(DisplayPolicy.focusTarget(displays: [], pointer: .zero) == nil)
        #expect(DisplayPolicy.enabled([left]) { _ in true }.map(\.id) == [left.id])
    }

    @Test("A stopped dock session refuses stale completions even if its display reconnects")
    func sessions() {
        var old = DockSession()
        let token = old.token
        #expect(old.accepts(token))
        old.stop()
        #expect(!old.accepts(token))
        #expect(!DockSession().accepts(token))
    }
}
