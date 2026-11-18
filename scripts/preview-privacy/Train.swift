import CreateML
import Foundation

@main
struct Train {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: train DATASET OUTPUT.mlmodel")
            exit(2)
        }
        let dataset = URL(filePath: CommandLine.arguments[1])
        let model = try MLImageClassifier(
            trainingData: .labeledDirectories(at: dataset.appending(path: "train")),
            parameters: .init(
                validation: .dataSource(.labeledDirectories(at: dataset.appending(path: "validation"))),
                maxIterations: 25,
                augmentation: [],
                algorithm: .transferLearning(featureExtractor: .scenePrint(revision: 1), classifier: .logisticRegressor)
            )
        )
        try model.write(to: URL(filePath: CommandLine.arguments[2]), metadata: .init(
            author: "DOKK", shortDescription: "Sensitive window preview classifier trained on synthetic windows.", version: "1"))
    }
}
