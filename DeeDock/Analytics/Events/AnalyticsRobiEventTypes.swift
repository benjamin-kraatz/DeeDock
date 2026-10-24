/// Where the context in Robi's prompt bar came from.
nonisolated enum AnalyticsRobiContext: String, AnalyticsToken {
    case selection, region, window

    init(_ kind: RobiContextKind) {
        switch kind {
        case .selection: self = .selection
        case .region: self = .region
        case .window: self = .window
        }
    }
}

/// Which model answered a Robi request.
nonisolated enum AnalyticsRobiModel: String, AnalyticsToken {
    case onDevice = "on_device", claude

    init(_ model: RobiAnswerModel) {
        switch model {
        case .onDevice: self = .onDevice
        case .claude: self = .claude
        }
    }
}

/// The suggestion a Robi request came from; `suggested` for a question Apple Intelligence
/// suggested, `custom` for a typed question. Never the question itself.
nonisolated enum AnalyticsRobiIntent: String, AnalyticsToken {
    case explain, translate, summarize, doIt = "do_it"
    case proofread, improve, shorten, formal, friendly, reply
    case actionItems = "action_items"
    case suggested, custom

    init(_ intent: RobiIntent) {
        switch intent {
        case .explain: self = .explain
        case .translate: self = .translate
        case .summarize: self = .summarize
        case .doIt: self = .doIt
        case .proofread: self = .proofread
        case .improve: self = .improve
        case .shorten: self = .shorten
        case .formal: self = .formal
        case .friendly: self = .friendly
        case .reply: self = .reply
        case .actionItems: self = .actionItems
        case .suggested: self = .suggested
        case .custom: self = .custom
        }
    }
}

/// How a Robi request ended.
nonisolated enum AnalyticsRobiOutcome: String, AnalyticsToken {
    /// A text answer arrived.
    case answered
    /// The model proposed a menu command.
    case proposed
    /// The model or the network failed.
    case failed
    /// The person stopped the answer before it was complete.
    case stopped
    /// The on-device model was not available on this Mac.
    case unavailable
    /// Claude was chosen but no API key was saved.
    case keyMissing = "key_missing"
}

/// What the person did with a Robi answer.
nonisolated enum AnalyticsRobiAction: String, AnalyticsToken {
    case copy, replace, paste
    case runCommand = "run_command"
}
