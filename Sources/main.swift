// Uyku: a menu bar eye that shows whether your Mac is allowed to sleep.
//
//   open eye   = sleep is disabled (`pmset -a disablesleep 1`); the Mac stays
//                awake, even with the lid closed
//   closed eye = normal sleep
//
// Click the eye to switch. Right-click for options.

import Cocoa
import ServiceManagement

// MARK: - Text

let isTurkish = (Locale.preferredLanguages.first ?? "en").hasPrefix("tr")
func L(_ tr: String, _ en: String) -> String { isTurkish ? tr : en }

// MARK: - System

let sudoersPath = "/etc/sudoers.d/uyku"
let lowBatteryPercent = 10

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func sleepDisabled() -> Bool {
    for line in run("/usr/bin/pmset", ["-g"]).out.split(separator: "\n") where line.contains("SleepDisabled") {
        return line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last == "1"
    }
    return false
}

/// Runs a shell command as root after the standard macOS password prompt.
func adminShell(_ command: String, prompt: String) -> Bool {
    func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    let source = "do shell script \"\(esc(command))\" with prompt \"\(esc(prompt))\" with administrator privileges"
    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)
    return error == nil
}

/// Tries the passwordless path only (works when the sudoers rule is installed).
func setSleepDisabledSilently(_ disabled: Bool) -> Bool {
    run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"]).status == 0
}

func setSleepDisabled(_ disabled: Bool) -> Bool {
    if setSleepDisabledSilently(disabled) { return true }
    let prompt = disabled
        ? L("Mac'in uyumasını kapatmak için parolanı gir.", "Enter your password to keep this Mac awake.")
        : L("Normal uykuya dönmek için parolanı gir.", "Enter your password to let this Mac sleep normally.")
    return adminShell("/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)", prompt: prompt)
}

var passwordlessInstalled: Bool { FileManager.default.fileExists(atPath: sudoersPath) }

/// Installs a sudoers rule that allows exactly two commands without a password:
/// `pmset -a disablesleep 0` and `pmset -a disablesleep 1`, for the current user.
func installPasswordless() -> Bool {
    let user = NSUserName()
    guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { return false }
    let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
    let command = "f=$(/usr/bin/mktemp) && /usr/bin/printf '%s\\n' '\(rule)' > \"$f\""
        + " && /usr/sbin/visudo -cf \"$f\" >/dev/null"
        + " && /usr/bin/install -m 440 -o root -g wheel \"$f\" \(sudoersPath); r=$?; /bin/rm -f \"$f\"; exit $r"
    return adminShell(command, prompt: L("Bir daha parola sorulmaması için parolanı bir kez gir.",
                                         "Enter your password once so Uyku never has to ask again."))
}

func removePasswordless() -> Bool {
    adminShell("/bin/rm -f \(sudoersPath)", prompt: L("Parolasız kuralı kaldırmak için parolanı gir.",
                                                       "Enter your password to remove the passwordless rule."))
}

/// True when the Mac runs on battery and the charge is at or below `lowBatteryPercent`.
func batteryIsLow() -> Bool {
    let out = run("/usr/bin/pmset", ["-g", "batt"]).out
    guard out.contains("Battery Power"),
          let r = out.range(of: "[0-9]+%", options: .regularExpression),
          let percent = Int(out[r].dropLast()) else { return false }
    return percent <= lowBatteryPercent
}

func notify(_ text: String) {
    let safe = text.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "'")
    run("/usr/bin/osascript", ["-e", "display notification \"\(safe)\" with title \"Uyku\""])
}

// MARK: - Icons

enum IconStyle: Int, CaseIterable {
    case eye = 11, faces = 8, sunMoon = 10, toggle = 0

    var title: String {
        switch self {
        case .eye: return L("Göz", "Eye")
        case .faces: return L("Gözler ve uyuyan yüz", "Eyes and sleeping face")
        case .sunMoon: return L("Güneş ve ay", "Sun and moon")
        case .toggle: return L("Anahtar", "Switch")
        }
    }

    static var current: IconStyle {
        get { (UserDefaults.standard.object(forKey: "stil") as? Int).flatMap(IconStyle.init(rawValue:)) ?? .eye }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "stil") }
    }
}

