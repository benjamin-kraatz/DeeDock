import AppKit
import Foundation
import Testing
@testable import DeeDock

@MainActor
struct VolumeTests {
    private func traits(path: String = "/Volumes/Stick", browsable: Bool = true, root: Bool = false,
                        local: Bool = true, isInternal: Bool = false, removable: Bool = false,
                        ejectable: Bool = false, deviceProtocol: String? = "USB",
                        model: String? = "Flash Drive", timeMachine: Bool = false) -> VolumeTraits {
        VolumeTraits(path: path, isBrowsable: browsable, isRootFileSystem: root, isLocal: local,
                     isInternal: isInternal, isRemovable: removable, isEjectable: ejectable,
                     deviceProtocol: deviceProtocol, deviceModel: model, isTimeMachineBackup: timeMachine)
    }

    private func volume(_ id: String, kind: VolumeKind) -> VolumeDockItem {
        VolumeDockItem(info: VolumeInfo(volumeID: id, url: URL(fileURLWithPath: "/Volumes/\(id)"), name: id, kind: kind),
                       icon: NSImage(size: CGSize(width: 48, height: 48)), isEjecting: false)
    }

    @Test("Removable media, fixed external disks, disk images, and shares map to their own kinds")
    func classification() {
        #expect(VolumeScanner.classify(traits(removable: true, ejectable: true)) == .removable)
        #expect(VolumeScanner.classify(traits(ejectable: true, deviceProtocol: "Thunderbolt", model: "SSD")) == .externalDisk)
        // Some enclosures report neither removable nor ejectable; an external protocol still counts.
        #expect(VolumeScanner.classify(traits(deviceProtocol: "USB")) == .externalDisk)
        #expect(VolumeScanner.classify(traits(ejectable: true, deviceProtocol: "Disk Image", model: "Disk Image")) == .diskImage)
        #expect(VolumeScanner.classify(traits(ejectable: true, deviceProtocol: "Virtual Interface", model: nil)) == .diskImage)
        #expect(VolumeScanner.classify(traits(local: false, deviceProtocol: nil, model: nil)) == .network)
    }

    @Test("The boot volume, system volumes, internal partitions, and hidden volumes never appear")
    func exclusions() {
        #expect(VolumeScanner.classify(traits(path: "/", root: true)) == nil)
        #expect(VolumeScanner.classify(traits(path: "/System/Volumes/Data")) == nil)
        #expect(VolumeScanner.classify(traits(isInternal: true, deviceProtocol: "Apple Fabric", model: "APPLE SSD")) == nil)
        #expect(VolumeScanner.classify(traits(browsable: false, removable: true)) == nil)
        #expect(VolumeScanner.classify(traits(deviceProtocol: nil, model: nil)) == nil)
        // An internal Mac can still mount a disk image; the image check comes first.
        #expect(VolumeScanner.classify(traits(isInternal: true, deviceProtocol: "Disk Image", model: "Disk Image")) == .diskImage)
    }

    @Test("A Time Machine destination is its own kind, whatever disk carries it, and stays off by default")
    func timeMachine() {
        #expect(VolumeScanner.classify(traits(ejectable: true, timeMachine: true)) == .timeMachine)
        #expect(VolumeScanner.classify(traits(removable: true, timeMachine: true)) == .timeMachine)
        #expect(VolumeScanner.classify(traits(deviceProtocol: "Disk Image", model: "Disk Image", timeMachine: true)) == .timeMachine)
        #expect(VolumeScanner.classify(traits(browsable: false, timeMachine: true)) == nil)
        #expect(VolumeScanner.isTimeMachineBackup(attributeNames: ["com.apple.backupd.HostUUID"]))
        #expect(VolumeScanner.isTimeMachineBackup(attributeNames: ["com.apple.timemachine.private.structure.metadata"]))
        #expect(!VolumeScanner.isTimeMachineBackup(attributeNames: ["com.apple.FinderInfo", "purgeable-drecs-fixed"]))
        #expect(!VolumeVisibility(settings: .defaults).includes(.timeMachine))
        var settings = DockSettings.defaults
        settings.showTimeMachineVolumes = true
        #expect(VolumeVisibility(settings: settings).includes(.timeMachine))
        settings.showVolumes = false
        #expect(!VolumeVisibility(settings: settings).includes(.timeMachine))
        #expect(VolumeKind.timeMachine.isFixedDisk && VolumeKind.externalDisk.isFixedDisk && !VolumeKind.removable.isFixedDisk)
    }

