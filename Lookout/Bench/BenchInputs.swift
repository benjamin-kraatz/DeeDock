import Foundation

/// The fixed inputs the bench measures with, so runs compare.
enum BenchInputs {
    /// 30 searches from one word to a long sentence, before `Prompts.query` frames them.
    static let queries = [
        "invoice",
        "tax return",
        "passport scan",
        "wedding photos 2024",
        "quarterly budget spreadsheet",
        "notes from the design review",
        "the contract with the landlord",
        "slides about onboarding new hires",
        "receipt for the new laptop charger",
        "recipe with lentils and coconut milk",
        "screenshot of the error dialog in Xcode",
        "photo of the whiteboard after the planning meeting",
        "that PDF the bank sent about the mortgage rate change",
        "draft of the blog post about migrating to Swift concurrency",
        "the presentation I gave at the conference in Berlin last spring",
        "a spreadsheet tracking monthly electricity and gas usage at home",
        "meeting notes where we decided to postpone the launch until after the holidays",
        "a scanned letter from the insurance company about the claim for the broken window",
        "the README that explains how to build the project and run the tests on a fresh machine",
        "photos from the hiking trip where we saw the waterfall and camped next to the lake overnight",
        "an email attachment with the signed offer letter and the start date for the new position",
        "the document listing every server we run, who owns it, and when its certificate expires",
        "a voice memo where I described the idea for the app while walking home from the station",
        "notes on why the payment page sometimes shows a declined error even when the card is fine",
        "the chart comparing response times before and after we added the cache in front of the database",
        "a long report on how the team handled the outage last November, with the timeline and follow-up tasks",
        "the screenshot of the settings window that shows the dock on the left edge of the second monitor",
        "something about a trip to Japan with a train to Kamakura and dinner in Shibuya on the last evening",
        "the spreadsheet with all the books I read this year, the ratings I gave them, and who recommended each one",
        "a write-up comparing three approaches to on-device search, with measurements of latency, memory use and accuracy",
    ]

    /// 16 document texts of 1,500 characters (cut at a word boundary), with titles, before `Prompts.document` frames
    /// them. Each repeats one topic's sentences with numbered variations, so no two are alike.
    static let documents: [(title: String, text: String)] = topics.map { topic in
        var text = ""
        var round = 1
        while text.count < 1_500 {
            for sentence in topic.sentences where text.count < 1_500 {
                text += (text.isEmpty ? "" : " ") + sentence.replacingOccurrences(of: "#", with: String(round))
            }
            round += 1
        }
        let cut = text.prefix(1_500)
        return (topic.title, String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)]))
    }

    private static let topics: [(title: String, sentences: [String])] = [
        ("Kitchen renovation", ["Week # of the kitchen renovation began with the electrician rewiring the outlets.",
                                "The cabinets for wall # arrived with one door scratched, so we sent it back.",
                                "Tiles for the backsplash cost # percent more than the first quote."]),
        ("Release checklist", ["Step #: confirm the build number matches the marketing version.",
                               "Before shipping, run the update feed check # times against the staging server.",
                               "Notarization of build # took eleven minutes and passed on the first try."]),
        ("Garden journal", ["On day # the tomatoes on the south bed showed their first flowers.",
                            "We watered the herb planters # times this week because of the heat.",
                            "Slugs ate # of the lettuce seedlings near the fence again."]),
        ("Incident report", ["At minute # of the outage the database connection pool was exhausted.",
                             "The on-call engineer restarted # of the worker nodes before traffic recovered.",
                             "Follow-up task #: add an alert when queue latency passes two seconds."]),
        ("Trip to Lisbon", ["Day # in Lisbon started with coffee and pastries near the river.",
                            "Tram # was full, so we walked up the hill to the castle instead.",
                            "Dinner on evening # was grilled sardines in a small place in Alfama."]),
        ("Thesis notes", ["Chapter # argues that sparse retrieval misses paraphrased questions.",
                          "Experiment # compared dense embeddings against keyword search on legal texts.",
                          "Reviewer # asked for a clearer definition of recall at ten."]),
        ("Band rehearsal", ["Rehearsal # focused on the bridge of the second song.",
                            "The drummer suggested playing the outro # beats per minute slower.",
                            "We recorded take # on a phone and it sounded better than expected."]),
        ("Apartment search", ["Viewing # was a two-room flat with a balcony facing the courtyard.",
                              "The landlord of listing # wanted three months of deposit.",
                              "Commute from option # would take forty minutes by bike."]),
        ("Fitness log", ["Session # included five sets of squats and a short run.",
                         "My resting heart rate in week # dropped to fifty-eight.",
                         "Stretching for # minutes after the run helped the sore calf."]),
        ("Customer interviews", ["Interviewee # said the export button is hard to find.",
                                 "Customer # uses the app every morning to plan deliveries.",
                                 "Theme #: people want offline access when the signal drops."]),
        ("Car maintenance", ["Service visit # replaced the brake pads on the front axle.",
                             "Tire pressure was # psi below the recommendation before the trip.",
                             "The mechanic noted oil leak # near the gasket and quoted a repair."]),
        ("Book club", ["In meeting # we discussed why the narrator never names the town.",
                       "Member # thought the ending was rushed and too neat.",
                       "Next month's pick #: a short novel about a lighthouse keeper."]),
        ("Server inventory", ["Host # runs the build cache and has two terabytes of disk.",
                              "The certificate for service # expires at the end of the quarter.",
                              "Rack # needs a new power distribution unit before winter."]),
        ("Baking experiments", ["Loaf # used a longer cold proof and had a much better crust.",
                                "Hydration of # percent made the dough too sticky to shape.",
                                "Batch # of cookies spread too much because the butter was warm."]),
        ("Budget planning", ["Line # of the budget covers software subscriptions for the team.",
                             "Travel in quarter # went over the plan by a few hundred euros.",
                             "Scenario # assumes two new hires starting in the spring."]),
        ("Birdwatching", ["Morning walk # brought a kingfisher on the willow by the canal.",
                          "We counted # sparrows at the feeder before eight.",
                          "Sighting #: a pair of herons building a nest on the island."]),
    ]
}
