import Foundation

extension LookoutRanking.Tuning {
    /// The names `eval --set name=value` takes, each with the property it sets.
    static let settable: [String: WritableKeyPath<LookoutRanking.Tuning, Double>] = [
        "zGate": \.zGate, "wordWeight": \.wordWeight, "coverageExponent": \.coverageExponent, "wordGate": \.wordGate, "idfExponent": \.idfExponent,
        "lookupMeaningWeight": \.lookupMeaningWeight, "lookupWordFactor": \.lookupWordFactor,
        "kindHintBonus": \.kindHintBonus, "nameWeight": \.nameWeight, "dateBonus": \.dateBonus, "strongRatio": \.strongRatio, "folderBonusPerFile": \.folderBonusPerFile,
        "folderBonusCap": \.folderBonusCap,
    ]

    /// This tuning with `name=value` overrides applied, in order.
    ///
    /// - Throws: `BenchFailure` for an unknown name or a value that isn't a number.
    func overridden(_ assignments: [String]) throws -> LookoutRanking.Tuning {
        var tuning = self
        for assignment in assignments {
            let parts = assignment.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let value = Double(parts[1]) else {
                throw BenchFailure("--set \(assignment): expected name=number")
            }
            if parts[0] == "folderMinimumFiles" {
                tuning.folderMinimumFiles = Int(value)
            } else if let path = Self.settable[parts[0]] {
                tuning[keyPath: path] = value
            } else {
                let names = (Array(Self.settable.keys) + ["folderMinimumFiles"]).sorted().joined(separator: ", ")
                throw BenchFailure("--set \(parts[0]): unknown; one of \(names)")
            }
        }
        return tuning
    }
}
