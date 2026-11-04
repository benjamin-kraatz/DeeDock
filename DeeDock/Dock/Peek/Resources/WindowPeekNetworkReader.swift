import Darwin
import Foundation
import os

/// Down and up byte totals for one set of processes, cumulative since this reader started.
nonisolated struct WindowPeekNetworkTotals: Equatable, Sendable {
    var received: UInt64
    var sent: UInt64
}

/// Bytes per second in each direction. Nil when the counters moved backwards, which means the
/// private interface changed shape or a flow was counted twice.
nonisolated struct WindowPeekNetworkRate: Equatable, Sendable {
    var receivedPerSecond: Double
    var sentPerSecond: Double

    static func make(current: WindowPeekNetworkTotals, previous: WindowPeekNetworkTotals,
                     interval: Double) -> WindowPeekNetworkRate? {
        guard interval > 0, current.received >= previous.received, current.sent >= previous.sent else { return nil }
        return WindowPeekNetworkRate(receivedPerSecond: Double(current.received - previous.received) / interval,
                                     sentPerSecond: Double(current.sent - previous.sent) / interval)
    }
}

/// Byte accounting for one Peek, independent of the private framework.
///
/// A description can arrive before any counts, and it carries no byte counters. Those zeros are not
/// a baseline: the first counts callback is. A later read reports only growth after that callback,
/// so traffic from before Peek opened does not appear as one interval. A flow with no counts yet is
/// skipped, including when it closes.
nonisolated struct WindowPeekNetworkLedger {
    private struct Flow {
        var pid: pid_t = 0
        var received: UInt64 = 0
        var sent: UInt64 = 0
        /// The baseline, then each total already handed to a rate.
        var countedReceived: UInt64 = 0
        var countedSent: UInt64 = 0
        /// False until a counts callback has written `received` and `sent`.
        var hasCounts = false
    }

    private var flows: [UInt: Flow] = [:]
    /// Growth of flows that closed since the last read, after their first counts.
    private var pending: [pid_t: WindowPeekNetworkTotals] = [:]

    /// Records the process id from a description. Does not invent counters.
    mutating func describe(key: UInt, pid: pid_t) {
        var flow = flows[key, default: Flow()]
        flow.pid = pid
        flows[key] = flow
    }

    /// Records one counts callback. The first one freezes the baseline; later ones update the totals.
    mutating func counts(key: UInt, pid: pid_t?, received: UInt64, sent: UInt64) {
        var flow = flows[key, default: Flow()]
        if let pid { flow.pid = pid }
        if !flow.hasCounts {
            flow.countedReceived = received
            flow.countedSent = sent
            flow.hasCounts = true
        }
        flow.received = received
        flow.sent = sent
        flows[key] = flow
    }

    /// Drops a flow. Growth since its baseline waits in `pending` for the next read.
    /// A flow that never received counts contributes nothing.
    mutating func remove(key: UInt) {
        guard let flow = flows.removeValue(forKey: key), flow.pid > 0, flow.hasCounts else { return }
        var totals = pending[flow.pid, default: WindowPeekNetworkTotals(received: 0, sent: 0)]
        totals.received &+= Self.growth(flow.received, since: flow.countedReceived)
        totals.sent &+= Self.growth(flow.sent, since: flow.countedSent)
        pending[flow.pid] = totals
    }

    /// Bytes received and sent by `pids` since the previous call. The first counts of a flow
    /// contribute nothing.
    mutating func take(matching pids: Set<pid_t>) -> WindowPeekNetworkTotals {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for key in Array(flows.keys) {
            guard var flow = flows[key], flow.hasCounts else { continue }
            if flow.pid > 0, pids.contains(flow.pid) {
                received &+= Self.growth(flow.received, since: flow.countedReceived)
                sent &+= Self.growth(flow.sent, since: flow.countedSent)
            }
            flow.countedReceived = flow.received
            flow.countedSent = flow.sent
            flows[key] = flow
        }
        for pid in pids {
            guard let extra = pending[pid] else { continue }
            received &+= extra.received
            sent &+= extra.sent
            pending[pid] = nil
        }
        return WindowPeekNetworkTotals(received: received, sent: sent)
    }

    private static func growth(_ current: UInt64, since counted: UInt64) -> UInt64 {
        current >= counted ? current &- counted : 0
    }
}

