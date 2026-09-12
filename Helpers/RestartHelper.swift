import AppKit

// A separate process must outlive the app; opening a running bundle just activates it.
let arguments = CommandLine.arguments
 guard arguments.count == 3, let parentPID = pid_t(arguments[1]), parentPID > 1 else { exit(2) }
let appURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
guard appURL.pathExtension == "app", FileManager.default.fileExists(atPath: appURL.path) else { exit(3) }
let deadline = Date().addingTimeInterval(15)
while kill(parentPID, 0) == 0 {
    guard Date() < deadline else { exit(4) }
    Thread.sleep(forTimeInterval: 0.05)
}
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
configuration.createsNewApplicationInstance = true
configuration.arguments = ["--show-settings", "--permission-relaunch"]
NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
    guard error == nil, let app, app.processIdentifier != parentPID else { exit(5) }
    exit(0)
}
RunLoop.main.run(until: Date().addingTimeInterval(20))
exit(6)
