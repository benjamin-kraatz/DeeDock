// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Darwin
import Foundation
import UniformTypeIdentifiers

/// What gets indexed. The defaults come from a real developer's Mac: Spotlight types 57k TypeScript files as movies,
/// one repo holds a 55k-clip dataset, and screenshot tools move screenshots into code projects.
///
/// Lookout indexes documents, PDFs, images and screenshots. Audio and video are ignored outright (Spotlight still finds
/// them by name), and code and data files are skipped, as DigUp does without its code index.
nonisolated enum Rules {
    /// What to do with one file.
    enum Classification: Equatable, Sendable {
        case index(FileKind)
        /// A reason worth reporting ("code or data file").
        case skip(String)
        /// A type we don't handle at all.
        case ignore
    }

    /// Folders never worth walking into. Hidden folders and bundles are skipped by the enumerator itself.
    static let skippedFolderNames: Set<String> = [
        "node_modules", "bower_components", "venv", "site-packages", "__pycache__", "DerivedData", "Pods", "Carthage",
    ]

    /// Any of these in a folder makes it a code project, where only screenshots are indexed.
    static let projectMarkers = [
        ".git", "package.json", "Package.swift", "pyproject.toml", "setup.py", "requirements.txt", "Cargo.toml",
        "go.mod", "pom.xml", "build.gradle", "build.gradle.kts", "Gemfile", "composer.json", "CMakeLists.txt",
    ]
    static let projectBundleExtensions: Set<String> = ["xcodeproj", "xcworkspace"]

    /// Documents, read as text (`DocExtractor`). Markup formats (reStructuredText, AsciiDoc, Org, Textile, MDX) are
    /// read as they are written, subtitles without their cue numbers and timings, LaTeX without its commands, and
    /// Safari web archives and XHTML through the HTML path (`DocumentText`).
    static let docExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "rtf", "docx", "doc", "odt", "html", "htm", "rst", "adoc", "asciidoc", "org",
        "tex", "latex", "textile", "xhtml", "mdx", "srt", "vtt", "webarchive", "rtfd",
    ]

    /// Documents that are package folders, by extension, and the file inside each one that holds its text. The crawler
    /// indexes the package as one document, and `QueuedFileGate` reads that one file inside it.
    static let packageDocuments: [String: String] = ["rtfd": "TXT.rtf"]

    /// The file inside `url` that holds its text when `url` is a package document (`packageDocuments`), else nil.
    static func packageDocumentEntry(_ url: URL) -> String? {
        packageDocuments[url.pathExtension.lowercased()]
    }

    /// Source code and data files: skipped (your editor and ripgrep search them better, and they flood an index).
    static let codeExtensions: Set<String> = [
        "py", "ipynb", "c", "h", "cc", "cpp", "cxx", "hpp", "hh", "m", "mm", "swift", "tsx", "cts", "js", "jsx", "mjs",
        "cjs", "go", "rs", "java", "kt", "kts", "scala", "rb", "php", "cs", "fs", "sh", "bash", "zsh", "fish", "ps1",
        "lua", "pl", "r", "jl", "dart", "sql", "vue", "svelte", "css", "scss", "sass", "less", "json", "jsonl", "yaml",
        "yml", "toml", "xml", "plist", "gradle", "cmake", "mk", "lock", "log", "csv", "tsv", "ini", "cfg", "conf",
        "proto", "graphql", "tf", "nix", "zig", "hs", "ex", "exs", "erl", "clj", "elm", "ml", "vim", "el", "asm",
        "metal", "glsl", "hlsl", "wgsl", "cu", "pyi", "pyc",
    ]

    static let screenshotPrefixes = ["Screenshot", "Screen Shot", "CleanShot", "SCR-"]

    /// Decides what a file is from its name, its type and its screen-capture attribute. It never opens the file: the
    /// crawler classifies before its `lstat` check, so the file may still be a FIFO (opening one with no writer blocks
    /// forever), a link, or a placeholder whose contents a read would download.
    static func classify(_ url: URL, type: UTType?, options: IndexOptions) -> Classification {
        let ext = url.pathExtension.lowercased()
        if options.excludedExtensions.contains(ext) { return .skip("excluded type") }
        if isSecret(url.lastPathComponent) { return .skip("key or password file") }
        // .ts and .mts are usually TypeScript, which Spotlight calls MPEG-2 video; .m2ts is only video. Lookout indexes
        // neither, so none is read to tell them apart (DigUp sniffed the first bytes for its video index).
        if ext == "ts" || ext == "mts" { return .skip("code or data file") }
        if ext == "m2ts" { return .ignore }
        if docExtensions.contains(ext) { return .index(.doc) }
        if codeExtensions.contains(ext) { return .skip("code or data file") }
        guard let type else { return .ignore }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return .skip("code or data file") }
        if type.conforms(to: .pdf) { return .index(.pdf) }
        if isPicture(type) { return .index(isScreenshot(url) ? .screenshot : .image) }
        return .ignore   // audio, video, SVG and everything else
    }

    /// Whether files of `type` are pictures Lookout reads: images, but not SVG. macOS types SVG as an image, yet ImageIO
    /// can't decode it, so it would only ever fail; it's ignored like any other type Lookout doesn't handle.
    static func isPicture(_ type: UTType) -> Bool {
        type.conforms(to: .image) && !type.conforms(to: .svg)
    }

    /// Keys, certificates, password and credential files: never read, wherever they are.
    static func isSecret(_ name: String) -> Bool {
        let lower = name.lowercased()
        let secretTypes: Set<String> = ["pem", "key", "p12", "pfx", "keystore", "jks", "ppk", "kdbx", "gpg", "asc",
                                        "crt", "cer", "der", "p8", "mobileprovision"]
        if secretTypes.contains((lower as NSString).pathExtension) { return true }
        return ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", ".env", "secret", "credential", ".netrc", ".npmrc",
                ".pypirc", "htpasswd", ".htpasswd"].contains(where: lower.hasPrefix)
    }

    /// macOS marks screenshots with an extended attribute that survives moves and copies; names are the fallback. The
    /// attribute is read from the entry itself (`XATTR_NOFOLLOW`), never from a link's target.
    static func isScreenshot(_ url: URL) -> Bool {
        if getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, XATTR_NOFOLLOW) > 0 { return true }
        let name = url.lastPathComponent
        return screenshotPrefixes.contains { name.hasPrefix($0) }
    }

    /// Why the crawler doesn't walk into `url`, or nil. `excluded` are the skipped folders that apply inside the root
    /// being walked.
    static func skipReason(forFolder url: URL, home: String, excluded: [String]) -> String? {
        let name = url.lastPathComponent
        if skippedFolderNames.contains(name) { return "developer folder" }
        if name.hasSuffix(".noindex") { return ".noindex folder" }
        if url.path == home + "/Library" { return "~/Library" }
        if excluded.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) { return "excluded folder" }
        return nil
    }

    /// Why a folder can't be a root, a folder Lookout walks. The app refuses these when they're picked
    /// (`LookoutFolderChoice`), and the service and the crawler check every saved root again before each walk, on its
    /// real path: a chosen folder that has since become a symbolic link to `~/Library` resolves there and is refused.
    enum RootRefusal: String, Sendable, Equatable {
        /// `/`, or `/Volumes` itself: every volume and the system. `FolderSelection`'s prefix rules can't express "/"
        /// as a parent either.
        case wholeDisk
        /// The home folder, or a folder around it such as `/Users`: it holds ~/Library and everything else at once.
        case homeFolder
        /// ~/Library or a folder inside it, which Lookout never reads, apart from the cloud folders `isCloudFolder` allows.
        case library
        /// A folder with a hidden component (`.ssh`, `.config`): the crawler never walks into those either.
        case hidden
        /// An app, a library bundle or another package, or a folder inside one.
        case bundle
        /// The system's own folders (`systemFolders`).
        case system

        /// The reason a crawl report gives for a refused root.
        var reason: String {
            switch self {
            case .wholeDisk: "the whole disk"
            case .homeFolder: "the home folder"
            case .library: "~/Library"
            case .hidden: "hidden folder"
            case .bundle: "app or bundle"
            case .system: "system folder"
            }
        }
    }

    /// Folders of the system, refused as roots with everything inside them. `/etc`, `/var` and `/tmp` aren't listed:
    /// they are links into `/private`, and the checks run on real paths.
    ///
    /// `/private` has two exceptions: folders inside `/private/tmp` and inside the user's own temporary folder may be
    /// roots. Both hold scratch files people make themselves (and the tests' folders). The rest of `/private`
    /// (`/private/etc`, `/private/var/db`, other apps' caches in `/private/var/folders`) is the system's.
    static let systemFolders = ["/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/private", "/dev",
                                "/cores", "/Network"]

    /// The real path of this user's temporary folder (`/private/var/folders/…/T`).
    static let temporaryFolder: String = {
        let path = (NSTemporaryDirectory() as NSString).standardizingPath
        return FolderSelection.realPath(path)
    }()

    /// Why `path` can't be a root, or nil when it can. The check doesn't resolve links: pass a real path
    /// (`FolderSelection.realPath`, or use `checkRoots`) to check where a folder really is. It looks up only whether
    /// each folder on the way is a package.
    ///
    /// - Parameters:
    ///   - home: The home folder (tests pass a folder of their own). It's compared as given and as its real path.
    ///   - temporary: The user's temporary folder (`temporaryFolder`), which may hold roots although it's in
    ///     `/private`.
    static func rootRefusal(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                            temporary: String = temporaryFolder) -> RootRefusal? {
        let path = normalizedFolder(path)
        if path.isEmpty || path == "/" || path == "/Volumes" { return .wholeDisk }
        let homes = Set([normalizedFolder(home), FolderSelection.realPath(normalizedFolder(home))])
        if homes.contains(where: { path == $0 || FolderSelection.isInside($0, path) }) { return .homeFolder }
        for home in homes where path == home + "/Library" || FolderSelection.isInside(path, home + "/Library") {
            if !isCloudFolder(path, home: home) { return .library }
        }
        let components = path.split(separator: "/")
        if components.contains(where: { $0.hasPrefix(".") }) { return .hidden }
        let inside = { (folder: String) in path == folder || FolderSelection.isInside(path, folder) }
        if systemFolders.contains(where: inside) {
            let scratch = ["/private/tmp", normalizedFolder(temporary)]
            guard scratch.contains(where: { FolderSelection.isInside(path, $0) }) else { return .system }
        }
        // Packages last: they cost a lookup per folder on the way (a few, once per root and walk).
        var folder = ""
        for component in components {
            folder += "/" + component
            let values = try? URL(fileURLWithPath: folder, isDirectory: true).resourceValues(forKeys: [.isPackageKey])
            if values?.isPackage == true { return .bundle }
        }
        return nil
    }

    /// Whether `path` (inside `home`'s Library) is a cloud folder people keep their files in, or inside one: a File
    /// Provider folder in `~/Library/CloudStorage` (Dropbox, Google Drive, OneDrive, which `~/Dropbox` and the like
    /// link to), or iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs`). `CloudStorage` and
    /// `Mobile Documents` themselves stay refused, as do other apps' containers in `Mobile Documents`. Their
    /// placeholders that aren't downloaded are still skipped file by file.
    static func isCloudFolder(_ path: String, home: String) -> Bool {
        let storage = home + "/Library/CloudStorage"
        let iCloudDrive = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        return FolderSelection.isInside(path, storage) || path == iCloudDrive || FolderSelection.isInside(path, iCloudDrive)
    }

    /// An absolute path with `.`, `..`, repeated and trailing slashes resolved by its text alone. Not
    /// `standardizingPath`, which turns `/private/etc` into `/etc` and would hide a real path's system folder from
    /// `rootRefusal`. Empty stays empty.
    static func normalizedFolder(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        var components: [Substring] = []
        for component in path.split(separator: "/") where component != "." {
            if component == ".." { _ = components.popLast() } else { components.append(component) }
        }
        return "/" + components.joined(separator: "/")
    }

    /// The real path of each of `paths` that may be a root, and the rest with why not. A path is checked as given and
    /// where it really is: "~/Notes" that has become a link to ~/Library is refused. A path that isn't there right now
    /// (an unplugged drive) resolves to itself.
    static func checkRoots(_ paths: [String], home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                           temporary: String = temporaryFolder)
        -> (allowed: [String], refused: [(path: String, refusal: RootRefusal)]) {
        var allowed: [String] = [], refused: [(path: String, refusal: RootRefusal)] = []
        for path in paths {
            let given = normalizedFolder(path)
            let real = FolderSelection.realPath(given)
            if let refusal = rootRefusal(given, home: home, temporary: temporary)
                ?? rootRefusal(real, home: home, temporary: temporary) {
                refused.append((path, refusal))
            } else {
                allowed.append(real)
            }
        }
        return (allowed, refused)
    }

    static func isProjectRoot(_ folder: String) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return false }
        let set = Set(names)
        return projectMarkers.contains(where: set.contains)
            || names.contains { projectBundleExtensions.contains(($0 as NSString).pathExtension) }
    }

    static let cameraPrefixes = ["img", "dsc", "pxl", "mvimg", "vid", "gopr", "dji", "photo", "whatsapp", "screenshot"]

    /// Machine-made names like "clip_000123", "frame-0042" or "3f9a1c0e-…", but not camera names like "IMG_1234".
    static func looksMachineNamed(_ stem: String) -> Bool {
        let name = stem.lowercased()
        if cameraPrefixes.contains(where: { name.hasPrefix($0) }) { return false }
        if name.range(of: #"^[0-9a-f]{8,}([-_][0-9a-f]{4,})*$"#, options: .regularExpression) != nil { return true }
        return name.range(of: #"^[a-z]{0,16}[-_. ]?\d{3,}([-_.]\d+)*$"#, options: .regularExpression) != nil
    }

    /// Folders with hundreds of machine-named images: training data, not your stuff. They're skipped (and reported)
    /// instead of being indexed silently. Roots you pick yourself are never datasets.
    static func datasetFolders(_ files: [(folder: String, stem: String, kind: FileKind)], roots: Set<String>,
                               minimum: Int = 300) -> [String: Int] {
        var groups: [String: [String]] = [:]
        for file in files where file.kind == .image && !roots.contains(file.folder) {
            groups[file.folder, default: []].append(file.stem)
        }
        var datasets: [String: Int] = [:]
        for (folder, stems) in groups where stems.count >= minimum {
            let machine = stems.filter(looksMachineNamed).count
            if Double(machine) / Double(stems.count) >= 0.7 { datasets[folder] = stems.count }
        }
        return datasets
    }
}