/// Draws the eye in a 22 x 16 design space scaled to `rect`.
func drawEye(open: Bool, in rect: NSRect, color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: rect.minX, yBy: rect.minY)
    t.scaleX(by: rect.width / 22, yBy: rect.height / 16)
    t.concat()
    color.setStroke(); color.setFill()
    let p = NSBezierPath()
    p.lineWidth = 1.7; p.lineCapStyle = .round; p.lineJoinStyle = .round
    if open {
        p.move(to: NSPoint(x: 1.5, y: 8))
        p.curve(to: NSPoint(x: 20.5, y: 8), controlPoint1: NSPoint(x: 6, y: 15.5), controlPoint2: NSPoint(x: 16, y: 15.5))
        p.curve(to: NSPoint(x: 1.5, y: 8), controlPoint1: NSPoint(x: 16, y: 0.5), controlPoint2: NSPoint(x: 6, y: 0.5))
        p.stroke()
        NSBezierPath(ovalIn: NSRect(x: 7.7, y: 4.7, width: 6.6, height: 6.6)).fill()
    } else {
        p.move(to: NSPoint(x: 1.5, y: 10.5))
        p.curve(to: NSPoint(x: 20.5, y: 10.5), controlPoint1: NSPoint(x: 6, y: 3.5), controlPoint2: NSPoint(x: 16, y: 3.5))
        let lashes = [(NSPoint(x: 5.2, y: 6.6), NSPoint(x: 3.6, y: 3.6)),
                      (NSPoint(x: 11, y: 5.3), NSPoint(x: 11, y: 2.0)),
                      (NSPoint(x: 16.8, y: 6.6), NSPoint(x: 18.4, y: 3.6))]
        for (from, to) in lashes { p.move(to: from); p.line(to: to) }
        p.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
}

func eyeImage(open: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { rect in
        drawEye(open: open, in: rect, color: .black)
        return true
    }
    image.isTemplate = true
    return image
}

func emojiImage(_ emoji: String) -> NSImage {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16)]
    let size = (emoji as NSString).size(withAttributes: attributes)
    return NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { _ in
        (emoji as NSString).draw(at: .zero, withAttributes: attributes)
        return true
    }
}

func toggleImage(on: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 28, height: 16), flipped: false) { rect in
        (on ? NSColor.systemGreen : NSColor.black.withAlphaComponent(0.35)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        let d = rect.height - 4
        (on ? NSColor.white : NSColor.black).setFill()
        NSBezierPath(ovalIn: NSRect(x: on ? rect.maxX - d - 2 : 2, y: 2, width: d, height: d)).fill()
        return true
    }
    image.isTemplate = !on
    return image
}

