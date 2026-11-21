import Foundation
import Testing
@testable import DeeDock

/// Invitations, meeting links, short links, and share secrets are never stored, however short;
/// ordinary pages on the same services still are.
struct FlixShareLinkDenylistTests {
    @Test(arguments: [
        "https://discord.gg/abc123", "https://discord.com/invite/abc123", "https://t.me/+AbCdEf123",
        "https://t.me/joinchat/AbCdEf", "https://chat.whatsapp.com/Kx12ab", "https://wa.me/4915112345678",
        "https://signal.group/#CjQKIA", "https://us02web.zoom.us/j/81234567890?pwd=abc", "https://zoom.us/my/someone",
        "https://meet.google.com/abc-defg-hij", "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0",
        "https://join.slack.com/t/team/shared_invite/zt-1abc", "https://team.slack.com/shared_invite/zt-1abc",
        "https://calendly.com/someone/30min", "https://bit.ly/3xYz", "https://t.co/AbC12", "https://tinyurl.com/y7abc",
        "https://goo.gl/maps/abc", "https://lnkd.in/eAbC", "https://cutt.ly/abc", "https://wetransfer.com/downloads/abc/def",
        "https://we.tl/t-AbCdEf", "https://docsend.com/view/abc123", "https://1drv.ms/w/s!AbC", "https://mega.nz/file/abc#key",
        "https://www.icloud.com/iclouddrive/0abcDEF#Report", "https://www.icloud.com/share/0abc", "https://app.box.com/s/abc123",
        "https://www.dropbox.com/scl/fi/abc/report.pdf", "https://drive.google.com/file/d/1AbC/view?usp=sharing",
        "https://drive.google.com/drive/folders/1AbC", "https://team.notion.site/Public-page-0123456789abcdef0123456789abcdef",
        "https://contoso.sharepoint.com/:w:/g/personal/someone/EAbC", "https://contoso.sharepoint.com/:x:/s/site/EAbC",
    ])
    func sharesAndInvitationsAreNeverStored(address: String) throws {
        #expect(FlixURLSanitizer.clean(try #require(URL(string: address))) == .skipped)
    }

    @Test(arguments: [
        ("https://zoom.us/pricing", "https://zoom.us/pricing"),
        ("https://discord.com/developers/docs/intro", "https://discord.com/developers/docs/intro"),
        ("https://drive.google.com/file/d/1AbC/view", "https://drive.google.com/file/d/1AbC"),
        ("https://drive.google.com/file/d/1AbC", "https://drive.google.com/file/d/1AbC"),
        ("https://docs.google.com/document/d/1AbC/edit?usp=sharing", "https://docs.google.com/document/d/1AbC/edit"),
        ("https://contoso.sharepoint.com/:w:/r/sites/team/Doc.docx", "https://contoso.sharepoint.com/:w:/r/sites/team/Doc.docx"),
        ("https://www.icloud.com/", "https://www.icloud.com/"),
    ])
    func ordinaryPagesOnTheseServicesAreKept(address: String, stored: String) throws {
        #expect(FlixURLSanitizer.sanitize(try #require(URL(string: address)))?.absoluteString == stored)
    }

    @Test func skippedSharesCountAsARemovedSecret() throws {
        #expect(FlixURLSanitizer.removedSecretCount(try #require(URL(string: "https://bit.ly/3xYz"))) == 1)
    }
}
