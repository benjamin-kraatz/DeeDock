#if DEBUG
import Foundation

/// Preview composition never creates a Service Management service.
enum LoginItemPreview {
    static func controller() -> LoginItemController { LoginItemController(service: Service()) }

    private final class Service: LoginItemServicing {
        var status: LoginItemStatus { .notRegistered }
        func register() throws {}
        func unregister() async throws {}
        func openSystemSettings() {}
    }
}

/// Previews report a fixed permission state and never prompt.
enum WindowAccessPreview {
    static func controller(status: WindowAccessStatus = .notEnabled) -> WindowAccessController {
        WindowAccessController(service: Service(status: status))
    }

    private final class Service: WindowAccessServicing {
        let status: WindowAccessStatus
        init(status: WindowAccessStatus) { self.status = status }
        func requestAccess() {}
        func openSystemSettings() {}
    }
}

/// Previews report a fixed permission state and never prompt.
enum ScreenCaptureAccessPreview {
    static func controller(status: ScreenCaptureAccessStatus = .notEnabled) -> ScreenCaptureAccessController {
        ScreenCaptureAccessController(service: Service(status: status))
    }

    private final class Service: ScreenCaptureAccessServicing {
        let status: ScreenCaptureAccessStatus
        init(status: ScreenCaptureAccessStatus) { self.status = status }
        func requestAccess() {}
        func openSystemSettings() {}
    }
}
#endif
