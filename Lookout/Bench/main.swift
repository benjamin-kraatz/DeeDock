import Foundation

// LookoutBench: Lookout's phase 0 spike. Measures EmbeddingGemma 2 on the vendored llama.cpp and checks its vectors
// against DigUp's reference. A developer tool: it isn't part of DOKK.app.

let usage = """
    usage: LookoutBench reference --models <folder> --refs <folder>
           LookoutBench bench --models <folder> [--refs <folder>]

      --models  the folder with embeddinggemma-2-Q8_0.gguf and mmproj-embeddinggemma-2-Q8_0.gguf
      --refs    DigUp's Tests/LlamaRuntimeTests/Reference (photo.jpg, screen.png, speech.wav, vectors.json);
                bench measures images and checks the reference only with it
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
        exit(try Benchmark.run(models: arguments.requiredFolder("models"), references: references))
    case "probe-text":
        try TextProbe.run(models: arguments.requiredFolder("models"))
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
