import AppKit
import SwiftUI

/// Shown in place of a folder stack's contents when macOS refuses to list them. Explains the
/// cause and offers Finder, which can usually open the folder, plus the Full Disk Access pane
/// when that setting would let DOKK read it.
struct FolderStackAccessDeniedView: View {
    let denial: FolderStackAccessDenial
    /// The folder or drive name supplied by macOS.
    let name: String
    let openInFinder: () -> Void
    let openFullDiskAccess: () -> Void
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(.folderStackAccessDeniedTitle, systemImage: denial == .privacyProtection ? "lock.shield" : "lock")
        } description: {
            Text(denial == .privacyProtection ? .folderStackAccessDeniedPrivacy(name: name)
                                              : .folderStackAccessDeniedPermissions(name: name))
        } actions: {
            Button(.volumeOpenInFinder, action: openInFinder)
            if denial == .privacyProtection {
                Button(.folderStackOpenFullDiskAccess, action: openFullDiskAccess)
            }
            Button(.folderStackRetry, action: retry)
        }
    }
}

extension FolderStackAccessDeniedView {
    /// Opens System Settings at Privacy & Security › Full Disk Access.
    static func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}

#Preview("Privacy protection") {
    FolderStackAccessDeniedView(denial: .privacyProtection, name: "TimeMachine", openInFinder: {},
                                openFullDiskAccess: {}, retry: {})
        .frame(width: 560, height: 360)
}

#Preview("File permissions, long name, dark") {
    FolderStackAccessDeniedView(denial: .filePermissions, name: "A very long shared folder name from the office server",
                                openInFinder: {}, openFullDiskAccess: {}, retry: {})
        .frame(width: 560, height: 360)
        .preferredColorScheme(.dark)
}
