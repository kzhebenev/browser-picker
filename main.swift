import AppKit
import SwiftUI

// BrowserPicker: назначается браузером по умолчанию и раздаёт ссылки.
// Без модификатора — по правилам сайтов или в браузер по умолчанию,
// с зажатым модификатором (по умолчанию ⌥⌘) — показывает окно выбора.

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store.shared
    private var statusItem: NSStatusItem!
    private var pickers: [PickerController] = []
    private var settingsWindow: NSWindow?
    let catcher = LinkCatcher()
    private let updater = Updater()
    private var browserIDs = Set<String>()
    private var browserIDsUpdated = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch",
                                           accessibilityDescription: "BrowserPicker")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        catcher.decide = { [weak self] point, flags in
            self?.decideClick(at: point, flags: flags) ?? .pass
        }
        Log.write("запуск \(Updater.currentVersion), доступ к кликам: \(LinkCatcher.isTrusted ? "есть" : "нет")")
        if !LinkCatcher.isTrusted { LinkCatcher.promptForTrust() }
        catcher.start()
        updater.start()

        // Нет доступа к кликам — сразу показать настройки
        // (событие со ссылкой при запуске может прийти чуть позже didFinishLaunching)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [self] in
            if !LinkCatcher.isTrusted && !launchedByURL { showSettings() }
        }
    }

    private var launchedByURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        launchedByURL = true
        // browserpicker://pick?url=... — всегда показать окно выбора (для букмарклета в Safari)
        if url.scheme?.lowercased() == "browserpicker" {
            let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "url" }?.value
            if let target, let link = URL(string: target), ["http", "https"].contains(link.scheme?.lowercased() ?? "") {
                route([link], forcePicker: true)
            }
            return
        }
        route([url])
    }

    // html-файлы и прочее, что пришло как документ
    func application(_ application: NSApplication, open urls: [URL]) {
        launchedByURL = true
        route(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - Маршрутизация

    func route(_ urls: [URL], forcePicker: Bool = false) {
        guard !urls.isEmpty else { return }
        // Модификаторы читаем сразу, пока пользователь ещё держит клавиши
        let flags = NSEvent.modifierFlags
        store.reloadIfChanged()
        let config = store.config

        if forcePicker || config.trigger.isPressed(flags) {
            showPicker(urls, preselected: config.rule(for: urls[0])?.browser ?? config.defaultBrowser)
            return
        }

        // Ссылки из одной пачки могут вести на разные сайты
        var groups: [String: [URL]] = [:]
        var order: [String] = []
        for url in urls {
            let browser = config.rule(for: url)?.browser ?? config.defaultBrowser
            if groups[browser] == nil { order.append(browser) }
            groups[browser, default: []].append(url)
        }
        for browser in order {
            Browsers.open(groups[browser]!, with: browser)
        }
    }

    // Клик внутри приложения: ⌥⌘ по ссылке — окно выбора; обычный клик в браузере
    // по сайту с правилом на другой браузер — сразу туда. Иначе клик идёт как обычно.
    private func decideClick(at point: CGPoint, flags: NSEvent.ModifierFlags) -> LinkCatcher.Decision {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid() else { return .pass }
        store.reloadIfChanged()
        let config = store.config
        let frontID = front.bundleIdentifier ?? ""
        let triggered = config.trigger.isPressed(flags)
        let isBrowser = knownBrowserIDs().contains(frontID)

        if !triggered {
            guard config.applyRulesInBrowsers, isBrowser,
                  config.rules.contains(where: { $0.browser != frontID }) else { return .pass }
        }
        if isBrowser { LinkCatcher.enableWebAccessibility(pid: front.processIdentifier, bundleID: frontID) }
        guard let (url, pid) = LinkCatcher.link(at: point), pid != getpid() else {
            if triggered {
                Log.write("клик с модификатором в \(frontID): ссылки нет, под курсором \(LinkCatcher.describe(at: point))")
            }
            return .pass
        }

        if triggered {
            let preselected = config.rule(for: url)?.browser ?? config.defaultBrowser
            Log.write("окно выбора для \(url.host(percentEncoded: false) ?? "?")")
            return .swallow { [weak self] in self?.showPicker([url], preselected: preselected) }
        }
        guard let rule = config.rule(for: url), rule.browser != frontID,
              NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.browser) != nil else { return .pass }
        Log.write("\(url.host(percentEncoded: false) ?? "?") по правилу \(rule.pattern) -> \(rule.browser)")
        return .swallow { Browsers.open([url], with: rule.browser) }
    }

    private func knownBrowserIDs() -> Set<String> {
        if Date().timeIntervalSince(browserIDsUpdated) > 60 {
            browserIDs = Set(Browsers.all().map(\.id))
            browserIDsUpdated = Date()
        }
        return browserIDs
    }

    private func showPicker(_ urls: [URL], preselected: String) {
        let browsers = Browsers.all()
        var controller: PickerController!
        controller = PickerController(urls: urls, browsers: browsers, preselected: preselected) { [weak self] browser, remember in
            guard let self else { return }
            self.pickers.removeAll { $0 === controller }
            guard let browser else { return }
            if remember, let host = urls.first?.host(percentEncoded: false), !host.isEmpty {
                self.store.setRule(pattern: Domain.siteKey(for: host), browser: browser.id)
            }
            Browsers.open(urls, with: browser.id)
        }
        pickers.append(controller)
        controller.show()
    }

    // MARK: - Меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if catcher.isRunning {
            let status = NSMenuItem(title: "Клики по ссылкам перехватываются", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        } else {
            menu.addItem(item("Дать доступ к кликам (Универсальный доступ)…", #selector(openAccessibility)))
        }
        if !Browsers.isDefaultBrowser {
            menu.addItem(item("Ловить ссылки из других приложений…", #selector(makeDefault)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Открыть ссылку из буфера…", #selector(openFromClipboard), key: "v"))

        let defaults = NSMenuItem(title: "Открывать по умолчанию в", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for browser in Browsers.all() {
            let entry = item(browser.name, #selector(chooseDefault(_:)))
            entry.representedObject = browser.id
            entry.state = browser.id == store.config.defaultBrowser ? .on : .off
            let icon = browser.icon
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            sub.addItem(entry)
        }
        defaults.submenu = sub
        menu.addItem(defaults)

        menu.addItem(item("Настройки и правила…", #selector(showSettings), key: ","))
        menu.addItem(item("Версия \(Updater.currentVersion): проверить обновления", #selector(checkUpdates)))
        menu.addItem(.separator())
        menu.addItem(item("Выйти из BrowserPicker", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = target ?? self
        return i
    }

    @objc private func checkUpdates() { updater.check(manual: true) }

    @objc private func openAccessibility() {
        LinkCatcher.promptForTrust()
        LinkCatcher.openAccessibilitySettings()
    }

    @objc private func makeDefault() {
        Browsers.makeDefault {}
    }

    @objc private func chooseDefault(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.config.defaultBrowser = id
    }

    @objc private func openFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let urls = text.split(whereSeparator: \.isNewline)
            .compactMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        if urls.isEmpty {
            NSSound.beep()
            return
        }
        route(urls, forcePicker: true)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            window.title = "BrowserPicker"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 620, height: 520))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // Без главного меню в приложении-агенте не работают ⌘C/⌘V/⌘W в полях настроек
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Скопировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать все", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Окно")
        windowMenu.addItem(withTitle: "Закрыть", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }
}

// Самопроверка правил: BrowserPicker --selftest
func runSelfTest() -> Int32 {
    var failures = 0
    func check(_ cond: Bool, _ name: String) {
        if !cond { failures += 1; print("FAIL: \(name)") }
    }
    var cfg = Config()
    cfg.rules = [
        Rule(pattern: "nalog.ru", browser: "gost"),
        Rule(pattern: "https://www.Gosuslugi.ru/help", browser: "gost2"),
        Rule(pattern: "*.kontur.*", browser: "k"),
        Rule(pattern: "lkfl2.nalog.ru", browser: "specific"),
    ]
    func pick(_ s: String) -> String? { cfg.rule(for: URL(string: s)!)?.browser }
    check(pick("https://nalog.ru/x") == "gost", "точный домен")
    check(pick("https://service.nalog.ru") == "gost", "поддомен")
    check(pick("https://lkfl2.nalog.ru/lk") == "specific", "самое длинное правило")
    check(pick("https://notnalog.ru") == nil, "не путать суффикс без точки")
    check(pick("https://www.gosuslugi.ru") == "gost2", "нормализация схемы и пути")
    check(pick("https://esia.gosuslugi.ru") == nil, "www.gosuslugi.ru не покрывает esia")
    check(pick("https://auth.kontur.ru") == "k", "маска")
    check(pick("https://NALOG.RU.") == "gost", "регистр и точка в конце")
    check(pick("https://ya.ru") == nil, "нет правила")
    check(Domain.siteKey(for: "lkfl2.nalog.ru") == "nalog.ru", "siteKey обычный")
    check(Domain.siteKey(for: "www.zakupki.gov.ru") == "zakupki.gov.ru", "siteKey gov.ru")
    check(Domain.siteKey(for: "192.168.2.1") == "192.168.2.1", "siteKey IP")
    check(Domain.siteKey(for: "localhost") == "localhost", "siteKey localhost")
    check(Rule.normalize("*.diadoc.ru") == "diadoc.ru", "нормализация *.")
    check(Rule(pattern: "госуслуги.рф", browser: "x").matches(host: "www.xn--c1aapkosapc.xn--p1ai"), "кириллический домен")
    check(Rule(pattern: "xn--c1aapkosapc.xn--p1ai", browser: "x").matches(host: "госуслуги.рф"), "punycode в правиле")
    check(Rule(pattern: "госуслуги.рф", browser: "x").matches(host: "%D0%B3%D0%BE%D1%81%D1%83%D1%81%D0%BB%D1%83%D0%B3%D0%B8.%D1%80%D1%84"), "%-кодированный хост")
    check(pick("https://kontur.ru") == "k", "маска *.x.* и сам домен")
    check(pick("https://госуслуги.рф") == nil, "кириллица без правила")
    var shared = Config()
    shared.defaultBrowser = "shared-default"
    shared.rules = [Rule(pattern: "nalog.ru", browser: "gost"), Rule(pattern: "a.ru", browser: "x")]
    var local = Config()
    local.defaultBrowser = "local-default"
    local.rules = [Rule(pattern: "https://Nalog.ru", browser: "other"), Rule(pattern: "b.ru", browser: "y"), Rule(pattern: "", browser: "z")]
    let merged = Config.merge(shared: shared, local: local)
    check(merged.defaultBrowser == "shared-default", "слияние: общие настройки главнее")
    check(merged.rules.map(\.pattern) == ["nalog.ru", "a.ru", "b.ru"], "слияние: правила без дублей и пустых")
    check(merged.rule(for: URL(string: "https://nalog.ru")!)?.browser == "gost", "слияние: общее правило побеждает")
    check(Trigger.optionCommand.isPressed([.option, .command]), "триггер ⌥⌘")
    check(Trigger.optionCommand.isPressed([.option, .command, .shift]), "триггер с лишним Shift")
    check(!Trigger.optionCommand.isPressed([.command]), "только ⌘ не триггер")
    print(failures == 0 ? "OK: все проверки пройдены" : "Провалено: \(failures)")
    return failures == 0 ? 0 : 1
}

if CommandLine.arguments.contains("--selftest") {
    exit(runSelfTest())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
