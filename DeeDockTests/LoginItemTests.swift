import Foundation
import ServiceManagement
import Testing

@MainActor
struct LoginItemTests {
    @Test(arguments: [
        (SMAppService.Status.notRegistered, LoginItemStatus.notRegistered),
        (.enabled, .enabled), (.requiresApproval, .requiresApproval), (.notFound, .notFound)
    ])
    func mapsSystemStatus(system: SMAppService.Status, expected: LoginItemStatus) {
        #expect(LoginItemStatus(system) == expected)
    }

    @Test(arguments: LoginItemStatus.allCases)
    func onlyApprovedRegistrationIsOn(status: LoginItemStatus) {
        let service = LoginItemTestService(status: status)
        let controller = LoginItemController(service: service)
        #expect(controller.status.isEnabled == (status == .enabled))
        #expect(controller.canToggle == (status == .enabled || status == .notRegistered))
        #expect(service.registrations == 0)
        #expect(service.unregistrations == 0)
        #expect(service.settingsOpened == 0)
    }

    @Test(arguments: [LoginItemStatus.enabled, .requiresApproval, .notRegistered])
    func registrationRereadsTheActualResult(result: LoginItemStatus) async throws {
        let service = LoginItemTestService(status: .notRegistered)
        service.resultStatus = result
        let controller = LoginItemController(service: service)
        let request = try #require(controller.setEnabled(true))
        #expect(controller.isPending)
        #expect(!controller.status.isEnabled)
        #expect(!controller.canToggle)
        await request.value
        #expect(service.registrations == 1)
        #expect(controller.status == result)
        #expect(!controller.isPending)
        #expect(controller.errorMessage == nil)
        #expect(service.settingsOpened == 0)
    }

    @Test(arguments: [LoginItemStatus.enabled, .requiresApproval])
    func disablingAndCancellingUseUnregistration(initial: LoginItemStatus) async throws {
        let service = LoginItemTestService(status: initial)
        service.resultStatus = .notRegistered
        let controller = LoginItemController(service: service)
        let request = try #require(initial == .enabled ? controller.setEnabled(false) : controller.cancelRequest())
        await request.value
        #expect(service.unregistrations == 1)
        #expect(service.registrations == 0)
        #expect(controller.status == .notRegistered)
        #expect(!controller.isPending)
    }

    @Test
    func externalChangesRefreshWithoutMutation() {
        let service = LoginItemTestService(status: .enabled)
        let controller = LoginItemController(service: service)
        service.currentStatus = .requiresApproval
        controller.refresh()
        #expect(controller.status == .requiresApproval)
        #expect(!controller.status.isEnabled)
        #expect(!controller.canToggle)
        service.currentStatus = .enabled
        controller.refresh()
        #expect(controller.status.isEnabled)
        #expect(service.registrations == 0)
        #expect(service.unregistrations == 0)
    }

