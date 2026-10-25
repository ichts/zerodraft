// [INPUT] A running app's process id (AX reads) and absolute screen coordinates
//         (CGEvent writes); command line options.
// [OUTPUT] JSON accessibility trees / matches / text snapshots on stdout, and real
//          HID-tap keyboard, mouse and screenshot probes.
// [POS] apps/macos/FirstLine/scripts/vm/widrig.swift - guest-side driver of the
//       recorded DMG acceptance rig. It exists so the journey can read the shipped
//       app's accessibility state and deliver CGEvent-level input from INSIDE the
//       macOS guest (the host cannot see or type into a VM's accessibility tree).
// [PROTOCOL] Accessibility and Screen Recording are TCC grants held by this binary
//            inside the prepared VM image (scripts/vm/prepare-guest.sh seeds them
//            once). Nothing here presses buttons through AXPress: input is always
//            CGEventPost(kCGHIDEventTap), so the app sees real keyboard and mouse.
//            Subcommands: trusted, tree, text, find, wait, watch, window, frontmost,
//            type, key, click, move, pxdiff, csreq.

import AppKit
import ApplicationServices
import Foundation
import Security

func emit(_ value: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else {
        FileHandle.standardError.write(Data("widrig: cannot encode output\n".utf8))
        exit(70)
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func die(_ message: String, _ code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("widrig: \(message)\n".utf8))
    exit(code)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    die("usage: widrig <trusted|tree|text|find|wait|watch|window|frontmost|type|key|click|move|pxdiff|csreq> [...]")
}
arguments.removeFirst()

func option(_ name: String, _ fallback: String? = nil) -> String? {
    guard let index = arguments.firstIndex(of: "--\(name)"), index + 1 < arguments.count else { return fallback }
    return arguments[index + 1]
}

func flag(_ name: String) -> Bool { arguments.contains("--\(name)") }

func requiredOption(_ name: String) -> String {
    guard let value = option(name) else { die("--\(name) is required") }
    return value
}

func now() -> Double { Date().timeIntervalSince1970 }

// MARK: - Accessibility

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func text(_ value: CFTypeRef?) -> String {
    guard let value else { return "" }
    if CFGetTypeID(value) == CFStringGetTypeID(), let string = value as? String { return string }
    if CFGetTypeID(value) == CFNumberGetTypeID(), let number = value as? NSNumber { return number.stringValue }
    return ""
}

func elementFrame(_ element: AXUIElement) -> [String: Double]? {
    guard let positionRef = attribute(element, kAXPositionAttribute),
          let sizeRef = attribute(element, kAXSizeAttribute),
          CFGetTypeID(positionRef) == AXValueGetTypeID(),
          CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
    let position = positionRef as! AXValue
    let size = sizeRef as! AXValue
    var point = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent) else { return nil }
    return ["x": point.x, "y": point.y, "w": extent.width, "h": extent.height]
}

