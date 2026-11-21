import Foundation

/// Every language-model task in Flix Files, with what decides where it may run.
///
/// Each task has a **cost** (cheap: small, bounded input and a short answer; expensive: a large
/// input or real reasoning), a **trigger** (background: runs by itself, once per file, window, or
/// day; on demand: only when the person asks), and whether its input must **stay on the Mac**
/// (content the person never chose to share: their files read in the background, the window in
/// front, a picture checked for ID or bank details).
///
/// ``FlixAIRouting`` turns those into an engine. Today every task but Ask Robi runs on Apple
/// Intelligence. The properties exist so a later version can send some tasks to a cloud model
/// (Claude) without revisiting every call site, and so that whatever it sends is chosen by rule:
/// background tasks run per file and could add up to thousands of paid calls, so they never leave
/// the device, however smart they are.
nonisolated enum FlixAITask: String, CaseIterable, Sendable {
    /// A typed search sentence into filter tokens. Latency-bound (3.5 s).
    case searchUnderstanding
    /// A sentence into a Smart Filter's rules.
    case smartFilter
    /// A name, emoji, and summary for a thread, from member names and captions.
    case threadName
    /// The "Where were you?" recap from thread names.
    case morningRecap
    /// What a document is and its key facts (due date, total, payment, signature), from its text.
    case documentReading
    /// A caption and name for a picture whose file name says nothing.
    case pictureCaption
    /// What the window in front wants (types, size limits), from its text.
    case windowText
    /// What the window in front wants, from its picture, when no text could be read.
    case windowPicture
    /// Whether a picture shows an ID, bank details, or a secret (the sensitive guard).
    case pictureSensitiveCheck
    /// A question about the selected files, asked in Ask Robi.
    case askRobi

    nonisolated enum Cost: Sendable { case cheap, expensive }
    nonisolated enum Trigger: Sendable { case background, onDemand }

    var cost: Cost {
        switch self {
        case .askRobi: .expensive
        default: .cheap
        }
    }

    var trigger: Trigger {
        switch self {
        case .searchUnderstanding, .smartFilter, .askRobi: .onDemand
        case .threadName, .morningRecap, .documentReading, .pictureCaption, .windowText, .windowPicture,
             .pictureSensitiveCheck: .background
        }
    }

    /// The input is content the person never chose to send anywhere.
    var staysOnDevice: Bool {
        switch self {
        case .documentReading, .pictureCaption, .windowText, .windowPicture, .pictureSensitiveCheck: true
        case .searchUnderstanding, .smartFilter, .threadName, .morningRecap, .askRobi: false
        }
    }

    /// The `$ai_span_name` AI observability reports (content is never sent, see `FlixLanguageModel`).
    /// Kept stable across renames, so dashboards keep their history.
    var span: String {
        switch self {
        case .searchUnderstanding: "flix_search_understand"
        case .smartFilter: "flix_smart_filter"
        case .threadName: "flix_thread_name"
        case .morningRecap: "flix_morning"
        case .documentReading: "flix_caption_document"
        case .pictureCaption: "flix_caption_picture"
        case .windowText: "flix_window_text"
        case .windowPicture: "flix_window_picture"
        case .pictureSensitiveCheck: "flix_sensitive_picture"
        case .askRobi: "flix_ask_robi"
        }
    }
}

/// Where a model task runs.
nonisolated enum FlixAIEngine: Sendable {
    /// Apple Intelligence on this Mac: no cost, no network.
    case appleIntelligence
    /// Claude with the person's own key: costs money per call.
    case claude
}

/// The one place that decides which engine runs a task.
nonisolated enum FlixAIRouting {
    /// Whether a task may ever be sent to a cloud model: only expensive tasks the person asked
    /// for, with input they chose to share. Everything else stays on Apple Intelligence, whatever
    /// a later setting says, so cloud cost follows the person's own actions.
    static func mayUseCloud(_ task: FlixAITask) -> Bool {
        task.cost == .expensive && task.trigger == .onDemand && !task.staysOnDevice
    }

    /// The engine for `task`.
    ///
    /// - Parameter cloudChosen: The person chose Claude for tasks that may use it. Ask Robi passes
    ///   Robi's own setting; no other setting exists yet, so every other Flix task runs on Apple
    ///   Intelligence.
    static func engine(for task: FlixAITask, cloudChosen: Bool = false) -> FlixAIEngine {
        cloudChosen && mayUseCloud(task) ? .claude : .appleIntelligence
    }
}