    @Test("Shares read after local volumes keep mount order, and unmounted ones drop out")
    func mountOrder() {
        func info(_ name: String, _ kind: VolumeKind) -> VolumeInfo {
            VolumeInfo(volumeID: name, url: URL(fileURLWithPath: "/Volumes/\(name)", isDirectory: true), name: name, kind: kind)
        }
        let stick = info("Stick", .removable), share = info("Share", .network), image = info("Image", .diskImage)
        let mounts = [share, stick, image].map { MountedVolume(url: $0.url, isLocal: $0.kind != .network) }
        // Local volumes publish first; a share read later still lands in its mount position.
        #expect(VolumeScanner.ordered([stick, image, share], by: mounts) == [share, stick, image])
        #expect(VolumeScanner.ordered([stick, image, share], by: Array(mounts.dropFirst())) == [stick, image])
        // The kernel listing never offers the boot volume or anything outside /Volumes.
        #expect(VolumeScanner.mounts().allSatisfy { $0.url.path.hasPrefix("/Volumes/") })
    }

    @Test("Volume reads run on their queue, not the caller's actor")
    func volumeReadsStayOffTheCaller() async {
        #expect(!VolumeReads.isCurrent)
        let current = await VolumeReads.run { VolumeReads.isCurrent }
        #expect(current)
    }

