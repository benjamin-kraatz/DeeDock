import Foundation

/// Injectable native picker boundary. A nil response means cancellation, never an empty batch.
@MainActor
protocol DockFileChoosing: AnyObject {
    func present(for reference: ApplicationReference, completion: @escaping ([URL]?) -> Void)
    func bringForward()
    func cancel()
}

/// Owns one picker across all displays. Its immutable target cannot follow later dock selection.
@MainActor
final class DockFilePickerController {
    private struct Session {
        let token: UUID
        let displayID: String
        let picker: any DockFileChoosing
        let hold: (Bool) -> Void
    }
    private var session: Session?
    private let makePicker: () -> any DockFileChoosing
    var isActive: Bool { session != nil }

    init(makePicker: @escaping () -> any DockFileChoosing) { self.makePicker = makePicker }

    func show(reference: ApplicationReference, displayID: String, hold: @escaping (Bool) -> Void,
              submit: @escaping (DocumentResourceAccess, ApplicationReference) -> Void,
              cancelled: @escaping () -> Void) {
        if let session { session.picker.bringForward(); return }
        let picker = makePicker()
        let token = UUID()
        session = Session(token: token, displayID: displayID, picker: picker, hold: hold)
        hold(true)
        picker.present(for: reference) { [weak self] urls in
            guard let self, let active = session, active.token == token else { return }
            // Acquire the URLs before releasing the native panel and its interaction hold.
            let access = urls.map { DocumentResourceAccess($0) }
            session = nil
            active.hold(false)
            if let access { submit(access, reference) }
            else { cancelled() }
        }
    }

    /// Invalidate the callback before cancelling AppKit, which may synchronously call it again.
    func cancel(for displayID: String) {
        guard session?.displayID == displayID else { return }
        stop()
    }

    func stop() {
        guard let active = session else { return }
        session = nil
        active.hold(false)
        active.picker.cancel()
    }
}
