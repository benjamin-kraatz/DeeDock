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

/// The suggestion a Robi request came from; `custom` for a typed question.
nonisolated enum AnalyticsRobiIntent: String, AnalyticsToken {
    case explain, translate, summarize, doIt = "do_it", custom

    init(_ intent: RobiIntent) {
        switch intent {
        case .explain: self = .explain
        case .translate: self = .translate
        case .summarize: self = .summarize
        case .doIt: self = .doIt
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
