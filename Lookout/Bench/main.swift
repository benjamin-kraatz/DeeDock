import Foundation

// LookoutBench: Lookout's developer tool. Measures EmbeddingGemma 2 on the vendored llama.cpp, checks its vectors
// against DigUp's reference, and runs the indexing pipeline without the app. It isn't part of DOKK.app.

let usage = """
    usage: LookoutBench reference --models <folder> --refs <folder>
           LookoutBench bench --models <folder> [--refs <folder>] [--image <file>]
           LookoutBench index --models <folder> --index <folder> --root <folder>... [--exclude <folder>]...
           LookoutBench estimate --root <folder>...

      --models   the folder with embeddinggemma-2-Q8_0.gguf and mmproj-embeddinggemma-2-Q8_0.gguf
      --refs     DigUp's Tests/LlamaRuntimeTests/Reference (photo.jpg, screen.png, speech.wav, vectors.json);
                 bench measures images and checks the reference only with it
      --image    a picture to search with in the picture-search probe (default: macOS's Sonoma wallpaper)
      --index    the folder index.sqlite goes in (created when missing); not the app's unless you pass it
      --root     a folder to index or estimate (repeatable)
      --exclude  a folder to skip inside the roots (repeatable)
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
