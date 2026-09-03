import Foundation
import Testing

@MainActor
struct DockFilePickerTests {
    @Test("One picker captures its original app and leases the selected batch")
    func fixedTarget() {
        let picker = FixtureFilePicker()
        let controller = DockFilePickerController(makePicker: { picker })
        let original = DisplayFixtures.app("original")
        var holds: [Bool] = []
        var submitted: ApplicationReference?
        var files: [URL] = []
        controller.show(reference: original, displayID: "one", hold: { holds.append($0) }, submit: { access, target in
            files = access.urls; submitted = target
        }, cancelled: { Issue.record("Not cancelled") })
        controller.show(reference: DisplayFixtures.app("other"), displayID: "two", hold: { _ in Issue.record("Second picker hold") }, submit: { _, _ in Issue.record("Wrong destination") }, cancelled: {})
        #expect(picker.broughtForward == 1)
        #expect(picker.reference == original)
        let url = URL(fileURLWithPath: "/fixture/document.txt")
        picker.reply?([url, url])
        #expect(submitted == original && files == [url])
        #expect(holds == [true, false])
        submitted = nil
        picker.reply?([url])
        #expect(submitted == nil) // Duplicate native completion cannot submit twice.
    }

    @Test("Cancellation restores focus once; display removal suppresses stale responses")
    func cancellation() {
        let picker = FixtureFilePicker()
        let controller = DockFilePickerController(makePicker: { picker })
        var restored = 0
        var holds: [Bool] = []
        func show() {
            controller.show(reference: DisplayFixtures.app("app"), displayID: "one", hold: { holds.append($0) }, submit: { _, _ in Issue.record("Cancelled picker submitted") }, cancelled: { restored += 1 })
        }
        show()
        let firstReply = picker.reply
        picker.reply?(nil)
        #expect(restored == 1)
        show()
        firstReply?([URL(fileURLWithPath: "/fixture/stale")])
        controller.cancel(for: "other")
        #expect(picker.cancellations == 0)
        controller.cancel(for: "one")
        picker.reply?([URL(fileURLWithPath: "/fixture/stale")])
        #expect(picker.cancellations == 1 && restored == 1)
        #expect(holds == [true, false, true, false])
    }
}

@MainActor
private final class FixtureFilePicker: DockFileChoosing {
    var reference: ApplicationReference?
    var reply: (([URL]?) -> Void)?
    var broughtForward = 0
    var cancellations = 0
    func present(for reference: ApplicationReference, completion: @escaping ([URL]?) -> Void) {
        self.reference = reference; reply = completion
    }
    func bringForward() { broughtForward += 1 }
    func cancel() { cancellations += 1; reply?(nil) }
}
