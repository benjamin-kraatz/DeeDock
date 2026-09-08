// Compile with LauncherSuggestionModels.swift and LauncherSuggestionBaseline.swift.
// Synthetic mechanics and chronological comparison only; never reads app history.
import Foundation
import CoreML

@main enum SuggestionBenchmark {
static let configuration: MLModelConfiguration = {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuOnly
    return configuration
}()
static let date = Date(timeIntervalSince1970: 1_800_000_000)

static func context(_ category: Int) -> LauncherSuggestionContext {
    LauncherSuggestionContext(date: date, foregroundID: "source.\(category)", modeID: "work", hour: category % 24, weekday: 2)
}

static func example(_ category: Int, label: String? = nil) throws -> MLDictionaryFeatureProvider {
    let array = try MLMultiArray(shape: [256], dataType: .float32)
    for (i, value) in context(category).featureVector.enumerated() { array[i] = NSNumber(value: value) }
    var dictionary: [String: Any] = ["context": array]
    if let label { dictionary["appIdentity"] = label }
    return try MLDictionaryFeatureProvider(dictionary: dictionary)
}

static func scores(_ model: MLModel, _ category: Int) throws -> [String: Double] {
    let output = try model.prediction(from: example(category))
    let dictionary = output.featureValue(for: "appIdentityProbs")!.dictionaryValue
    return Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key as! String, $0.value.doubleValue) })
}

static func update(_ url: URL, examples: [MLFeatureProvider], destination: URL) throws -> (MLModel, Double) {
    let semaphore = DispatchSemaphore(value: 0)
    var outcome: Result<MLModel, Error>?
    let start = Date()
    let task = try MLUpdateTask(forModelAt: url, trainingData: MLArrayBatchProvider(array: examples), configuration: configuration) { context in
        do {
            if let error = context.task.error { throw error }
            try context.model.write(to: destination)
            outcome = .success(try MLModel(contentsOf: destination, configuration: configuration))
        } catch { outcome = .failure(error) }
        semaphore.signal()
    }
    task.resume()
    precondition(semaphore.wait(timeout: .now() + 60) == .success, "Update timed out")
    return (try outcome!.get(), Date().timeIntervalSince(start))
}

