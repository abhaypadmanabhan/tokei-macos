import Foundation

/// `tokei status [--json]` — print the snapshot as a table or raw JSON.
enum StatusCommand {
    static func run(json: Bool, reader: SnapshotReader = SnapshotReader()) -> Int32 {
        do {
            let snapshot = try reader.read()
            if json {
                let data = try AgentSnapshot.makeEncoder().encode(snapshot)
                print(String(decoding: data, as: UTF8.self))
            } else {
                print(StatusFormatting.table(for: snapshot))
            }
            // A stale read still succeeds — it's flagged in the output, not an error.
            return 0
        } catch let error as SnapshotReadError {
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            return error.exitCode
        } catch {
            FileHandle.standardError.write(Data("tokei: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