    @Test(arguments: [LoginItemStatus.notRegistered, .enabled, .requiresApproval])
    func failuresStillRefreshStatus(initial: LoginItemStatus) async throws {
        let service = LoginItemTestService(status: initial)
        service.resultStatus = .notFound
        service.failure = TestFailure()
        let controller = LoginItemController(service: service)
        let request = try #require(initial == .requiresApproval
                                  ? controller.cancelRequest() : controller.setEnabled(initial == .notRegistered))
        await request.value
        #expect(controller.status == .notFound)
        #expect(!controller.isPending)
        #expect(controller.errorMessage != nil)
        #expect(service.registrations + service.unregistrations == 1)
        #expect(service.settingsOpened == 0)
        controller.dismissError()
        #expect(controller.errorMessage == nil)
    }

    @Test
    func overlappingCommandsAreRejectedEvenAfterRefresh() async throws {
        let service = LoginItemTestService(status: .enabled)
        service.holdsUnregistration = true
        let controller = LoginItemController(service: service)
        let request = try #require(controller.setEnabled(false))
        await service.waitForUnregistration()
        service.currentStatus = .requiresApproval
        controller.refresh()
        #expect(controller.isPending)
        #expect(!controller.canToggle)
        #expect(controller.setEnabled(true) == nil)
        #expect(controller.setEnabled(false) == nil)
        #expect(controller.cancelRequest() == nil)
        service.completeUnregistration(status: .notRegistered)
        await request.value
        #expect(service.unregistrations == 1)
        #expect(service.registrations == 0)
        #expect(controller.status == .notRegistered)
        #expect(controller.canToggle)
    }

    @Test
    func repeatedRegistrationDoesNotResubmit() async throws {
        let service = LoginItemTestService(status: .notRegistered)
        service.resultStatus = .enabled
        let controller = LoginItemController(service: service)
        let request = try #require(controller.setEnabled(true))
        #expect(controller.setEnabled(true) == nil)
        await request.value
        #expect(controller.setEnabled(true) == nil)
        #expect(service.registrations == 1)
    }

    @Test
    func aLaterExplicitRequestClearsThePreviousError() async throws {
        let service = LoginItemTestService(status: .notRegistered)
        service.failure = TestFailure()
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)?.value
        #expect(controller.errorMessage != nil)
        service.failure = nil
        service.resultStatus = .enabled
        let retry = try #require(controller.setEnabled(true))
        #expect(controller.errorMessage == nil)
        await retry.value
        #expect(controller.status == .enabled)
        #expect(service.registrations == 2)
    }

    @Test
    func successfulUnregistrationDoesNotAssumeDisabledStatus() async throws {
        let service = LoginItemTestService(status: .enabled)
        service.resultStatus = .enabled
        let controller = LoginItemController(service: service)
        let request = try #require(controller.setEnabled(false))
        await request.value
        #expect(controller.status.isEnabled)
        #expect(!controller.isPending)
        #expect(service.unregistrations == 1)
    }

    @Test(arguments: [LoginItemStatus.requiresApproval, .notFound, .unknown])
    func unavailableToggleNeverRegisters(status: LoginItemStatus) {
        let service = LoginItemTestService(status: status)
        let controller = LoginItemController(service: service)
        #expect(controller.setEnabled(true) == nil)
        #expect(controller.setEnabled(false) == nil)
        #expect(service.registrations == 0)
        #expect(service.unregistrations == 0)
    }

    @Test
    func commandsRevalidateExternalChanges() {
        let service = LoginItemTestService(status: .notRegistered)
        let controller = LoginItemController(service: service)
        service.currentStatus = .enabled
        #expect(controller.setEnabled(true) == nil)
        #expect(controller.status == .enabled)
        service.currentStatus = .notRegistered
        #expect(controller.setEnabled(false) == nil)
        #expect(controller.cancelRequest() == nil)
        #expect(service.registrations + service.unregistrations == 0)
    }

    @Test
    func systemSettingsOpensOnlyWhenRequested() {
        let service = LoginItemTestService(status: .requiresApproval)
        let controller = LoginItemController(service: service)
        controller.refresh()
        #expect(service.settingsOpened == 0)
        controller.openSystemSettings()
        #expect(service.settingsOpened == 1)
    }

    @Test
    func shutdownBeforeSubmissionCancelsOwnedWork() async throws {
        let service = LoginItemTestService(status: .notRegistered)
        let controller = LoginItemController(service: service)
        let request = try #require(controller.setEnabled(true))
        controller.stop()
        await request.value
        #expect(service.registrations == 0)
        #expect(!controller.isPending)
    }

    @Test(arguments: [false, true])
    func shutdownIgnoresLateCompletion(fails: Bool) async throws {
        let service = LoginItemTestService(status: .enabled)
        service.holdsUnregistration = true
        let controller = LoginItemController(service: service)
        let request = try #require(controller.setEnabled(false))
        await service.waitForUnregistration()
        let reads = service.statusReads
        controller.stop()
        service.completeUnregistration(status: .notRegistered, error: fails ? TestFailure() : nil)
        await request.value
        controller.refresh()
        controller.openSystemSettings()
        #expect(controller.setEnabled(true) == nil)
        #expect(controller.cancelRequest() == nil)
        #expect(controller.status == .enabled)
        #expect(controller.errorMessage == nil)
        #expect(!controller.isPending)
        #expect(!controller.canToggle)
        #expect(service.statusReads == reads)
        #expect(service.settingsOpened == 0)
    }
}

private struct TestFailure: Error {}

/// Controlled callbacks deliberately ignore task cancellation, just as a submitted OS request can.
@MainActor
private final class LoginItemTestService: LoginItemServicing {
    var currentStatus: LoginItemStatus
    var resultStatus: LoginItemStatus = .notRegistered
    var failure: (any Error)?
    var holdsUnregistration = false
    var registrations = 0
    var unregistrations = 0
    var settingsOpened = 0
    var statusReads = 0
    private var completion: CheckedContinuation<Void, any Error>?
    private var started: CheckedContinuation<Void, Never>?

    init(status: LoginItemStatus) { currentStatus = status }
    var status: LoginItemStatus {
        statusReads += 1
        return currentStatus
    }

    func register() throws {
        registrations += 1
        currentStatus = resultStatus
        if let failure { throw failure }
    }

    func unregister() async throws {
        unregistrations += 1
        if holdsUnregistration {
            try await withCheckedThrowingContinuation { completion in
                self.completion = completion
                started?.resume()
                started = nil
            }
        } else {
            currentStatus = resultStatus
            if let failure { throw failure }
        }
    }

    func waitForUnregistration() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func completeUnregistration(status: LoginItemStatus, error: (any Error)? = nil) {
        currentStatus = status
        let callback = completion
        completion = nil
        if let error { callback?.resume(throwing: error) }
        else { callback?.resume() }
    }

    func openSystemSettings() { settingsOpened += 1 }
}
