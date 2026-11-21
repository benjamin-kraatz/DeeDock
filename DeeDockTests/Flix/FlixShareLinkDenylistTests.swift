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

    /// The standard share routes of the file-sharing services, checked through the sanitizer.
    @Test(arguments: [
        // MediaFire
        "https://www.mediafire.com/file/abc123def456/report.pdf/file", "https://www.mediafire.com/folder/abc123def/Holiday",
        "https://www.mediafire.com/view/abc123def456/photo.jpg", "https://www.mediafire.com/?abc123def456",
        "https://www.mediafire.com/download/abc123def456", "https://mediafire.com/file_premium/abc123/x.zip",
        "https://download1234.mediafire.com/key123/abc123def456/report.pdf", "https://app.mediafire.com/abc123def456",
        "https://www.mediafire.com/abc123def456gh",
        // Dropbox
        "https://www.dropbox.com/s/abc123/report.pdf?dl=0", "https://www.dropbox.com/scl/fi/abc123/report.pdf?rlkey=x",
        "https://www.dropbox.com/scl/fo/abc123/def?rlkey=x", "https://www.dropbox.com/sh/abc123/def",
        "https://www.dropbox.com/t/AbCdEf", "https://www.dropbox.com/l/scl/AbC", "https://www.dropbox.com/request/AbC",
        "https://dl.dropboxusercontent.com/s/abc123/report.pdf", "https://db.tt/AbCdEf",
        // Box
        "https://app.box.com/s/abc123", "https://company.app.box.com/s/abc123", "https://app.box.com/v/custom-name",
        "https://app.box.com/shared/static/abc123.pdf", "https://app.box.com/f/abc123",
        // WeTransfer
        "https://wetransfer.com/downloads/abc/def", "https://we.tl/t-AbCdEf", "https://collect.wetransfer.com/board/abc",
        // pCloud
        "https://u.pcloud.link/publink/show?code=XZabc", "https://e.pcloud.link/publink/show?code=XZabc",
        "https://my.pcloud.com/publink/show?code=XZabc", "https://filedn.com/labc123/report.pdf",
        // Google Drive and Docs
        "https://drive.google.com/drive/folders/1AbC?usp=sharing", "https://drive.google.com/drive/u/0/folders/1AbC",
        "https://drive.google.com/open?id=1AbC", "https://drive.google.com/uc?id=1AbC&export=download",
        "https://drive.usercontent.google.com/download?id=1AbC", "https://docs.google.com/document/d/e/2PACX-1vAbC/pub",
        "https://docs.google.com/uc?export=download&id=1AbC",
        // OneDrive
        "https://1drv.ms/u/s!AbCdEf", "https://1drv.ms/f/s!AbCdEf",
        "https://onedrive.live.com/redir?resid=ABC!123&authkey=!AbC", "https://onedrive.live.com/embed?resid=ABC!123",
        "https://onedrive.live.com/download?resid=ABC!123", "https://onedrive.live.com/?redeem=aHR0cHM6Ly8xZHJ2",
        "https://onedrive.live.com/:w:/g/personal/abc/EAbC",
        // iCloud
        "https://www.icloud.com/iclouddrive/0abcDEF#Report", "https://www.icloud.com/share/0abc",
        "https://www.icloud.com/attachment/?u=https%3A%2F%2Fcvws.icloud-content.com", "https://www.icloud.com/sharedalbum/#B0abc",
        "https://share.icloud.com/photos/0abc",
        // MEGA
        "https://mega.nz/file/abc#key", "https://mega.nz/folder/abc#key", "https://mega.io/file/abc", "https://mega.co.nz/#!abc!key",
    ])
    func fileShareRoutesAreNeverStored(address: String) throws {
        #expect(FlixURLSanitizer.clean(try #require(URL(string: address))) == .skipped)
    }

    @Test(arguments: [
        ("https://www.mediafire.com/", "https://www.mediafire.com/"),
        ("https://www.mediafire.com/upgrade/", "https://www.mediafire.com/upgrade/"),
        ("https://www.dropbox.com/plans", "https://www.dropbox.com/plans"),
        ("https://www.box.com/pricing", "https://www.box.com/pricing"),
        ("https://docs.google.com/document/d/1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcdef/edit",
         "https://docs.google.com/document/d/1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcdef/edit"),
    ])
    func ordinaryPagesOfFileSharingServicesAreKept(address: String, stored: String) throws {
        #expect(FlixURLSanitizer.sanitize(try #require(URL(string: address)))?.absoluteString == stored)
    }

    @Test func skippedSharesCountAsARemovedSecret() throws {
        #expect(FlixURLSanitizer.removedSecretCount(try #require(URL(string: "https://bit.ly/3xYz"))) == 1)
    }
}
