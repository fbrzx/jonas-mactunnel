import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var restartItem: NSMenuItem!
    private var pollTimer: Timer?

    private let projectRoot: String = {
        let bundle = Bundle.main.bundlePath
        let appDir = (bundle as NSString).deletingLastPathComponent
        let candidates = [
            appDir,
            (appDir as NSString).deletingLastPathComponent,
            ((appDir as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent,
        ]
        for c in candidates {
            let runSh = (c as NSString).appendingPathComponent("run.sh")
            if FileManager.default.fileExists(atPath: runSh) { return c }
        }
        return "/Users/fabfab/Projects/jonas-mactunnel" // fallback for development
    }()

    private var scriptPath: String { (projectRoot as NSString).appendingPathComponent("run.sh") }
    private var syncScriptPath: String { (projectRoot as NSString).appendingPathComponent("scripts/sync-from-jonas.sh") }
    private var envFileCandidates: [String] {
        var candidates: [String] = []
        if let resourcePath = Bundle.main.resourcePath {
            candidates.append((resourcePath as NSString).appendingPathComponent(".env"))
        }
        candidates.append((projectRoot as NSString).appendingPathComponent(".env"))
        return candidates
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Jonas Tunnel", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        statusMenuItem = NSMenuItem(title: "Status: checking...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        startItem = NSMenuItem(title: "Connect Jonas", action: #selector(startTunnel), keyEquivalent: "s")
        startItem.target = self
        menu.addItem(startItem)

        stopItem = NSMenuItem(title: "Disconnect Jonas", action: #selector(stopTunnel), keyEquivalent: "x")
        stopItem.target = self
        menu.addItem(stopItem)

        restartItem = NSMenuItem(title: "Reconnect Jonas", action: #selector(restartTunnel), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        menu.addItem(NSMenuItem.separator())

        let syncItem = NSMenuItem(title: "Sync Vault", action: #selector(syncVault), keyEquivalent: "y")
        syncItem.target = self
        menu.addItem(syncItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        refreshStatus()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    // MARK: - Actions

    @objc private func startTunnel() {
        setMenuEnabled(false)
        runScriptAsync("start") { [weak self] output in
            self?.refreshStatus()
            self?.setMenuEnabled(true)
            self?.notify(title: "Jonas Tunnel", body: output)
        }
    }

    @objc private func stopTunnel() {
        setMenuEnabled(false)
        runScriptAsync("stop") { [weak self] output in
            self?.refreshStatus()
            self?.setMenuEnabled(true)
            self?.notify(title: "Jonas Tunnel", body: output)
        }
    }

    @objc private func restartTunnel() {
        setMenuEnabled(false)
        runScriptAsync("restart") { [weak self] output in
            self?.refreshStatus()
            self?.setMenuEnabled(true)
            self?.notify(title: "Jonas Tunnel", body: output)
        }
    }

    @objc private func syncVault() {
        runShellAsync(script: syncScriptPath, args: ["--yes"]) { [weak self] output in
            let lastLine = output.components(separatedBy: "\n").last(where: { !$0.isEmpty }) ?? output
            self?.notify(title: "Jonas Tunnel", body: lastLine)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Status

    private func refreshStatus() {
        let output = runScript("status")
        let running = output.lowercased().contains("running")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let button = self.statusItem.button {
                let symbolName = running ? "lock.fill" : "lock.open"
                if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Jonas Tunnel") {
                    image.size = NSSize(width: 16, height: 16)
                    image.isTemplate = true
                    button.image = image
                }
                button.title = ""
            }
            self.statusMenuItem.title = running ? "Status: Connected" : "Status: Disconnected"
            self.startItem.isEnabled = !running
            self.restartItem.isEnabled = running
            self.stopItem.isEnabled = running
        }
    }

    private func setMenuEnabled(_ enabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.startItem.isEnabled = enabled
            self?.stopItem.isEnabled = enabled
            self?.restartItem.isEnabled = enabled
        }
    }

    // MARK: - Shell helpers

    private func runShell(script: String, args: [String], stdinData: String? = nil) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script] + args
        process.standardOutput = pipe
        process.standardError = pipe
        var env = ProcessInfo.processInfo.environment
        let overrides = loadEnvOverrides()
        for (key, value) in overrides {
            env[key] = value
        }
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        process.environment = env
        if let input = stdinData, let data = input.data(using: .utf8) {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            stdinPipe.fileHandleForWriting.write(data)
            stdinPipe.fileHandleForWriting.closeFile()
        }
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Error: \(error.localizedDescription)"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func runScript(_ command: String) -> String {
        runShell(script: scriptPath, args: [command])
    }

    private func runScriptAsync(_ command: String, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let output = self.runScript(command)
            DispatchQueue.main.async { completion(output) }
        }
    }

    private func runShellAsync(script: String, args: [String], stdinData: String? = nil, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let output = self.runShell(script: script, args: args, stdinData: stdinData)
            DispatchQueue.main.async { completion(output) }
        }
    }

    private func loadEnvOverrides() -> [String: String] {
        for path in envFileCandidates {
            if FileManager.default.fileExists(atPath: path) {
                return parseEnvFile(at: path)
            }
        }
        return [:]
    }

    private func parseEnvFile(at path: String) -> [String: String] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separatorIndex = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separatorIndex)...])
            value = value.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    // MARK: - Notifications

    private func notify(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        NSUserNotificationCenter.default.deliver(notification)
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