/// `awake` is true when sleep is disabled.
func statusImage(awake: Bool, style: IconStyle) -> NSImage {
    switch style {
    case .eye: return eyeImage(open: awake)
    case .faces: return emojiImage(awake ? "👀" : "😴")
    case .sunMoon: return emojiImage(awake ? "☀️" : "🌙")
    case .toggle: return toggleImage(on: awake)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var busy = false
    private var ticks = 0
    private var warnedLowBattery = false

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        show(sleepDisabled())
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard !busy else { return }
        ticks += 1
        let checkBattery = ticks % 20 == 0          // once a minute
        DispatchQueue.global(qos: .utility).async {
            var awake = sleepDisabled()
            var message: String?
            if checkBattery {
                if awake && batteryIsLow() {
                    if setSleepDisabledSilently(false) {
                        awake = false
                        message = L("Pil azaldı, Mac yeniden normal uyuyacak.", "Battery is low. This Mac can sleep again.")
                    } else if !self.warnedLowBattery {
                        self.warnedLowBattery = true
                        message = L("Pil azaldı ve Mac hâlâ uyumuyor.", "Battery is low and this Mac still cannot sleep.")
                    }
                } else if !batteryIsLow() {
                    self.warnedLowBattery = false
                }
            }
            DispatchQueue.main.async {
                self.show(awake)
                if let message = message { notify(message) }
            }
        }
    }

    private func stateText(_ awake: Bool) -> String {
        awake ? L("Açık: kapak kapansa da Mac uyumaz", "On: this Mac stays awake, even with the lid closed")
              : L("Kapalı: Mac normal uyur", "Off: this Mac sleeps normally")
    }

    private func show(_ awake: Bool) {
        guard let button = item.button else { return }
        button.image = statusImage(awake: awake, style: .current)
        button.toolTip = stateText(awake)
        button.setAccessibilityLabel("Uyku. " + stateText(awake))
    }

    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            toggle()
        }
    }

    private func toggle() {
        guard !busy else { return }
        busy = true
        item.button?.appearsDisabled = true
        _ = setSleepDisabled(!sleepDisabled())
        item.button?.appearsDisabled = false
        busy = false
        show(sleepDisabled())
    }

    private func showMenu() {
        let menu = NSMenu()
        let info = NSMenuItem(title: stateText(sleepDisabled()), action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())

        let icons = NSMenuItem(title: L("Simge", "Icon"), action: nil, keyEquivalent: "")
        let iconMenu = NSMenu()
        for style in IconStyle.allCases {
            let entry = NSMenuItem(title: style.title, action: #selector(pickIcon(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = style.rawValue
            entry.state = style == .current ? .on : .off
            iconMenu.addItem(entry)
        }
        icons.submenu = iconMenu
        menu.addItem(icons)

        let passwordless = NSMenuItem(title: L("Parola sorma", "Don't ask for my password"),
                                      action: #selector(togglePasswordless), keyEquivalent: "")
        passwordless.target = self
        passwordless.state = passwordlessInstalled ? .on : .off
        menu.addItem(passwordless)

        let login = NSMenuItem(title: L("Açılışta başlat", "Start at login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("Çıkış", "Quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func pickIcon(_ sender: NSMenuItem) {
        if let style = IconStyle(rawValue: sender.tag) { IconStyle.current = style }
        show(sleepDisabled())
    }

    @objc private func togglePasswordless() {
        if !(passwordlessInstalled ? removePasswordless() : installPasswordless()) { NSSound.beep() }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch { NSSound.beep() }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

// MARK: - Asset rendering (only used to produce the files in Resources/ and docs/)

func writePNG(width: CGFloat, height: CGFloat, scale: CGFloat, to path: String, draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

func renderAppIcon(to path: String) {
    writePNG(width: 1024, height: 1024, scale: 1, to: path) {
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        NSGradient(starting: NSColor(red: 0.20, green: 0.24, blue: 0.36, alpha: 1),
                   ending: NSColor(red: 0.08, green: 0.10, blue: 0.17, alpha: 1))?.draw(in: tile, angle: -90)
        drawEye(open: true, in: NSRect(x: 237, y: 312, width: 550, height: 400), color: .white)
    }
}

func renderPreview(to path: String) {
    let barW: CGFloat = 170, barH: CGFloat = 28, gap: CGFloat = 16, pad: CGFloat = 16, label: CGFloat = 22
    writePNG(width: pad * 2 + barW * 2 + gap, height: pad * 2 + barH + label, scale: 4, to: path) {
        let text: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                                   .foregroundColor: NSColor(white: 0.45, alpha: 1)]
        let clock: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                    .foregroundColor: NSColor.white]
        for (index, awake) in [true, false].enumerated() {
            let x0 = pad + CGFloat(index) * (barW + gap)
            let caption = (awake ? "stays awake" : "sleeps normally") as NSString
            caption.draw(at: NSPoint(x: x0 + (barW - caption.size(withAttributes: text).width) / 2, y: pad + barH + 6), withAttributes: text)
            NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x0, y: pad, width: barW, height: barH), xRadius: 7, yRadius: 7).fill()
            var x = x0 + barW - 10
            let time = "9:41" as NSString
            let timeSize = time.size(withAttributes: clock)
            x -= timeSize.width
            time.draw(at: NSPoint(x: x, y: pad + (barH - timeSize.height) / 2), withAttributes: clock)
            x -= 22 + 16
            drawEye(open: awake, in: NSRect(x: x, y: pad + (barH - 16) / 2, width: 22, height: 16), color: .white)
        }
    }
}

// MARK: - Start

let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--render-icon"), i + 1 < arguments.count { renderAppIcon(to: arguments[i + 1]); exit(0) }
if let i = arguments.firstIndex(of: "--render-preview"), i + 1 < arguments.count { renderPreview(to: arguments[i + 1]); exit(0) }
if arguments.contains("--login-off") { try? SMAppService.mainApp.unregister(); exit(0) }
if arguments.contains("--login-status") { print(SMAppService.mainApp.status == .enabled ? "enabled" : "disabled"); exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