struct Node {
    let role: String
    let title: String
    let value: String
    let description: String
    let frame: [String: Double]?
    let path: String
    /// Best human/assertion text: the value when present, otherwise the title.
    var haystack: String {
        [value, title, description].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

func application(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

func collect(_ root: AXUIElement, maxDepth: Int = 24, limit: Int = 4000) -> [Node] {
    var nodes: [Node] = []
    var visited = Set<Int>()
    func walk(_ element: AXUIElement, depth: Int, path: String) {
        guard depth <= maxDepth, nodes.count < limit else { return }
        let identity = Int(CFHash(element))
        guard !visited.contains(identity) else { return }
        visited.insert(identity)
        let children = (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        if depth > 0 {
            nodes.append(Node(
                role: text(attribute(element, kAXRoleAttribute)),
                title: text(attribute(element, kAXTitleAttribute)),
                value: text(attribute(element, kAXValueAttribute)),
                description: text(attribute(element, kAXDescriptionAttribute)),
                frame: elementFrame(element),
                path: path
            ))
        }
        for (index, child) in children.enumerated() {
            walk(child, depth: depth + 1, path: path.isEmpty ? "\(index)" : "\(path).\(index)")
        }
    }
    walk(root, depth: 0, path: "")
    return nodes
}

/// Resolves the target process either from --pid or by waiting for a running
/// application whose bundle or executable path contains --pattern. The pattern
/// form exists so a launch watcher can be armed BEFORE the app is opened and
/// still catch its very first frames.
func scanProcessTable(_ pattern: String) -> pid_t? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-f", pattern]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8),
          let first = output.split(separator: "\n").first,
          let pid = Int32(first.trimmingCharacters(in: .whitespaces)) else { return nil }
    return pid
}

func resolvePID() -> pid_t {
    if let raw = option("pid") {
        guard let pid = Int32(raw) else { die("--pid must be numeric") }
        return pid
    }
    guard let pattern = option("pattern") else { die("--pid or --pattern is required") }
    let deadline = now() + Double(option("timeout") ?? "30")!
    while now() < deadline {
        for application in NSWorkspace.shared.runningApplications {
            let bundle = application.bundleURL?.path ?? ""
            let executable = application.executableURL?.path ?? ""
            if bundle.contains(pattern) || executable.contains(pattern) { return application.processIdentifier }
        }
        // A quarantined first launch runs the app from a Gatekeeper-translocated
        // read-only copy, which NSWorkspace does not always list; fall back to a
        // direct process-table scan so the watcher still finds it.
        if let scanned = scanProcessTable(pattern) { return scanned }
        usleep(50_000)
    }
    die("no process matching pattern \(pattern)", 1)
}

func regex(_ pattern: String) -> NSRegularExpression {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { die("invalid --text regex \(pattern)") }
    return expression
}

func matches(_ expression: NSRegularExpression, _ haystack: String) -> Bool {
    expression.firstMatch(in: haystack, range: NSRange(haystack.startIndex..., in: haystack)) != nil
}

func nodeJSON(_ node: Node) -> [String: Any] {
    var object: [String: Any] = [
        "role": node.role,
        "title": node.title,
        "value": node.value,
        "description": node.description,
        "path": node.path,
    ]
    if let frame = node.frame { object["frame"] = frame }
    return object
}

func joinedText(_ nodes: [Node]) -> String {
    nodes.map(\.haystack).filter { !$0.isEmpty }.joined(separator: " | ")
}

// MARK: - Input

let keyCodes: [String: CGKeyCode] = [
    "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "backspace": 0x33,
    "escape": 0x35, "right": 0x7C, "left": 0x7B, "down": 0x7D, "up": 0x7E,
    "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79, "forwarddelete": 0x75,
]

let characterKeys: [Character: (CGKeyCode, Bool)] = {
    var map: [Character: (CGKeyCode, Bool)] = [:]
    let rows: [(String, [CGKeyCode])] = [
        ("abcdefghijklmnopqrstuvwxyz", [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26,
                                        0x28, 0x25, 0x2E, 0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11,
                                        0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]),
        ("1234567890", [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]),
    ]
    for (characters, codes) in rows {
        for (character, code) in zip(characters, codes) { map[character] = (code, false) }
    }
    let shifted: [(Character, CGKeyCode)] = [
        ("-", 0x1B), ("=", 0x18), ("[", 0x21), ("]", 0x1E), ("\\", 0x2A), (";", 0x29),
        ("'", 0x27), (",", 0x2B), (".", 0x2F), ("/", 0x2C), ("`", 0x32),
    ]
    for (character, code) in shifted { map[character] = (code, false) }
    let shiftPairs: [(Character, Character)] = [
        ("!", "1"), ("@", "2"), ("#", "3"), ("$", "4"), ("%", "5"), ("^", "6"), ("&", "7"),
        ("*", "8"), ("(", "9"), (")", "0"), ("_", "-"), ("+", "="), ("{", "["), ("}", "]"),
        ("|", "\\"), (":", ";"), ("\"", "'"), ("<", ","), (">", "."), ("?", "/"), ("~", "`"),
    ]
    for (shiftedCharacter, base) in shiftPairs {
        if let (code, _) = map[base] { map[shiftedCharacter] = (code, true) }
    }
    return map
}()

func source() -> CGEventSource? { CGEventSource(stateID: .hidSystemState) }

func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
    guard let eventSource = source() else { die("no HID event source") }
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down) else { continue }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

func postUnicode(_ character: Character) {
    guard let eventSource = source(), let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) else { return }
    var units = Array(String(character).utf16)
    event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
    event.post(tap: .cghidEventTap)
    guard let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else { return }
    up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
    up.post(tap: .cghidEventTap)
}

func postMouse(_ type: CGEventType, at point: CGPoint, clickState: Int64 = 1, button: CGMouseButton = .left) {
    guard let eventSource = source() else { die("no HID event source") }
    guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
    if clickState > 0 { event.setIntegerValueField(.mouseEventClickState, value: clickState) }
    event.post(tap: .cghidEventTap)
}

// MARK: - Screenshot probing

func bitmap(_ path: String) -> NSBitmapImageRep {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let representation = NSBitmapImageRep(data: data) else { die("cannot read image \(path)") }
    return representation
}

// MARK: - Commands

switch command {
case "trusted":
    let prompt = flag("prompt")
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    emit(["accessibility": AXIsProcessTrustedWithOptions(options), "prompt": prompt])

case "tree":
    let nodes = collect(application(resolvePID()))
    emit(["count": nodes.count, "elements": nodes.map(nodeJSON)])

case "text":
    emit(["text": joinedText(collect(application(resolvePID())))])

case "window":
    let app = application(resolvePID())
    let windows = (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    var objects: [[String: Any]] = []
    for window in windows {
        var object: [String: Any] = [
            "title": text(attribute(window, kAXTitleAttribute)),
            "role": text(attribute(window, kAXRoleAttribute)),
            "subrole": text(attribute(window, kAXSubroleAttribute)),
        ]
        if let frame = elementFrame(window) { object["frame"] = frame }
        objects.append(object)
    }
    emit(["windows": objects])

case "find", "wait":
    // --text is optional: without it the first element with --role matches, which
    // is how the journey focuses an empty text field whose haystack is empty.
    let expression = option("text").flatMap { $0.isEmpty ? nil : $0 }.map { regex($0) }
    let role = option("role")
    let pid = resolvePID()
    let deadline = now() + Double(option("timeout") ?? "20")!
    while true {
        let nodes = collect(application(pid))
        let match = nodes.first { node in
            (role == nil || node.role == role!) && (expression == nil || matches(expression!, node.haystack))
        }
        if let match {
            emit(nodeJSON(match))
            exit(0)
        }
        if command == "find" || now() >= deadline { emit(["found": false]); exit(1) }
        usleep(120_000)
    }

case "watch":
    let pid = resolvePID()
    let seconds = Double(option("seconds") ?? "3")!
    let interval = Double(option("interval") ?? "0.08")!
    let deadline = now() + seconds
    var frames = 0
    while now() < deadline {
        let nodes = collect(application(pid))
        var object: [String: Any] = ["t": now(), "text": joinedText(nodes)]
        if let window = (attribute(application(pid), kAXWindowsAttribute) as? [AXUIElement])?.first,
           let frame = elementFrame(window) {
            object["window"] = frame
        }
        emit(object)
        frames += 1
        usleep(useconds_t(interval * 1_000_000))
    }
    FileHandle.standardError.write(Data("widrig: watch frames=\(frames)\n".utf8))

case "frontmost":
    let app = application(resolvePID())
    let result = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    emit(["ok": result == .success])

case "type":
    let string = requiredOption("text")
    let delay = Double(option("delay") ?? "0.06")!
    for character in string {
        if let (code, shifted) = characterKeys[character] {
            postKey(code, flags: shifted ? .maskShift : [])
        } else {
            postUnicode(character)
        }
        usleep(useconds_t(delay * 1_000_000))
    }
    emit(["typed": string.count])

case "key":
    let name = requiredOption("name").lowercased()
    let count = Int(option("count") ?? "1")!
    let flags: CGEventFlags = flag("shift") ? .maskShift : (flag("command") ? .maskCommand : [])
    let code: CGKeyCode
    if let known = keyCodes[name] {
        code = known
    } else if name.count == 1, let character = name.first, let (mapped, shifted) = characterKeys[character] {
        code = mapped
        postKey(code, flags: (shifted || flag("shift")) ? .maskShift : [])
        emit(["key": name, "code": Int(code), "count": 1])
        exit(0)
    } else if let numeric = UInt16(name) {
        code = CGKeyCode(numeric)
    } else {
        die("unknown key \(name)")
    }
    for _ in 0..<max(1, count) {
        postKey(code, flags: flags)
        usleep(60_000)
    }
    emit(["key": name, "code": Int(code), "count": max(1, count)])

case "click":
    let x = Double(requiredOption("x"))!
    let y = Double(requiredOption("y"))!
    let count = Int(option("count") ?? "1")!
    let point = CGPoint(x: x, y: y)
    postMouse(.mouseMoved, at: point, clickState: 0)
    usleep(80_000)
    for index in 1...max(1, count) {
        postMouse(.leftMouseDown, at: point, clickState: Int64(index))
        usleep(40_000)
        postMouse(.leftMouseUp, at: point, clickState: Int64(index))
        if index < count { usleep(80_000) }
    }
    emit(["clicked": ["x": x, "y": y], "count": max(1, count)])

case "move":
    let point = CGPoint(x: Double(requiredOption("x"))!, y: Double(requiredOption("y"))!)
    postMouse(.mouseMoved, at: point, clickState: 0)
    emit(["moved": ["x": point.x, "y": point.y]])

case "pxdiff":
    let first = bitmap(requiredOption("first"))
    let second = bitmap(requiredOption("second"))
    guard first.pixelsWide == second.pixelsWide, first.pixelsHigh == second.pixelsHigh else {
        emit(["comparable": false])
        exit(1)
    }
    var changed = 0
    var sampled = 0
    let step = 4
    var y = 0
    while y < first.pixelsHigh {
        var x = 0
        while x < first.pixelsWide {
            guard let left = first.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  let right = second.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                die("cannot sample pixels")
            }
            let delta = max(abs(left.redComponent - right.redComponent),
                            abs(left.greenComponent - right.greenComponent),
                            abs(left.blueComponent - right.blueComponent))
            if delta > 0.1 { changed += 1 }
            sampled += 1
            x += step
        }
        y += step
    }
    let fraction = sampled == 0 ? 0 : Double(changed) / Double(sampled)
    emit(["comparable": true, "sampled": sampled, "changedPixels": changed, "changedFraction": fraction])
    exit(fraction > 0.02 ? 0 : 1)

case "csreq":
    let path = requiredOption("binary")
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else {
        die("cannot read static code for \(path)")
    }
    var requirement: SecRequirement?
    guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement else {
        die("cannot read designated requirement for \(path)")
    }
    var data: CFData?
    guard SecRequirementCopyData(requirement, [], &data) == errSecSuccess, let data else {
        die("cannot encode designated requirement for \(path)")
    }
    let hex = (data as Data).map { String(format: "%02x", $0) }.joined()
    emit(["binary": path, "csreq": hex])

default:
    die("unknown command \(command)")
}
