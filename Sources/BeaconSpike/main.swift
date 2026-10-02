import CoachCore
import Foundation

// Week-1 model spike: replays saved screen snapshots against a model and scores pointing.
//
//   swift run beacon-spike <folder-of-case-json> [--provider zai|anthropic] [--model glm-4.6v] [--runs 1]
//
// Keys come from ZAI_API_KEY / ANTHROPIC_API_KEY. Cases are written by the app's
// "Save spike snapshot" action; fill in "question" and "expectedElementID" by hand.

struct Options {
    var folder: URL
    var provider = LLMProvider.zai
    var model: String?
    var runs = 1
}

func parseOptions() -> Options? {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let first = args.first, !first.hasPrefix("--") else { return nil }
    var options = Options(folder: URL(fileURLWithPath: first))
    args.removeFirst()
    while !args.isEmpty {
        let flag = args.removeFirst()
        guard let value = args.first else { return nil }
        args.removeFirst()
        switch flag {
        case "--provider": guard let p = LLMProvider(rawValue: value) else { return nil }; options.provider = p
        case "--model": options.model = value
        case "--runs": options.runs = max(1, Int(value) ?? 1)
        default: return nil
        }
    }
    return options
}

func loadCases(in folder: URL) throws -> [SpikeCase] {
    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    return try files.map { try JSONDecoder().decode(SpikeCase.self, from: Data(contentsOf: $0)) }
}

func run(_ spikeCase: SpikeCase, client: any LLMClient) async -> SpikeResult {
    let messages = PromptBuilder.messages(
        history: [],
        context: spikeCase.context,
        learnerText: PromptBuilder.learnerUtterance(spikeCase.question),
        attachScreenshot: spikeCase.context.screenshot != nil
    )
    let start = Date()
    var first: TimeInterval?
    var text = ""
    var command: PointerCommand?
    do {
        for try await event in client.stream(messages: messages, tools: CoachTools.all) {
            if first == nil { first = Date().timeIntervalSince(start) }
            switch event {
            case let .text(t): text += t
            case let .toolCall(call):
                if let parsed = CoachTools.parse(call), parsed != .clear, command == nil { command = parsed }
            }
        }
    } catch {
        return SpikeResult(name: spikeCase.name, timeToFirstEvent: first, total: Date().timeIntervalSince(start), pointedAt: nil,
                           validPointer: false, hit: nil, spokenText: text, error: error.localizedDescription)
    }
    let (valid, hit) = SpikeScoring.score(command, for: spikeCase)
    return SpikeResult(name: spikeCase.name, timeToFirstEvent: first, total: Date().timeIntervalSince(start), pointedAt: command,
                       validPointer: valid, hit: hit, spokenText: text, error: nil)
}

func describe(_ command: PointerCommand?) -> String {
    switch command {
    case nil: "none"
    case let .element(id, _)?: id
    case let .region(box, _)?: "region \(box.map { Int($0) })"
    case .clear?: "clear"
    }
}

func percentile(_ values: [TimeInterval], _ p: Double) -> String {
    guard !values.isEmpty else { return "–" }
    let sorted = values.sorted()
    let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))
    return String(format: "%.2fs", sorted[index])
}

guard let options = parseOptions() else {
    print("usage: beacon-spike <folder> [--provider zai|anthropic] [--model NAME] [--runs N]")
    exit(2)
}

let keyName = options.provider == .zai ? "ZAI_API_KEY" : "ANTHROPIC_API_KEY"
let apiKey = ProcessInfo.processInfo.environment[keyName] ?? ""
guard !apiKey.isEmpty else {
    print("Set \(keyName) in the environment.")
    exit(2)
}

let cases: [SpikeCase]
do {
    cases = try loadCases(in: options.folder)
} catch {
    print("Could not read cases: \(error)")
    exit(1)
}
guard !cases.isEmpty else {
    print("No .json cases in \(options.folder.path)")
    exit(1)
}

let settings = LLMSettings(provider: options.provider, model: options.model, apiKey: apiKey)
let client = LLMClients.make(settings)
print("Model: \(settings.provider.rawValue) / \(settings.model) — \(cases.count) cases × \(options.runs) runs\n")

var results: [SpikeResult] = []
for _ in 0..<options.runs {
    for spikeCase in cases {
        let result = await run(spikeCase, client: client)
        results.append(result)
        let hitText = result.hit.map { $0 ? "HIT " : "MISS" } ?? "n/a "
        let ttfe = result.timeToFirstEvent.map { String(format: "%.2fs", $0) } ?? "–"
        print("\(hitText)  first \(ttfe)  total \(String(format: "%.2fs", result.total))  pointed \(describe(result.pointedAt))  expected \(spikeCase.expectedElementID ?? "–")  \(result.name)")
        if let error = result.error { print("      error: \(error)") }
        if !result.spokenText.isEmpty { print("      said: \(result.spokenText.prefix(160))") }
    }
}

let scored = results.filter { $0.hit != nil }
let hits = scored.filter { $0.hit == true }.count
let valid = results.filter(\.validPointer).count
let firsts = results.compactMap(\.timeToFirstEvent)
print("""

Summary
  valid pointer:   \(valid)/\(results.count)
  hit rate:        \(scored.isEmpty ? "no expectations set" : "\(hits)/\(scored.count) (\(Int(Double(hits) / Double(scored.count) * 100))%)")
  first event p50: \(percentile(firsts, 0.5))   p90: \(percentile(firsts, 0.9))
  pass bar:        ≥80% hit rate, p50 first event under 1s (see docs/SPIKE.md)
""")
