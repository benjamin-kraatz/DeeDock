import DiskArbitration
import Foundation

/// Performs unmount and eject requests. Neither path shows system UI; the volume card reports
/// every outcome itself.
nonisolated enum VolumeEjector {
    /// Unmounts every volume on the device and ejects it, the same request Finder's Eject makes.
    ///
    /// - Returns: `.ejected`, `.blocked` with the processes holding files open, or `.failed` with
    ///   macOS's description.
    static func eject(_ url: URL) async -> VolumeEjectResult {
        do {
            try await FileManager.default.unmountVolume(at: url, options: [.allPartitionsAndEjectDisk, .withoutUI])
            return .ejected
        } catch {
            let processes = await Task.detached(priority: .userInitiated) {
                VolumeBlockerScanner.processes(onVolumeAt: url)
            }.value
            // macOS may name a dissenter the volume query cannot see, such as a sandboxed helper.
            let dissenter = (error as NSError).userInfo[NSFileManagerUnmountDissentingProcessIdentifierErrorKey] as? NSNumber
            var candidates = processes
            if let pid = dissenter?.int32Value, pid > 0, !candidates.contains(where: { $0.pid == pid }) {
                candidates.insert(VolumeBlockerScanner.Process(pid: pid, name: "\(pid)"), at: 0)
            }
            let found = candidates
            let blockers = await MainActor.run { VolumeBlockerResolver.blockers(from: found) }
            if !blockers.isEmpty || isBusy(error) { return .blocked(blockers) }
            return .failed(error.localizedDescription)
        }
    }

    /// Unmounts even with files open, then ejects the whole device. Open documents can lose
    /// unsaved changes, so the card asks first.
    static func forceEject(_ url: URL) async -> VolumeEjectResult {
        await withCheckedContinuation { continuation in
            ForceEjectOperation(url: url) { continuation.resume(returning: $0) }.start()
        }
    }

    private static func isBusy(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EBUSY) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(EBUSY)
        }
        return false
    }
}

/// One forced Disk Arbitration unmount followed by an eject.
///
/// Disk Arbitration reports through C callbacks with an opaque context pointer. The operation
/// retains itself through that pointer until the final callback, then releases it exactly once.
private nonisolated final class ForceEjectOperation: @unchecked Sendable {
    private let url: URL
    private let completion: (VolumeEjectResult) -> Void
    private let queue = DispatchQueue(label: "de.benjaminkraatz.DeeDock.volume-eject")
    private var session: DASession?

    init(url: URL, completion: @escaping (VolumeEjectResult) -> Void) {
        self.url = url
        self.completion = completion
    }

    func start() {
        queue.async { [self] in
            guard let session = DASessionCreate(kCFAllocatorDefault),
                  let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else {
                completion(.failed(CocoaError(.fileNoSuchFile).localizedDescription))
                return
            }
            self.session = session
            DASessionSetDispatchQueue(session, queue)
            let context = Unmanaged.passRetained(self).toOpaque()
            // The whole-disk option acts on a whole-disk object, so unmount from there and take
            // sibling partitions with it, as the normal eject does. Shares have no whole disk.
            let target = DADiskCopyWholeDisk(disk) ?? disk
            let options = DADiskUnmountOptions(kDADiskUnmountOptionForce | kDADiskUnmountOptionWhole)
            DADiskUnmount(target, options, { disk, dissenter, context in
                guard let context else { return }
                let operation = Unmanaged<ForceEjectOperation>.fromOpaque(context).takeUnretainedValue()
                operation.unmounted(disk, dissenter: dissenter, context: context)
            }, context)
        }
    }

    private func unmounted(_ disk: DADisk, dissenter: DADissenter?, context: UnsafeMutableRawPointer) {
        if let dissenter {
            finish(.failed(Self.message(dissenter)), context: context)
            return
        }
        // Network shares and some images have no whole device to eject; unmounting was enough.
        guard let whole = DADiskCopyWholeDisk(disk) else {
            finish(.ejected, context: context)
            return
        }
        DADiskEject(whole, DADiskEjectOptions(kDADiskEjectOptionDefault), { _, _, context in
            guard let context else { return }
            // The volume is already gone. A device that refuses the eject is still safe to remove.
            Unmanaged<ForceEjectOperation>.fromOpaque(context).takeUnretainedValue().finish(.ejected, context: context)
        }, context)
    }

    private func finish(_ result: VolumeEjectResult, context: UnsafeMutableRawPointer) {
        if let session { DASessionSetDispatchQueue(session, nil) }
        session = nil
        completion(result)
        Unmanaged<ForceEjectOperation>.fromOpaque(context).release()
    }

    private static func message(_ dissenter: DADissenter) -> String {
        if let text = DADissenterGetStatusString(dissenter) as String? { return text }
        return String(format: "0x%08X", DADissenterGetStatus(dissenter))
    }
}
