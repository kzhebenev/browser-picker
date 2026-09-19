import AppKit
import Foundation

// Правило: сайт (домен с поддоменами или маска) -> браузер (bundle id).
struct Rule: Codable, Identifiable, Equatable {
    var id = UUID()
    var pattern: String
    var browser: String

    enum CodingKeys: String, CodingKey { case pattern, browser }

    // "https://www.Nalog.ru/path" -> "www.nalog.ru", "*.gosuslugi.ru" -> "gosuslugi.ru"
    static func normalize(_ raw: String) -> String {
        var p = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where p.hasPrefix(scheme) {
            p.removeFirst(scheme.count)
        }
        if let slash = p.firstIndex(of: "/") { p = String(p[..<slash]) }
        // "*.site.ru" — то же, что "site.ru" (с поддоменами); маски вроде "*.kontur.*" оставляем
        if p.hasPrefix("*."), !p.dropFirst(2).contains(where: { $0 == "*" || $0 == "?" }) {
            p.removeFirst(2)
        }
        if p.contains("*") || p.contains("?") { return p }
        return Domain.normalizeHost(p)
    }

    var normalizedPattern: String { Rule.normalize(pattern) }

    // id живёт только в памяти (для списка в настройках), в сравнении не участвует
    static func == (a: Rule, b: Rule) -> Bool { a.pattern == b.pattern && a.browser == b.browser }

    func matches(host rawHost: String) -> Bool {
        let host = Domain.normalizeHost(rawHost)
        let p = normalizedPattern
        guard !p.isEmpty, !host.isEmpty else { return false }
        if p.contains("*") || p.contains("?") {
            // "*.kontur.*" подходит и для самого kontur.ru
            return fnmatch(p, host, 0) == 0 || (p.hasPrefix("*.") && fnmatch(String(p.dropFirst(2)), host, 0) == 0)
        }
        return host == p || host.hasSuffix("." + p)
    }
}

enum Trigger: String, Codable, CaseIterable, Identifiable {
    case optionCommand, option, controlOption, commandShift, controlCommand

    var id: String { rawValue }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .optionCommand: return [.option, .command]
        case .option: return [.option]
        case .controlOption: return [.control, .option]
        case .commandShift: return [.command, .shift]
        case .controlCommand: return [.control, .command]
        }
    }

    var title: String {
        switch self {
        case .optionCommand: return "⌥⌘ Option + Command"
        case .option: return "⌥ Option"
        case .controlOption: return "⌃⌥ Control + Option"
        case .commandShift: return "⇧⌘ Shift + Command"
        case .controlCommand: return "⌃⌘ Control + Command"
        }
    }

    func isPressed(_ current: NSEvent.ModifierFlags) -> Bool {
        current.intersection([.command, .option, .control, .shift]).isSuperset(of: flags)
    }
}

struct Config: Codable, Equatable {
    var defaultBrowser = "com.apple.Safari"
    var trigger = Trigger.optionCommand
    var rules: [Rule] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultBrowser = try c.decodeIfPresent(String.self, forKey: .defaultBrowser) ?? "com.apple.Safari"
        trigger = (try? c.decodeIfPresent(Trigger.self, forKey: .trigger)) ?? .optionCommand
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
    }

    // Из нескольких подходящих правил побеждает самое конкретное (длинный домен).
    func rule(for url: URL) -> Rule? {
        guard let host = url.host(percentEncoded: false) else { return nil }
        return rules
            .filter { $0.matches(host: host) }
            .max { $0.normalizedPattern.count < $1.normalizedPattern.count }
    }
}

enum Domain {
    // Зоны второго уровня, в которых «сайт» — это три последние метки
    static let secondLevelZones: Set<String> = [
        "gov.ru", "com.ru", "org.ru", "net.ru", "msk.ru", "spb.ru", "edu.ru", "ac.ru", "mil.ru",
        "com.kz", "gov.kz", "org.kz", "com.ua", "gov.by", "com.by",
        "co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "com.br", "co.jp", "com.cn", "com.tr",
        "co.il", "co.kr", "co.nz", "com.sg",
    ]

    // Хост в единый вид: нижний регистр, без точки в конце, кириллица — в punycode
    // (Foundation отдаёт один и тот же домен то юникодом, то %-кодами, то punycode)
    static func normalizeHost(_ host: String) -> String {
        var h = (host.removingPercentEncoding ?? host).lowercased()
        while h.hasSuffix(".") { h.removeLast() }
        if h.unicodeScalars.contains(where: { !$0.isASCII }),
           let ascii = URL(string: "https://\(h)")?.host(percentEncoded: false),
           ascii.unicodeScalars.allSatisfy(\.isASCII) {
            h = ascii.lowercased()
        }
        return h
    }

    static func isIP(_ host: String) -> Bool {
        host.contains(":") || host.allSatisfy { $0.isNumber || $0 == "." }
    }

    // Домен, который запоминается по галочке: lkfl2.nalog.ru -> nalog.ru, www.x.gov.ru -> x.gov.ru
    static func siteKey(for host: String) -> String {
        let h = normalizeHost(host)
        guard h.contains("."), !isIP(h) else { return h }
        let parts = h.split(separator: ".").map(String.init)
        guard parts.count > 2 else { return h }
        let lastTwo = parts.suffix(2).joined(separator: ".")
        if secondLevelZones.contains(lastTwo) {
            return parts.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }
}

// Госсайты, которым обычно нужен браузер с поддержкой ГОСТ-шифрования
let govPresetSites = [
    "diadoc.ru", "kontur.ru", "nalog.gov.ru", "nalog.ru", "gosuslugi.ru",
    "zakupki.gov.ru", "sfr.gov.ru", "rosreestr.gov.ru", "fedresurs.ru",
]

final class Store: ObservableObject {
    static let shared = Store()

    @Published var config: Config {
        didSet { if config != oldValue { save() } }
    }

    let fileURL: URL
    private var loadedModified: Date?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrowserPicker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")
        config = Config()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            reload()
        } else {
            save()
        }
    }

    private var fileModified: Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    func reload() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let loaded = try JSONDecoder().decode(Config.self, from: data)
            loadedModified = fileModified
            if loaded != config { config = loaded }
        } catch {
            NSLog("BrowserPicker: не удалось прочитать \(fileURL.path): \(error)")
        }
    }

    // Файл могли поправить руками — перечитываем, если он изменился
    func reloadIfChanged() {
        if fileModified != loadedModified { reload() }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(config) else { return }
        try? data.write(to: fileURL, options: .atomic)
        loadedModified = fileModified
    }

    func setRule(pattern: String, browser: String) {
        let key = Rule.normalize(pattern)
        var rules = config.rules.filter { $0.normalizedPattern != key }
        rules.append(Rule(pattern: pattern, browser: browser))
        config.rules = rules
    }
}