    @Test("A refused folder listing is told apart by cause; other errors are not access denials")
    func accessDenial() {
        func refusal(_ code: Int32) -> NSError {
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
                    userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(code))])
        }
        #expect(FolderStackAccessDenial(refusal(EPERM)) == .privacyProtection)
        #expect(FolderStackAccessDenial(refusal(EACCES)) == .filePermissions)
        #expect(FolderStackAccessDenial(CocoaError(.fileReadNoPermission)) == .filePermissions)
        #expect(FolderStackAccessDenial(CocoaError(.fileReadNoSuchFile)) == nil)
    }

    @Test("The master switch gates every kind; images and shares have their own opt-ins")
    func visibility() {
        let all = VolumeVisibility(showsVolumes: true, showsDiskImages: true, showsNetworkVolumes: true)
        #expect([VolumeKind.removable, .externalDisk, .diskImage, .network].allSatisfy { all.includes($0) })
        let drivesOnly = VolumeVisibility(showsVolumes: true, showsDiskImages: false, showsNetworkVolumes: false)
        #expect(drivesOnly.includes(.removable) && drivesOnly.includes(.externalDisk))
        #expect(!drivesOnly.includes(.diskImage) && !drivesOnly.includes(.network))
        let off = VolumeVisibility(showsVolumes: false, showsDiskImages: true, showsNetworkVolumes: true)
        #expect(![VolumeKind.removable, .externalDisk, .diskImage, .network].contains { off.includes($0) })
        #expect(VolumeVisibility(settings: .defaults) == VolumeVisibility(showsVolumes: true, showsDiskImages: true,
                                                                           showsNetworkVolumes: false))
    }

    @Test("Volumes trail the Shelf, precede Trash, and share the utility divider without being movable")
    func projection() {
        let shelf = ShelfDockItem(count: 0, icon: NSImage(size: CGSize(width: 48, height: 48)))
        let trash = TrashDockItem(state: .empty, icon: NSImage(size: CGSize(width: 48, height: 48)))
        let stick = volume("Stick", kind: .removable), disk = volume("Backup", kind: .externalDisk)
        let entries = DockSectionProjection.entries(items: [], visibility: .showAll, expanded: false,
                                                    shelf: shelf, volumes: [stick, disk], trash: trash)
        #expect(entries.map(\.target) == [.shelf, .volume("Stick"), .volume("Backup"), .trash])
        #expect(entries.allSatisfy { $0.isUtility })
        #expect(entries.filter { $0.volume != nil }.allSatisfy { $0.movableUtilityID == nil && !$0.isPinned && $0.pin == nil })
        #expect(entries[1].name == "Stick")
        #expect(DockEntryID.volume("Stick").hitID == "volume:Stick")
    }

    @Test("An ejected volume's selection moves to the nearest remaining entry")
    func selectionRepair() {
        let trash = TrashDockItem(state: .empty, icon: NSImage(size: CGSize(width: 48, height: 48)))
        let before = DockSectionProjection.entries(items: [], visibility: .showAll, expanded: false,
                                                   volumes: [volume("Stick", kind: .removable)], trash: trash)
        let after = DockSectionProjection.entries(items: [], visibility: .showAll, expanded: false, trash: trash)
        #expect(DockSectionProjection.repairedSelection(.volume("Stick"), previous: before, current: after) == .trash)
    }

    @Test("A volume keeps one stack identity across remounts, with or without a file system UUID")
    func stackIdentity() {
        let uuid = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
        #expect(VolumeStackIdentity.uuid(for: uuid) == UUID(uuidString: uuid))
        let fat = VolumeStackIdentity.uuid(for: "path:/Volumes/NO NAME")
        #expect(fat == VolumeStackIdentity.uuid(for: "path:/Volumes/NO NAME"))
        #expect(fat != VolumeStackIdentity.uuid(for: "path:/Volumes/OTHER"))
        let item = volume("Stick", kind: .removable).stackItem(displayID: "display-test")
        #expect(item.reference.id == VolumeStackIdentity.uuid(for: "Stick"))
        #expect(item.reference.url.path == "/Volumes/Stick" && !item.isDownloads)
    }

    @Test("Blockers resolve to their application, deduplicated, applications first")
    func blockerResolution() {
        // 300 is a shell whose parent 200 is Terminal; 400 is a background tool with no app.
        let processes = [VolumeBlockerScanner.Process(pid: 400, name: "rsync"),
                         VolumeBlockerScanner.Process(pid: 300, name: "zsh"),
                         VolumeBlockerScanner.Process(pid: 200, name: "Terminal"),
                         VolumeBlockerScanner.Process(pid: 100, name: "Preview")]
        let parents: [pid_t: pid_t] = [300: 250, 250: 200]
        let applications: [pid_t: String] = [200: "Terminal", 100: "Preview"]
        let blockers = VolumeBlockerResolver.blockers(from: processes, parent: { parents[$0] },
                                                      application: { applications[$0] })
        #expect(blockers.map(\.name) == ["Terminal", "Preview", "rsync"])
        #expect(blockers.map(\.isApplication) == [true, true, false])
    }

    @Test("Bare processes keep their path and system flag for the card's Show in Finder")
    func bareProcessDetails() {
        let daemon = VolumeBlockerScanner.Process(pid: 500, name: "revisiond", path: "/usr/libexec/revisiond", isSystem: true)
        let blockers = VolumeBlockerResolver.blockers(from: [daemon], parent: { _ in nil }, application: { _ in nil })
        #expect(blockers == [VolumeBlocker(pid: 500, name: "revisiond", isApplication: false,
                                           executablePath: "/usr/libexec/revisiond", isSystem: true)])
    }

    @Test("Process IDs resolve to names, including root-owned processes")
    func describeProcesses() {
        let own = VolumeBlockerScanner.describe(ProcessInfo.processInfo.processIdentifier)
        #expect(own.name != "\(own.pid)" && !own.isSystem && own.path != nil)
        // launchd runs as root; the volume query cannot inspect it, but the process table can.
        let launchd = VolumeBlockerScanner.describe(1)
        #expect(launchd.name == "launchd" && launchd.isSystem)
    }

    @Test("Free space ignores the zero important-usage figure FAT32 and exFAT report")
    func availableCapacity() {
        // Measured on FAT32 and exFAT images: important usage 0, plain capacity correct.
        #expect(VolumeCapacityFormat.available(important: 0, plain: 222_341_120) == 222_341_120)
        // APFS adds purgeable space to the important-usage figure.
        #expect(VolumeCapacityFormat.available(important: 900, plain: 600) == 900)
        #expect(VolumeCapacityFormat.available(important: nil, plain: 600) == 600)
        #expect(VolumeCapacityFormat.available(important: 700, plain: nil) == 700)
        #expect(VolumeCapacityFormat.available(important: nil, plain: nil) == nil)
    }

    @Test("Used fraction is clamped and unknown without both capacities")
    func capacity() {
        #expect(VolumeCapacityFormat.usedFraction(total: 100, available: 25) == 0.75)
        #expect(VolumeCapacityFormat.usedFraction(total: 100, available: 150) == 0)
        #expect(VolumeCapacityFormat.usedFraction(total: nil, available: 1) == nil)
        #expect(VolumeCapacityFormat.usedFraction(total: 0, available: 0) == nil)
    }

    @Test("Volume settings decode with defaults and stay app-wide")
    func settings() throws {
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(DockSettings.defaults)) as? [String: Any])
        for key in ["showVolumes", "showDiskImages", "showNetworkVolumes", "showTimeMachineVolumes",
                    "confirmBeforeEjectingDisks"] {
            legacy.removeValue(forKey: key)
        }
        let decoded = try JSONDecoder().decode(DockSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.showVolumes && decoded.showDiskImages && !decoded.showNetworkVolumes)
        #expect(decoded.confirmBeforeEjectingDisks && !decoded.showTimeMachineVolumes)
        var defaults = DockSettings.defaults
        defaults.showVolumes = false; defaults.showNetworkVolumes = true; defaults.confirmBeforeEjectingDisks = false
        let resolved = DockSettingsOverrides().resolving(defaults)
        #expect(!resolved.showVolumes && resolved.showNetworkVolumes && !resolved.confirmBeforeEjectingDisks)
    }

    @Test("Only the plain info card follows hover; every other phase stays until resolved")
    func stickyPhases() {
        #expect(!VolumeCardPhase.info.isSticky)
        let sticky: [VolumeCardPhase] = [.confirmDisk, .ejecting, .blocked([]), .confirmForce([]), .failed("x"), .ejected]
        #expect(sticky.allSatisfy { $0.isSticky })
    }
}
