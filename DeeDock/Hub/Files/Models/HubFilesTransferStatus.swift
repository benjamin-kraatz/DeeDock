import Foundation

/// What the status bar shows for the copy/move queue: the job in progress, or one that just ended.
struct HubFilesTransferStatus: Equatable {
    enum Phase: Equatable {
        case running
        case paused
        case finished
        case cancelled
        case failed(String)
    }

    var jobID: UUID
    var kind: HubFileTransferQueue.Kind
    var itemCount: Int
    /// 0...1.
    var fraction: Double
    var phase: Phase
    var sourceName: String
    var destinationName: String
    /// Jobs waiting behind this one.
    var queuedCount: Int

    init(jobID: UUID = UUID(), kind: HubFileTransferQueue.Kind, itemCount: Int, fraction: Double, phase: Phase,
         sourceName: String, destinationName: String, queuedCount: Int = 0) {
        self.jobID = jobID
        self.kind = kind
        self.itemCount = itemCount
        self.fraction = fraction
        self.phase = phase
        self.sourceName = sourceName
        self.destinationName = destinationName
        self.queuedCount = queuedCount
    }

    init(_ job: HubFileTransferQueue.Job, queuedCount: Int) {
        let phase: Phase = switch job.state {
        case .running: .running
        case .paused: .paused
        case .finished: .finished
        case .cancelled: .cancelled
        case .failed(let message): .failed(message)
        }
        self.init(jobID: job.id, kind: job.kind, itemCount: job.sources.count, fraction: job.fractionCompleted,
                  phase: phase, sourceName: job.sourceFolderName, destinationName: job.destinationFolderName,
                  queuedCount: queuedCount)
    }
}
