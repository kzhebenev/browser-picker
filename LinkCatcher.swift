import AppKit
import ApplicationServices

// Перехват кликов по ссылкам внутри приложений (прежде всего Safari).
// Клик ловится глобальным event tap, ссылка под курсором достаётся через Accessibility:
// браузеры отдают элемент AXLink с атрибутом AXURL. Нужен доступ «Универсальный доступ».
final class LinkCatcher {
    enum Decision {
        case pass
        case swallow(() -> Void) // съесть клик и выполнить действие
    }

    // Решение по клику; вызывается синхронно из event tap, должно быть быстрым
    var decide: ((_ location: CGPoint, _ flags: NSEvent.ModifierFlags) -> Decision)?

    private var tap: CFMachPort?
    private var swallowNextUp = false
    private var trustTimer: Timer?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    var isRunning: Bool { tap != nil }

    // Запускает перехват, как только появится разрешение
    func start() {
        if startTap() { return }
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            if self?.startTap() == true { timer.invalidate() }
        }
    }

    private func startTap() -> Bool {
        guard tap == nil else { return true }
        guard LinkCatcher.isTrusted else { return false }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: { _, type, event, refcon in
                                              let me = Unmanaged<LinkCatcher>.fromOpaque(refcon!).takeUnretainedValue()
                                              return me.handle(type, event)
                                          },
                                          userInfo: refcon) else {
            NSLog("BrowserPicker: не удалось создать event tap")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        NSLog("BrowserPicker: перехват кликов включён")
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .leftMouseUp:
            if swallowNextUp {
                swallowNextUp = false
                return nil
            }
            return pass
        case .leftMouseDown:
            // Флаги модификаторов CGEvent и NSEvent совпадают побитово
            let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            guard let decide, case let .swallow(action) = decide(event.location, flags) else { return pass }
            swallowNextUp = true
            DispatchQueue.main.async(execute: action)
            return nil
        default:
            return pass
        }
    }

    // MARK: - Accessibility

    private static var enabledPIDs = Set<pid_t>()

    // Chromium-браузеры строят дерево доступности веб-страницы только по запросу
    static func enableWebAccessibility(pid: pid_t, bundleID: String) {
        guard bundleID != "com.apple.Safari", !enabledPIDs.contains(pid) else { return }
        enabledPIDs.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // Ссылка под точкой экрана (глобальные координаты, начало — левый верхний угол)
    static func link(at point: CGPoint) -> (url: URL, pid: pid_t)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        // Поднимаемся от текста/картинки к ссылке, но не выше самой страницы
        for _ in 0..<12 {
            let role = string(element, kAXRoleAttribute)
            if role == "AXWebArea" || role == "AXWindow" || role == "AXApplication" { return nil }
            if role == "AXLink", let url = url(element) { return (url, pid) }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let next = parent, CFGetTypeID(next) == AXUIElementGetTypeID() else { return nil }
            element = next as! AXUIElement
        }
        return nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func url(_ element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success,
              let value else { return nil }
        if CFGetTypeID(value) == CFURLGetTypeID() {
            let url = value as! URL
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? url : nil
        }
        if let s = value as? String, let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }
        return nil
    }
}