/// Per-process network totals from the private NetworkStatistics framework, while a Peek is open.
///
/// Activity Monitor and `nettop` read the same interface. There is no public equivalent.
/// The calls were checked on macOS 27.2: `NStatManagerCreate` takes an allocator, a queue, and a
/// source block; subscribing to TCP and UDP delivers description and counts dictionaries keyed by
/// `kNStatSrcKeyPID`, `kNStatSrcKeyRxBytes`, and `kNStatSrcKeyTxBytes`; `NStatManagerDestroy`
/// tears the manager down. `dlsym` cannot prove a signature, so this stays off on any other major
/// release, and on any missing symbol. A failure leaves the Peek line without a network figure.
///
/// The framework reports every flow, not just the peeked app. This reader keeps each flow's
/// process id and byte counts in memory so a rate can be computed, shows only the requested
/// processes, and drops the table in `stop`. Addresses are never read. Nothing is written.
nonisolated final class WindowPeekNetworkReader: @unchecked Sendable {
    private typealias SourceBlock = @convention(block) (OpaquePointer?) -> Void
    private typealias DictionaryBlock = @convention(block) (NSDictionary?) -> Void
    private typealias Create = @convention(c) (CFAllocator?, UnsafeMutableRawPointer?, @escaping SourceBlock) -> OpaquePointer?
    private typealias AddAll = @convention(c) (OpaquePointer?) -> Void
    private typealias SetDictionaryBlock = @convention(c) (OpaquePointer?, @escaping DictionaryBlock) -> Void
    private typealias SetRemovedBlock = @convention(c) (OpaquePointer?, @escaping SourceBlock) -> Void
    private typealias QueryDescription = @convention(c) (OpaquePointer?) -> Void
    private typealias QueryUpdate = @convention(c) (OpaquePointer?, @escaping @convention(block) () -> Void) -> Void
    private typealias Destroy = @convention(c) (OpaquePointer?) -> Void

    private struct Interface {
        let create: Create
        let addTCP: AddAll
        let addUDP: AddAll
        let setDescription: SetDictionaryBlock
        let setCounts: SetDictionaryBlock
        let setRemoved: SetRemovedBlock
        let queryDescription: QueryDescription
        let queryUpdate: QueryUpdate
        let destroy: Destroy
        let pid: CFString
        let received: CFString
        let sent: CFString

        static func resolve() -> Interface? {
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27,
                  let image = dlopen("/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics",
                                     RTLD_LAZY | RTLD_LOCAL),
                  let create = function("NStatManagerCreate", image, Create.self),
                  let addTCP = function("NStatManagerAddAllTCP", image, AddAll.self),
                  let addUDP = function("NStatManagerAddAllUDP", image, AddAll.self),
                  let setDescription = function("NStatSourceSetDescriptionBlock", image, SetDictionaryBlock.self),
                  let setCounts = function("NStatSourceSetCountsBlock", image, SetDictionaryBlock.self),
                  let setRemoved = function("NStatSourceSetRemovedBlock", image, SetRemovedBlock.self),
                  let queryDescription = function("NStatSourceQueryDescription", image, QueryDescription.self),
                  let queryUpdate = function("NStatManagerQueryAllSourcesUpdate", image, QueryUpdate.self),
                  let destroy = function("NStatManagerDestroy", image, Destroy.self),
                  let pid = string("kNStatSrcKeyPID", image),
                  let received = string("kNStatSrcKeyRxBytes", image),
                  let sent = string("kNStatSrcKeyTxBytes", image) else { return nil }
            return Interface(create: create, addTCP: addTCP, addUDP: addUDP, setDescription: setDescription,
                             setCounts: setCounts, setRemoved: setRemoved, queryDescription: queryDescription,
                             queryUpdate: queryUpdate, destroy: destroy, pid: pid, received: received, sent: sent)
        }

        private static func function<T>(_ name: String, _ image: UnsafeMutableRawPointer, _: T.Type) -> T? {
            guard let symbol = dlsym(image, name) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }

        /// The keys are exported `CFString` slots. `dlsym` returns the slot, not the string.
        private static func string(_ name: String, _ image: UnsafeMutableRawPointer) -> CFString? {
            guard let symbol = dlsym(image, name) else { return nil }
            return symbol.assumingMemoryBound(to: CFString?.self).pointee
        }
    }

    private static let interface = Interface.resolve()
    /// Callbacks arrive here, never on the main thread. Retained for the manager's lifetime.
    private let queue = DispatchQueue(label: "dock.peek.network")
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var manager: OpaquePointer?

    private struct State {
        var session = UUID()
        var ledger = WindowPeekNetworkLedger()
        var running = false
    }

    /// Begins collecting. A reader that is already collecting starts over, so a new Peek does not
    /// inherit the previous app's totals. Does nothing when the interface is unavailable.
    func start() {
        stop()
        guard let interface = Self.interface else { return }
        let session = UUID()
        state.withLock { $0.session = session }
        let added: SourceBlock = { [weak self] source in
            guard let self, let source else { return }
            self.watch(source, session: session, interface: interface)
        }
        guard let manager = interface.create(kCFAllocatorDefault, Unmanaged.passUnretained(queue).toOpaque(), added) else { return }
        self.manager = manager
        state.withLock { $0.running = true }
        interface.addTCP(manager)
        interface.addUDP(manager)
    }

    /// Drops every flow and releases the manager. Safe when collecting never started.
    func stop() {
        state.withLock { state in
            state.session = UUID()
            state.ledger = WindowPeekNetworkLedger()
            state.running = false
        }
        guard let manager else { return }
        self.manager = nil
        Self.interface?.destroy(manager)
    }

    /// Bytes received and sent by `pids` since the previous call.
    ///
    /// A flow contributes nothing until its first counts callback, and that callback is only a
    /// baseline. Later growth does. Nil when the interface is not running.
    func bytesSinceLastRead(matching pids: Set<pid_t>) -> WindowPeekNetworkTotals? {
        state.withLock { state in
            guard state.running else { return nil }
            return state.ledger.take(matching: pids)
        }
    }

    /// Asks for fresh counts without waiting. The next read sees whatever has arrived.
    func refresh() {
        guard let manager, state.withLock({ $0.running }) else { return }
        Self.interface?.queryUpdate(manager, {})
    }

    private func watch(_ source: OpaquePointer, session: UUID, interface: Interface) {
        let key = UInt(bitPattern: source)
        interface.setDescription(source, { [weak self] dictionary in
            guard let self, let dictionary, let pid = Self.pid(dictionary[interface.pid]) else { return }
            self.state.withLock { state in
                guard state.session == session else { return }
                state.ledger.describe(key: key, pid: pid)
            }
        })
        interface.setCounts(source, { [weak self] dictionary in
            guard let self, let dictionary else { return }
            let received = Self.bytes(dictionary[interface.received])
            let sent = Self.bytes(dictionary[interface.sent])
            let pid = Self.pid(dictionary[interface.pid])
            self.state.withLock { state in
                guard state.session == session else { return }
                state.ledger.counts(key: key, pid: pid, received: received, sent: sent)
            }
        })
        interface.setRemoved(source, { [weak self] _ in
            self?.state.withLock { state in
                guard state.session == session else { return }
                state.ledger.remove(key: key)
            }
        })
        interface.queryDescription(source)
    }

    private static func pid(_ value: Any?) -> pid_t? {
        guard let number = value as? NSNumber else { return nil }
        let pid = pid_t(number.int32Value)
        return pid > 0 ? pid : nil
    }

    private static func bytes(_ value: Any?) -> UInt64 {
        (value as? NSNumber)?.uint64Value ?? 0
    }
}
