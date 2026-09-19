import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var browsers = Browsers.all()
    @State private var isDefault = Browsers.isDefaultBrowser
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(isDefault ? "BrowserPicker назначен браузером по умолчанию"
                                   : "BrowserPicker не назначен браузером по умолчанию, ссылки его не достигнут")
                        .foregroundStyle(isDefault ? Color.secondary : Color.red)
                    Spacer()
                    if !isDefault {
                        Button("Назначить") {
                            Browsers.makeDefault { isDefault = Browsers.isDefaultBrowser }
                        }
                    }
                }
                browserPicker("Открывать ссылки в", selection: $store.config.defaultBrowser)
                Picker("Окно выбора при клике с", selection: $store.config.trigger) {
                    ForEach(Trigger.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { loginEnabled },
                    set: { setLogin($0) }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                if store.config.rules.isEmpty {
                    Text("Правил пока нет. Их можно добавить здесь или галочкой «Запомнить» в окне выбора.")
                        .foregroundStyle(.secondary)
                }
                ForEach($store.config.rules) { $rule in
                    HStack {
                        TextField("", text: $rule.pattern, prompt: Text("example.ru или *.example.*"))
                            .labelsHidden()
                            .frame(minWidth: 180)
                        browserPicker("", selection: $rule.browser)
                            .labelsHidden()
                            .frame(width: 200)
                        Button {
                            let id = rule.id
                            DispatchQueue.main.async { store.config.rules.removeAll { $0.id == id } }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Удалить правило")
                    }
                }
                HStack {
                    Button("Добавить правило") {
                        store.config.rules.append(Rule(pattern: "", browser: store.config.defaultBrowser))
                    }
                    Menu("Добавить госсайты") {
                        ForEach(browsers) { browser in
                            Button("Открывать в \(browser.name)") { addGovPreset(browser.id) }
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Файл настроек") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                }
            } header: {
                Text("Правила по сайтам")
            } footer: {
                Text("Домен учитывает поддомены: nalog.ru подходит и для lkfl2.nalog.ru. Маски: *, ?. Если подходят несколько правил, срабатывает самое длинное.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 440)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            browsers = Browsers.all()
            isDefault = Browsers.isDefaultBrowser
            loginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    @ViewBuilder
    private func browserPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(browsers) { browser in
                Label {
                    Text(browser.name)
                } icon: {
                    Image(nsImage: smallIcon(browser))
                }
                .tag(browser.id)
            }
            if !browsers.contains(where: { $0.id == selection.wrappedValue }) {
                Text(Browsers.name(for: selection.wrappedValue)).tag(selection.wrappedValue)
            }
        }
    }

    private func smallIcon(_ browser: Browser) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: browser.appURL.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private func addGovPreset(_ browserID: String) {
        for site in govPresetSites {
            store.setRule(pattern: site, browser: browserID)
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Не удалось: \(error.localizedDescription)"
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}
