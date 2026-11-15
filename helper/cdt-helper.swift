// cdt-helper: runs from inside a clone (<App>.app/Contents/MacOS/cdt-helper) and acts
// on behalf of that bundle.
//
//   cdt-helper            ask macOS for notification permission
//                         (exit 0 granted, 1 denied, 2 timeout)
//   cdt-helper --status   print the current notification authorization status
//   cdt-helper --focus <pid>
//                         bring that process forward (no Automation permission needed)
//
// Claude Desktop never asks for notification permission itself, so a fresh clone would
// stay "not determined" and never appear in System Settings > Notifications.
// usernotificationsd only answers a process that checked in with LaunchServices as an
// app, so the permission modes run a hidden NSApplication instead of a bare CLI.
import AppKit
import UserNotifications

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--focus" {
    guard args.count == 2, let pid = pid_t(args[1]) else { fail("usage: cdt-helper --focus <pid>", 64) }
    guard let running = NSRunningApplication(processIdentifier: pid) else { fail("no app with pid \(pid)", 1) }
    let ok: Bool
    if #available(macOS 14, *) {
        ok = running.activate(options: [.activateAllWindows])
    } else {
        ok = running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
    exit(ok ? 0 : 1)
}

if let first = args.first, first != "--status" {
    fail("usage: cdt-helper [--status | --focus <pid>]", 64)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
let center = UNUserNotificationCenter.current()

if args.first == "--status" {
    center.getNotificationSettings { settings in
        let name: String
        switch settings.authorizationStatus {
        case .authorized: name = "authorized"
        case .denied: name = "denied"
        case .notDetermined: name = "not-determined"
        case .provisional: name = "provisional"
        case .ephemeral: name = "ephemeral"
        @unknown default: name = "unknown"
        }
        print(name)
        exit(0)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { fail("timed out reading status", 2) }
} else {
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        if let error { FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!) }
        print("\(Bundle.main.bundleIdentifier ?? "?"): granted=\(granted)")
        exit(granted ? 0 : 1)
    }
    // Give the user time to answer the system prompt.
    DispatchQueue.main.asyncAfter(deadline: .now() + 120) { fail("timed out waiting for an answer", 2) }
}
app.run()
