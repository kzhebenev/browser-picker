import AppKit

struct Browser: Identifiable, Hashable {
    let id: String // bundle id
    let name: String
    let appURL: URL

    var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        image.size = NSSize(width: 64, height: 64)
        return image
    }
}

enum Browsers {
    static let ownID = Bundle.main.bundleIdentifier ?? "ru.devkz.browserpicker"
    private static let probe = URL(string: "https://example.com")!

    // Все приложения, умеющие открывать https, кроме нас самих
    static func all() -> [Browser] {
        var seen = Set<String>()
        var result: [Browser] = []
        for url in NSWorkspace.shared.urlsForApplications(toOpen: probe) {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  id != ownID, !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(Browser(id: id, name: displayName(url), appURL: url))
        }
        // Safari первым, остальные по алфавиту
        return result.sorted {
            if ($0.id == "com.apple.Safari") != ($1.id == "com.apple.Safari") { return $0.id == "com.apple.Safari" }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func displayName(_ appURL: URL) -> String {
        var name = FileManager.default.displayName(atPath: appURL.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return name
    }

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return "\(bundleID) (не установлен)"
        }
        return displayName(url)
    }

    static func open(_ urls: [URL], with bundleID: String) {
        var target = bundleID
        if target == ownID || NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) == nil {
            NSLog("BrowserPicker: браузер \(bundleID) не найден, открываю в Safari")
            target = "com.apple.Safari"
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: cfg) { _, error in
            if let error { NSLog("BrowserPicker: ошибка открытия в \(target): \(error)") }
        }
    }

    static var isDefaultBrowser: Bool {
        ["http", "https"].allSatisfy { scheme in
            guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://example.com")!) else {
                return false
            }
            return Bundle(url: url)?.bundleIdentifier == ownID
        }
    }

    // macOS сама покажет диалог подтверждения смены браузера
    static func makeDefault(completion: @escaping () -> Void) {
        let me = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "http") { _ in
            NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "https") { _ in
                DispatchQueue.main.async(execute: completion)
            }
        }
    }
}