static func main() throws {
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let seed = try MLModel.compileModel(at: URL(fileURLWithPath: CommandLine.arguments[1]))
defer { try? FileManager.default.removeItem(at: seed) }
let empty = try MLModel(contentsOf: seed, configuration: configuration)
print("emptyScores", try scores(empty, 0))
let firstURL = directory.appendingPathComponent("first.mlmodelc")
let first = try update(seed, examples: [example(0, label: "app.A")], destination: firstURL).0
let firstScores = try scores(first, 0)
precondition(firstScores["app.A"] == 1)
let secondURL = directory.appendingPathComponent("second.mlmodelc")
let second = try update(firstURL, examples: [example(1, label: "new.dynamic.B"), example(2, label: "app.C")], destination: secondURL).0
let ranked = try scores(second, 1)
precondition(Set(ranked.keys) == Set(["app.A", "new.dynamic.B", "app.C"]))
let reloadedScores = try scores(MLModel(contentsOf: secondURL), 1)
precondition(reloadedScores == ranked)
print("dynamicLabelsAndReload", ranked)
let rebuiltURL = directory.appendingPathComponent("rebuilt.mlmodelc")
let rebuilt = try update(seed, examples: [example(2, label: "app.C")], destination: rebuiltURL).0
let retainedScores = try scores(rebuilt, 0)
precondition(Set(retainedScores.keys) == ["app.C"])
print("rebuildForgetsRemovedLabels", retainedScores)

// Each context deterministically predicts one of 12 identities. Predict before update.
var currentURL = seed
var model = empty
var counts: [String: Int] = [:]
var transitions: [Int: [String: Int]] = [:]
var hits = [0, 0, 0, 0, 0]
var coverage = [0, 0, 0, 0, 0]
var earlyHits = [0, 0, 0, 0, 0]
var recentScores: [String: Double] = [:]
var productionExamples: [LauncherSuggestionExample] = []
let streamCount = 120
for index in 0..<streamCount {
    let category = (index * 7) % 12
    let label = "synthetic.\(category)"
    let productionScores = LauncherSuggestionBaseline.scores(context: context(category), examples: productionExamples,
        feedback: [], excluded: [], now: date)
    let rankings = [try scores(model, category), counts.mapValues(Double.init), (transitions[category] ?? [:]).mapValues(Double.init), productionScores, recentScores]
    for j in 0..<5 {
        let top = rankings[j].sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(3)
        if top.contains(where: { $0.key != "__no_suggestion__" }) { coverage[j] += 1 }
        if top.contains(where: { $0.key == label }) {
            hits[j] += 1
            if index < 12 { earlyHits[j] += 1 }
        }
    }
    counts[label, default: 0] += 1
    recentScores[label] = Double(index + 1)
    productionExamples.append(.init(context: context(category), targetID: label, date: date))
    transitions[category, default: [:]][label, default: 0] += 1
    let nextURL = directory.appendingPathComponent("replay-\(index).mlmodelc")
    model = try update(currentURL, examples: [example(category, label: label)], destination: nextURL).0
    if currentURL != seed { try? FileManager.default.removeItem(at: currentURL) }
    currentURL = nextURL
}
print("chronologicalSyntheticTop3", "knn/frequency/contextTransition/production/mostRecent", hits, "of", streamCount)
print("chronologicalCoverage", coverage, "of", streamCount, "first12Hits", earlyHits)
print("afterFirst12Hits", zip(hits, earlyHits).map { $0 - $1 }, "of", streamCount - 12)

for count in [1_000, 10_000] {
    let records = try (0..<count).map { try example($0 % 64, label: "synthetic.\($0 % 64)") }
    let target = directory.appendingPathComponent("scale-\(count).mlmodelc")
    let (largeModel, seconds) = try update(seed, examples: records, destination: target)
    var times: [Double] = []
    for index in 0..<100 {
        let start = Date()
        _ = try scores(largeModel, index % 64)
        times.append(Date().timeIntervalSince(start) * 1000)
    }
    let enumerator = FileManager.default.enumerator(at: target, includingPropertiesForKeys: [.fileSizeKey])!
    let bytes = enumerator.compactMap { $0 as? URL }.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    print("scale", count, "updateSaveReloadSeconds", seconds, "predictionP95ms", times.sorted()[95], "bytes", bytes)
    let baselineExamples = (0..<count).map { LauncherSuggestionExample(context: context($0 % 64), targetID: "synthetic.\($0 % 64)", date: date) }
    var baselineTimes: [Double] = []
    for index in 0..<100 {
        let start = Date()
        _ = LauncherSuggestionBaseline.scores(context: context(index % 64), examples: baselineExamples, feedback: [], excluded: [], now: date)
        baselineTimes.append(Date().timeIntervalSince(start) * 1000)
    }
    print("productionBaseline", count, "predictionP95ms", baselineTimes.sorted()[95])
}

let cancellationSignal = DispatchSemaphore(value: 0)
let cancellationData = try (0..<10_000).map { try example($0 % 64, label: "cancel.\($0 % 64)") }
let cancelled = try MLUpdateTask(forModelAt: seed, trainingData: MLArrayBatchProvider(array: cancellationData), configuration: configuration) { context in
    print("cancelCompletionState", context.task.state.rawValue)
    cancellationSignal.signal()
}
cancelled.resume()
cancelled.cancel()
print("cancelImmediatelyState", cancelled.state.rawValue)
print("cancelCompletionWithin5Seconds", cancellationSignal.wait(timeout: .now() + 5) == .success)
print("cancelFinalState", cancelled.state.rawValue)
}
}
