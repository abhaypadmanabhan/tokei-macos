import Foundation

enum RouteCommand {
    static func run(arguments: [String], reader: SnapshotReader = SnapshotReader()) -> Int32 {
        var json = false
        var provider: String?
        var index = 0
        var seen = Set<String>()
        while index < arguments.count {
            let argument = arguments[index]
            guard seen.insert(argument).inserted else { return invalidArguments() }
            switch argument {
            case "--json": json = true
            case "--for":
                index += 1
                guard index < arguments.count, SnapshotReader.providerIDs.contains(arguments[index]) else { return invalidArguments() }
                provider = arguments[index]
            default: return invalidArguments()
            }
            index += 1
        }
        let result: RouteOutput
        if let snapshot = try? reader.read() {
            result = RouteFormatting.output(snapshot, now: reader.now(), provider: provider)
        } else {
            result = RouteOutput(generatedAt: reader.now(), stale: true, status: "unavailable", rows: [], unknown: [],
                                 advice: "No usage snapshot is available. Launch Tokei and retry.")
        }
        if json {
            guard let data = try? AgentSnapshot.makeEncoder().encode(result),
                  let text = String(data: data, encoding: .utf8) else { return 69 }
            print(text)
        } else {
            print(RouteFormatting.render(result))
        }
        return result.exitCode
    }

    private static func invalidArguments() -> Int32 {
        print("tokei route: invalid arguments; use --json and --for <provider ID>.")
        return 64
    }
}
