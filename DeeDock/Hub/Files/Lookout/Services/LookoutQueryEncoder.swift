import Foundation
import os

/// The client of `LookoutQueryService`, the query encoder embedded in DOKK.app: words always, pictures on demand.
///
/// The connection opens on the first call. The service exits 120 s after its last call, which interrupts the
/// connection: the next call relaunches it (NSXPC does that by itself) and pays the cold start, so `isWarm` turns false
/// on interruption. An invalidated connection (the service can't be found) is dropped and a new one is made for the
/// next call. Every call has an error handler, a time limit and honours cancellation (`LookoutXPCReply`).
///
/// Pictures aren't cached: each drop or paste is a new picture, and keeping its vector would keep something derived
/// from it after the search ends.
///
/// Main actor: the connection, the warm flags and the cache are only touched there. XPC handlers hop to the main
/// queue before touching them.
@MainActor final class LookoutQueryEncoder: LookoutQueryEncoding {
    /// A query's time limit. A warm query takes 10–15 ms; a cold one about 0.4 s, or about 5 s once after an install
    /// while Metal compiles shaders.
    static let embedTimeout: Duration = .seconds(10)
    /// A warm-up's time limit: the cold start plus the shader compile, with room to spare.
    static let warmUpTimeout: Duration = .seconds(30)
    /// A picture's time limit. A warm one takes 0.25–0.6 s; a cold one up to about 1.2 s more while the image encoder
    /// loads, and the text model's shader compile once after an install (about 5 s).
    static let pictureTimeout: Duration = .seconds(20)

    private let serviceName: String
    private var connection: NSXPCConnection?
    private(set) var isWarm = false
    private(set) var isPictureReaderWarm = false
    /// Bumped on every interruption, so a reply from a process that has since exited doesn't mark the new one warm.
    private var processGeneration = 0
    private var cache = LookoutQueryVectorCache(limit: 64)

    /// - Parameter serviceName: `LookoutServiceNames.query(appBundleIdentifier:)`.
    init(serviceName: String) {
        self.serviceName = serviceName
    }

    isolated deinit {
        connection?.invalidate()
    }

    func warmUp() async throws {
        let generation = processGeneration
        do {
            try await call(timeout: Self.warmUpTimeout) { (service, reply: LookoutXPCReply<Void>) in
                service.warmUp { error in
                    reply.finish(error.map { .failure(LookoutEncoderError.service($0)) } ?? .success(()))
                }
            }
            if generation == processGeneration { isWarm = true }
        } catch {
            if !(error is CancellationError) { isWarm = false }
            throw error
        }
    }

    func embed(query: String) async throws -> [Float] {
        if let cached = cache[query] { return cached }
        let generation = processGeneration
        do {
            let data = try await call(timeout: Self.embedTimeout) { (service, reply: LookoutXPCReply<Data>) in
                service.embedQueries([Prompts.query(query)]) { data, error in
                    if let data { reply.finish(.success(data)) } else {
                        reply.finish(.failure(LookoutEncoderError.service(error ?? "no reply")))
                    }
                }
            }
            guard let vector = QueryVectorRows.decode(data)?.first, vector.count == QueryVectorRows.dimension else {
                throw LookoutEncoderError.badReply
            }
            if generation == processGeneration { isWarm = true }
            cache[query] = vector
            return vector
        } catch {
            if !(error is CancellationError) { isWarm = false }
            throw error
        }
    }

    func warmUpPictureReader() async throws {
        let generation = processGeneration
        do {
            try await call(timeout: Self.warmUpTimeout) { (service, reply: LookoutXPCReply<Void>) in
                service.warmUpPictureReader { error in
                    reply.finish(error.map { .failure(LookoutEncoderError.service($0)) } ?? .success(()))
                }
            }
            if generation == processGeneration { (isWarm, isPictureReaderWarm) = (true, true) }
        } catch {
            if !(error is CancellationError) { isPictureReaderWarm = false }
            throw error
        }
    }

    func embed(picture: QueryPicture) async throws -> [Float] {
        let generation = processGeneration
        do {
            let data = try await call(timeout: Self.pictureTimeout) { (service, reply: LookoutXPCReply<Data>) in
                service.embedPicture(picture.pixels, width: picture.width, height: picture.height) { data, error in
                    if let data { reply.finish(.success(data)) } else {
                        reply.finish(.failure(LookoutEncoderError.service(error ?? "no reply")))
                    }
                }
            }
            guard let vector = QueryVectorRows.decode(data)?.first, vector.count == QueryVectorRows.dimension else {
                throw LookoutEncoderError.badReply
            }
            if generation == processGeneration { (isWarm, isPictureReaderWarm) = (true, true) }
            return vector
        } catch {
            if !(error is CancellationError) { isPictureReaderWarm = false }
            throw error
        }
    }

    func invalidate() {
        let old = connection
        connection = nil
        isWarm = false
        isPictureReaderWarm = false
        old?.invalidate()
    }

    // MARK: Connection

    private func call<Value: Sendable>(timeout: Duration,
                                       _ send: (any LookoutQueryServing, LookoutXPCReply<Value>) -> Void) async throws
        -> Value {
        let connection = liveConnection()
        return try await LookoutXPCReply<Value>.call(timeout: timeout) { reply in
            let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable error in
                LookoutLog.logger.error("Query encoder call failed: \(error.localizedDescription, privacy: .public)")
                reply.finish(.failure(LookoutEncoderError.unavailable))
            }
            guard let service = proxy as? any LookoutQueryServing else {
                reply.finish(.failure(LookoutEncoderError.unavailable))
                return
            }
            send(service, reply)
        }
    }

    private func liveConnection() -> NSXPCConnection {
        if let connection { return connection }
        let made = NSXPCConnection(serviceName: serviceName)
        made.remoteObjectInterface = NSXPCInterface(with: LookoutQueryServing.self)
        // NSXPC calls these on its own queue; state changes happen on the main actor.
        made.interruptionHandler = { @Sendable [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.interrupted() } }
        }
        let id = ObjectIdentifier(made)
        made.invalidationHandler = { @Sendable [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.invalidated(id) } }
        }
        made.resume()
        connection = made
        return made
    }

    /// The service process ended (idle exit or crash): the next call relaunches it cold.
    private func interrupted() {
        processGeneration += 1
        isWarm = false
        isPictureReaderWarm = false
    }

    private func invalidated(_ invalid: ObjectIdentifier) {
        guard let current = connection, ObjectIdentifier(current) == invalid else { return }
        connection = nil
        processGeneration += 1
        isWarm = false
        isPictureReaderWarm = false
    }
}
