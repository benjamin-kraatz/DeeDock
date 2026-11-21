import Foundation

// LookoutBench: Lookout's developer tool. Measures EmbeddingGemma 2 on the vendored llama.cpp, checks its vectors
// against DigUp's reference, and runs the indexing pipeline without the app. It isn't part of DOKK.app.

let usage = """
    usage: LookoutBench reference --models <folder> --refs <folder>
           LookoutBench bench --models <folder> [--refs <folder>] [--image <file>]
           LookoutBench index --models <folder> --index <folder> --root <folder>... [--exclude <folder>]...
           LookoutBench estimate --root <folder>...
           LookoutBench combine --models <folder> --index <folder> --cases <file> [--show <n>] [--weight <w>]
           LookoutBench corpus --out <folder> [--count <n>] [--seed <n>]
           LookoutBench queries --index <folder> --out <file> --root <folder>... [--cap <n>] [--limit <n>]
           LookoutBench dates [--now <yyyy-MM-dd>]   (queries on stdin)
           LookoutBench rerank --models <folder> --index <folder> --cases <file>... [--drop <text>]...
                               [--model linear|tree] [--depth <n>] [--rounds <n>] [--clicks <log>]...
                               [--show <n>] [--out <file.mlmodel>]
           LookoutBench clicks --log <clicks.jsonl>... [--show <n>]
           LookoutBench eval --models <folder> --index <folder> --cases <file>... [--split tune|held|all]
                             [--drop <text>]... [--set <name>=<value>]... [--show <n>] [--json <file>]

      --models   the folder with embeddinggemma-2-Q8_0.gguf and mmproj-embeddinggemma-2-Q8_0.gguf
      --refs     DigUp's Tests/LlamaRuntimeTests/Reference (photo.jpg, screen.png, speech.wav, vectors.json);
                 bench measures images and checks the reference only with it
      --image    a picture to search with in the picture-search probe (default: macOS's Sonoma wallpaper)
      --index    the folder index.sqlite goes in (created when missing); not the app's unless you pass it
      --root     a folder to index or estimate (repeatable)
      --exclude  a folder to skip inside the roots (repeatable)
      --cases    picture, words and answers per line, tab-separated (CombineProbe)
      --show     combine: print each case's top n results at each method's best weight; eval: print n misses
      --weight   the words' weight --show uses for every method instead
      --out      corpus: the folder the documents go in; queries: the JSONL file cases are appended to
      --count    how many documents corpus writes (default 240)
      --seed     the seed of corpus's document specs (default 20261121)
      --cap      the most files queries takes from each --root (default 150)
      --limit    the most files queries writes cases for in this run
      --split    eval: the cases to run (default all)
      --json     eval: write every case's outcome to this file
      --drop     eval: leave out cases whose answer's path contains this text (repeatable)
      --set      eval: rank with this LookoutRanking.Tuning value instead of the constant (repeatable)
    """

// Line by line even into a pipe, so the header and the probes' echoed output keep their order.
setvbuf(stdout, nil, _IOLBF, 0)

let arguments = BenchArguments(CommandLine.arguments)
let isChild = arguments.folder("child") != nil
do {
    switch arguments.command {
    case "reference":
        exit(try ReferenceCheck.run(models: arguments.requiredFolder("models"),
                                    references: arguments.requiredFolder("refs"), reportResults: isChild))
    case "bench":
        let references = arguments.folder("refs") == nil ? nil : try arguments.requiredFolder("refs")
        exit(try Benchmark.run(models: arguments.requiredFolder("models"), references: references,
                               image: arguments.file("image")))
    case "probe-text":
        try TextProbe.run(models: arguments.requiredFolder("models"))
    case "probe-image":
        try ImageProbe.run(models: arguments.requiredFolder("models"), image: arguments.file("image"))
    case "index":
        guard let index = arguments.folder("index") else { throw BenchFailure("missing --index <folder>") }
        try IndexCommand.run(models: arguments.requiredFolder("models"), index: index,
                             roots: arguments.folders("root"), excluded: arguments.folders("exclude"))
    case "combine":
        guard let cases = arguments.file("cases") else { throw BenchFailure("missing --cases <file>") }
        try CombineProbe.run(models: arguments.requiredFolder("models"), index: arguments.requiredFolder("index"),
                             cases: cases, show: Int(try arguments.number("show") ?? 0),
                             weight: try arguments.number("weight"))
    case "corpus":
        guard let out = arguments.folder("out") else { throw BenchFailure("missing --out <folder>") }
        try await CorpusCommand.run(out: out, count: Int(try arguments.number("count") ?? 240),
                                    seed: UInt64(try arguments.number("seed") ?? 20261121))
    case "queries":
        guard let out = arguments.file("out") else { throw BenchFailure("missing --out <file>") }
        try await QueriesCommand.run(index: arguments.requiredFolder("index"), out: out,
                                     roots: try arguments.folders("root"), cap: Int(try arguments.number("cap") ?? 150),
                                     limit: try arguments.number("limit").map { Int($0) })
    case "eval":
        try EvalCommand.run(models: arguments.requiredFolder("models"), index: arguments.requiredFolder("index"),
                            cases: arguments.files("cases"), split: arguments.text("split"),
                            drop: arguments.texts("drop"), sets: arguments.texts("set"),
                            show: Int(try arguments.number("show") ?? 0), json: arguments.file("json"))
    case "rerank":
        try RerankCommand.run(models: arguments.requiredFolder("models"), index: arguments.requiredFolder("index"),
                              cases: arguments.files("cases"), drop: arguments.texts("drop"),
                              kind: arguments.text("model") ?? "tree", depth: Int(try arguments.number("depth") ?? 3),
                              rounds: Int(try arguments.number("rounds") ?? 100), clicks: arguments.files("clicks"),
                              out: arguments.file("out"),
                              show: Int(try arguments.number("show") ?? 0))
    case "clicks":
        try ClicksCommand.run(logs: arguments.files("log"), show: Int(try arguments.number("show") ?? 15))
    case "dates":
        try DatesCommand.run(now: arguments.text("now"))
    case "estimate":
        try EstimateCommand.run(roots: arguments.folders("root"))
    case "probe-full":
        let references = arguments.folder("refs") == nil ? nil : try arguments.requiredFolder("refs")
        try FullProbe.run(models: arguments.requiredFolder("models"), references: references)
    default:
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("LookoutBench: \(error)\n".utf8))
    exit(1)
}
