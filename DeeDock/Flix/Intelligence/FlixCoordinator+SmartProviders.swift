import Foundation

extension FlixCoordinator {
    /// Installs phase B2's providers: search in plain words, Threads, annotations (captions, names,
    /// facts, folders, versions), Where was I?, More like this, Smart Filters from a sentence, Tidy,
    /// drag memory with the filter tip, and Ask Robi. Phase B1's providers (Fits, drag hooks) are
    /// installed apart and left untouched here.
    ///
    /// Call once, before ``start()``. The providers share one `FlixSmartServices` (Lookout, the
    /// analysis and topic caches); their own background work stops, and their caches are written,
    /// through ``stopProviders`` when Flix Files stops.
    ///
    /// - Parameters:
    ///   - lookout: The Hub's Lookout engine; nil (or Lookout off) falls back to names, folders, and time.
    ///   - robi: Robi's settings and key; nil leaves Ask Robi out.
    func installSmartProviders(lookout: LookoutEngine?, robi: RobiStore?) {
        let services = FlixSmartServices(lookout: lookout, settingsStore: settingsStore, history: history,
                                         intelligence: intelligence, panelState: panelState,
                                         storage: FlixSmartServices.liveStorage) { [weak self] in
            self?.readPolicy ?? FlixReadPolicy(allowedRoots: [])
        }
        services.load()
        // Fits this window (phase B1) matches by meaning through the same Lookout window.
        contextServices?.fits.semantic = services.semantic
        let annotations = FlixAnnotationProvider(services: services)
        let threads = FlixThreadProvider(services: services)
        let similarity = FlixSimilarityProvider(services: services)
        let memory = FlixDragMemoryProvider(services: services)
        services.activityObservers.append { [weak memory] items in memory?.observe(items) }
        services.activityObservers.append { [weak similarity] _ in similarity?.warmSmartFilters() }

        // Each slot is set on the existing value, never by assigning a fresh one, so phase B1's
        // providers (Fits, drag hooks) stay whatever order the two installs run in.
        intelligence.providers.search = FlixSearchProvider(services: services)
        intelligence.providers.threads = threads
        intelligence.providers.annotations = annotations
        intelligence.providers.morning = FlixMorningProvider(defaults: services.storage == nil ? nil : .standard)
        intelligence.providers.similarity = similarity
        intelligence.providers.smartFilters = FlixSmartFilterProvider(services: services)
        intelligence.providers.tidy = FlixTidyProvider(services: services)
        intelligence.providers.robi = robi.map { FlixRobiProvider(store: $0, services: services) }
        intelligence.providers.dragMemory = memory

        // Settings' "What powers it" follows Lookout, Apple Intelligence, and Robi as they change.
        let engines = FlixEngineMonitor(intelligence: intelligence, lookout: lookout, robi: robi)
        engines.start()

        stopProviders.append {
            engines.stop()
            annotations.stop()
            threads.stop()
            similarity.stop()
            memory.stop()
            services.stop()
        }
    }
}
