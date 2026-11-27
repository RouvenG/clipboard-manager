import Foundation

/// Runs user scripts from the Scripts folder. A script is a .ts/.js/.mjs file whose default export is
/// `(input: string, context: { sourceApp?: string }) => string | Promise<string>`.
enum ScriptRunner {
    static let fileExtensions: Set<String> = ["ts", "js", "mjs", "mts"]
    nonisolated static let timeout: TimeInterval = 5

    enum Runtime: String {
        case bun, deno, node
    }

    // MARK: Discovery

    static func scripts(in directory: URL = AppPaths.scriptsDirectory) -> [Transform] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { fileExtensions.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let header = parseHeader(of: url)
                return Transform(
                    id: "script." + url.lastPathComponent,
                    name: header.name ?? url.deletingPathExtension().lastPathComponent,
                    detail: header.description ?? "Script: \(url.lastPathComponent)",
                    action: .script(url)
                )
            }
    }

    /// Reads `// @name ...` and `// @description ...` from the first lines of a script.
    static func parseHeader(of url: URL) -> (name: String?, description: String?) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return (nil, nil) }
        var name: String?
        var description: String?
        for line in content.split(separator: "\n").prefix(20) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("//") else { continue }
            let body = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("@name ") { name = String(body.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            if body.hasPrefix("@description ") { description = String(body.dropFirst(13)).trimmingCharacters(in: .whitespaces) }
        }
        return (name, description)
    }

    // MARK: Runtime

    static func resolveRuntime(preferredPath: String) -> URL? {
        let fm = FileManager.default
        if !preferredPath.isEmpty {
            let url = URL(fileURLWithPath: (preferredPath as NSString).expandingTildeInPath)
            return fm.isExecutableFile(atPath: url.path) ? url : nil
        }
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(home)/.bun/bin/bun", "/opt/homebrew/bin/bun", "/usr/local/bin/bun",
            "\(home)/.deno/bin/deno", "/opt/homebrew/bin/deno", "/usr/local/bin/deno",
            "/opt/homebrew/bin/node", "/usr/local/bin/node",
        ]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvm) {
            let newest = versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            candidates += newest.map { "\(nvm)/\($0)/bin/node" }
        }
        return candidates.lazy.map(URL.init(fileURLWithPath:)).first { fm.isExecutableFile(atPath: $0.path) }
    }

    static func runtime(of executable: URL) -> Runtime? {
        let name = executable.lastPathComponent.lowercased()
        if name.hasPrefix("bun") { return .bun }
        if name.hasPrefix("deno") { return .deno }
        if name.hasPrefix("node") { return .node }
        return nil
    }

    static func arguments(for runtime: Runtime, runner: URL, script: URL) -> [String] {
        switch runtime {
        case .bun:
            ["run", runner.path, script.path]
        case .deno:
            // Deno sandboxes by default: no network, reads limited to the scripts folder.
            ["run", "--quiet", "--no-prompt", "--allow-env=CLIPSHELF_CONTEXT",
             "--allow-read=\(script.deletingLastPathComponent().path)", runner.path, script.path]
        case .node:
            // Type stripping is on by default from Node 23.6; the flag enables it on 22.6+.
            ["--no-warnings", "--experimental-strip-types", runner.path, script.path]
        }
    }

    // MARK: Running

    static func run(script: URL, input: String, sourceApp: String?, runtimePath: String) async throws -> String {
        guard let executable = resolveRuntime(preferredPath: runtimePath), let runtime = runtime(of: executable) else {
            throw TransformError.failed("No bun, deno or node found. Set the runtime path in Settings.")
        }
        let runner = try writeRunner()
        let args = arguments(for: runtime, runner: runner, script: script)
        let context = (try? JSONSerialization.data(withJSONObject: ["sourceApp": sourceApp ?? ""])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return try await Task.detached {
            try execute(executable: executable, arguments: args, input: input, context: context)
        }.value
    }

    nonisolated private static func execute(executable: URL, arguments: [String], input: String, context: String) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let path = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = "\(executable.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:\(path)"
        environment["CLIPSHELF_CONTEXT"] = context
        environment["NO_COLOR"] = "1"
        process.environment = environment

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try? stdin.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        // Read concurrently so a large output cannot fill the pipe and deadlock.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = stdout.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = stderr.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning {
            process.terminate()
            group.wait()
            throw TransformError.failed("Script timed out after \(Int(timeout))s")
        }
        group.wait()

        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lines = message.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let summary = lines.first { $0.contains("Error") || $0.hasPrefix("error") } ?? lines.last
            throw TransformError.failed(summary ?? "Script exited with \(process.terminationStatus)")
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }

    // MARK: Files

    static let runnerSource = """
    import process from "node:process";
    import { Buffer } from "node:buffer";
    import { pathToFileURL } from "node:url";

    const chunks = [];
    for await (const chunk of process.stdin) chunks.push(chunk);
    const input = Buffer.concat(chunks).toString("utf8");
    const context = JSON.parse(process.env.CLIPSHELF_CONTEXT ?? "{}");

    const mod = await import(pathToFileURL(process.argv[process.argv.length - 1]).href);
    const fn = mod.default ?? mod.transform;
    if (typeof fn !== "function") {
      console.error("Script must `export default (input) => output`");
      process.exit(2);
    }
    const output = await fn(input, context);
    process.stdout.write(String(output ?? ""));

    """

    static func writeRunner() throws -> URL {
        let url = AppPaths.supportDirectory.appendingPathComponent("runner.mjs")
        if (try? String(contentsOf: url, encoding: .utf8)) != runnerSource {
            try runnerSource.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    static let exampleScript = """
    // @name Slugify
    // @description Turn text into a URL slug
    //
    // ClipShelf script: export a default function that receives the clip text and
    // returns the text to paste. Drop more .ts files into this folder; they show up
    // in the Cmd+K menu. Optional header lines: @name and @description.
    export default (input: string, context: { sourceApp?: string }): string =>
      input
        .normalize("NFKD")
        .replace(/[\\u0300-\\u036f]/g, "")
        .toLowerCase()
        .trim()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "");

    """

    /// Seeds one example script the first time, so the contract is discoverable.
    static func seedExampleIfNeeded(defaults: UserDefaults = .standard) {
        let key = "didSeedExampleScript"
        guard !defaults.bool(forKey: key) else { return }
        let url = AppPaths.scriptsDirectory.appendingPathComponent("slugify.ts")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? exampleScript.write(to: url, atomically: true, encoding: .utf8)
        }
        defaults.set(true, forKey: key)
    }
}
