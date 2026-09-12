import AppKit

@MainActor
enum AppRestarter {
    static func restart() throws {
        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/RestartHelper")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw NSError(domain: "MacBookDuo.Restart", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "找不到重启组件，请重新构建应用"])
        }
        let helper = Process()
        helper.executableURL = helperURL
        helper.arguments = [String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        NSApp.terminate(nil)
    }
}
