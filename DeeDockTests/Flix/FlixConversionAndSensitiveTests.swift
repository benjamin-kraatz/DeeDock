import Foundation
import Testing
import UniformTypeIdentifiers
@testable import DeeDock

/// Upload conversion decisions and the sensitive file guard's text rules.
struct FlixConversionAndSensitiveTests {
    private func demand(_ types: [UTType], max: Int64? = nil) -> FlixWindowDemand {
        FlixWindowDemand(acceptedTypes: types, maximumBytes: max, pageKind: .upload)
    }

    // MARK: Conversion planning

    @Test func acceptedFilesWithinTheLimitStay() {
        #expect(FlixConversionPlanner.decision(type: .pdf, byteSize: 1_000_000, isFile: true, demand: demand([.pdf], max: 5_000_000)) == .keep)
        #expect(FlixConversionPlanner.decision(type: .heic, byteSize: 9_000_000, isFile: true, demand: FlixWindowDemand()) == .keep)
        // Folders and apps never convert.
        #expect(FlixConversionPlanner.decision(type: .folder, byteSize: nil, isFile: false, demand: demand([.pdf])) == .keep)
    }

    @Test func picturesBecomePDFWhenOnlyPDFsAreAccepted() {
        #expect(FlixConversionPlanner.decision(type: .heic, byteSize: 3_000_000, isFile: true, demand: demand([.pdf], max: 5_000_000))
            == .convert(FlixConversionRecipe(format: .pdf, maximumBytes: 5_000_000)))
        #expect(FlixConversionPlanner.decision(type: .png, byteSize: 300_000, isFile: true, demand: demand([.jpeg]))
            == .convert(FlixConversionRecipe(format: .jpeg)))
    }

    @Test func oversizedPicturesAreScaledDown() {
        #expect(FlixConversionPlanner.decision(type: .jpeg, byteSize: 12_000_000, isFile: true, demand: demand([.jpeg, .png], max: 5_000_000))
            == .convert(FlixConversionRecipe(format: .jpeg, maximumBytes: 5_000_000, isResizeOnly: true)))
        #expect(FlixConversionPlanner.decision(type: .png, byteSize: 12_000_000, isFile: true, demand: demand([.png], max: 2_000_000))
            == .convert(FlixConversionRecipe(format: .png, maximumBytes: 2_000_000, isResizeOnly: true)))
        // No type limit, only a size: a JPEG copy.
        #expect(FlixConversionPlanner.decision(type: .heic, byteSize: 12_000_000, isFile: true, demand: demand([], max: 5_000_000))
            == .convert(FlixConversionRecipe(format: .jpeg, maximumBytes: 5_000_000, isResizeOnly: false)))
    }

    @Test(arguments: [UTType.rtf, .rtfd, .plainText, .html, UTType("net.daringfireball.markdown")!,
                      UTType("org.openxmlformats.wordprocessingml.document")!])
    func textDocumentsBecomePDF(type: UTType) {
        #expect(FlixConversionPlanner.decision(type: type, byteSize: 40_000, isFile: true, demand: demand([.pdf]))
            == .convert(FlixConversionRecipe(format: .pdf)))
    }

    @Test func unconvertibleFilesAreSaidSo() {
        // A PDF over the limit cannot be made smaller here.
        #expect(FlixConversionPlanner.decision(type: .pdf, byteSize: 9_000_000, isFile: true, demand: demand([.pdf], max: 5_000_000))
            == .unconvertible)
        // A document for an image-only page.
        #expect(FlixConversionPlanner.decision(type: .rtf, byteSize: 1_000, isFile: true, demand: demand([.jpeg, .png])) == .unconvertible)
        // A zip, or a file of unknown type.
        #expect(FlixConversionPlanner.decision(type: .zip, byteSize: 1_000, isFile: true, demand: demand([.pdf])) == .unconvertible)
        #expect(FlixConversionPlanner.decision(type: nil, byteSize: 1_000, isFile: true, demand: demand([.pdf])) == .unconvertible)
    }

    @Test func convertedCopiesKeepTheirName() {
        #expect(FlixConversionPlanner.convertedName(for: "Scan 12.HEIC", format: .pdf) == "Scan 12.pdf")
        #expect(FlixConversionPlanner.convertedName(for: "notes.md", format: .pdf) == "notes.pdf")
        #expect(FlixConversionPlanner.convertedName(for: "README", format: .jpeg) == "README.jpg")
    }

    @Test @MainActor func dragLabelsDescribeTheConversion() {
        let pdf = FlixPreparedConversion(url: URL(fileURLWithPath: "/tmp/a.pdf"), bytes: 1_200_000,
                                         recipe: FlixConversionRecipe(format: .pdf), sourceModified: nil, createdAt: .now)
        let resized = FlixPreparedConversion(url: URL(fileURLWithPath: "/tmp/b.jpg"), bytes: 900_000,
                                             recipe: FlixConversionRecipe(format: .jpeg, maximumBytes: 1_000_000, isResizeOnly: true),
                                             sourceModified: nil, createdAt: .now)
        #expect(FlixDragInterceptor.label(for: [pdf])?.contains("PDF") == true)
        #expect(FlixDragInterceptor.label(for: [pdf, pdf])?.contains("2") == true)
        #expect(FlixDragInterceptor.label(for: [pdf, resized]) != FlixDragInterceptor.label(for: [pdf, pdf]))
        #expect(FlixDragInterceptor.label(for: []) == nil)
    }

    // MARK: Sensitive rules

    @Test func passportMachineReadableZoneIsAnID() {
        let text = """
        PASSPORT
        P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
        L898902C36UTO7408122F1204159ZE184226B<<<<<10
        """
        #expect(FlixSensitiveRules.kind(forText: text) == .identity)
    }

    @Test func twoIDWordsAreAnID() {
        #expect(FlixSensitiveRules.kind(forText: "Personalausweis\nGeburtsdatum 12.08.1974\nStaatsangehörigkeit DEUTSCH") == .identity)
        // One word alone is ordinary mail.
        #expect(FlixSensitiveRules.kind(forText: "Remember to renew your passport before the trip.") == nil)
    }

    @Test func validIBANsAreBankDetails() {
        #expect(FlixSensitiveRules.kind(forText: "Please pay to DE89 3704 0044 0532 0130 00 by Friday") == .bank)
        #expect(FlixSensitiveRules.kind(forText: "IBAN: GB82WEST12345698765432") == .bank)
        // Same shape, wrong check digits.
        #expect(!FlixSensitiveRules.containsValidIBAN("Order DE00 3704 0044 0532 0130 00"))
    }

    @Test func accountWordsAndCardsAreBankDetails() {
        #expect(FlixSensitiveRules.kind(forText: "Account number 12345678\nRouting number 021000021") == .bank)
        #expect(FlixSensitiveRules.kind(forText: "Card 4111 1111 1111 1111 exp 12/29") == .bank)
        #expect(FlixSensitiveRules.kind(forText: "Card 4111 1111 1111 1112 exp 12/29") == nil)
        // "bic" only as a word: "bicycle" does not count.
        #expect(FlixSensitiveRules.kind(forText: "bicycle iban") == nil)
    }

    @Test func keysAndPasswordFilesAreSecrets() {
        #expect(FlixSensitiveRules.kind(forText: "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1r") == .secret)
        #expect(FlixSensitiveRules.kind(forText: "-----BEGIN CERTIFICATE-----\nMIID") == .secret)
        #expect(FlixSensitiveRules.kind(forFileName: "server.pem") == .secret)
        #expect(FlixSensitiveRules.kind(forFileName: "Vault.kdbx") == .secret)
        #expect(FlixSensitiveRules.kind(forFileName: "id_ed25519") == .secret)
        #expect(FlixSensitiveRules.kind(forFileName: "Passwords 2026.txt") == .secret)
        #expect(FlixSensitiveRules.kind(forFileName: "Quarterly report.pdf") == nil)
    }

    @Test func ordinaryTextIsNotSensitive() {
        #expect(FlixSensitiveRules.kind(forText: "Meeting notes: ship Flix Files, review the dock tile, invoice #4411") == nil)
        #expect(FlixSensitiveRules.kind(forText: "") == nil)
    }

    @Test func outsideTargetsAreBrowsersMailAndChat() {
        #expect(FlixAppCategory.browser.isOutside && FlixAppCategory.mail.isOutside && FlixAppCategory.chat.isOutside)
        #expect(!FlixAppCategory.finder.isOutside && !FlixAppCategory.office.isOutside && !FlixAppCategory.none.isOutside)
        #expect(FlixAppCategory.from(appStoreCategory: "public.app-category.social-networking") == .chat)
    }
}
