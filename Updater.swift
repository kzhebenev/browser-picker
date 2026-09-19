import AppKit

// Обновления через релизы GitHub, как в LayoutGlow: проверка при запуске и раз в сутки,
// по согласию скачивается DMG из последнего релиза и заменяет приложение в /Applications.
// Загрузка через URLSession не ставит карантин, поэтому Gatekeeper обновление не блокирует,
// а подпись тем же сертификатом сохраняет выданный «Универсальный доступ».
final class Updater {
    static let repo = "kzhebenev/browser-picker"
    private let latestAPI = URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!
    private let releasesPage = URL(string: "https://github.com/\(Updater.repo)/releases/latest")!
    private var timer: Timer?
    private var busy = false

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.check(manual: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.check(manual: false)
        }
    }

    func check(manual: Bool) {
        guard !busy else { return }
        var request = URLRequest(url: latestAPI)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                Log.write("проверка обновлений не удалась: \(error?.localizedDescription ?? "нет релизов")")
                if manual {
                    DispatchQueue.main.async {
                        self.alert("Не удалось проверить обновления", "Страница релизов недоступна. Возможно, нет сети.")
                    }
                }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let current = Updater.currentVersion
            let newer = latest.compare(current, options: .numeric) == .orderedDescending
            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmgURL = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }?["browser_download_url"] as? String
            let notes = (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                guard newer else {
                    if manual { self.alert("Обновлений нет", "Установлена последняя версия \(current).") }
                    return
                }
                Log.write("доступна версия \(latest)")
                let text = "Установлена \(current). Обновить сейчас? Приложение перезапустится."
                    + (notes.isEmpty ? "" : "\n\n\(notes.prefix(600))")
                guard self.confirm("Доступна версия BrowserPicker \(latest)", text) else { return }
                if let dmgURL, let url = URL(string: dmgURL) {
                    self.install(from: url)
                } else {
                    NSWorkspace.shared.open(self.releasesPage)
                }
            }
        }.resume()
    }

    private func install(from url: URL) {
        busy = true
        Log.write("загрузка обновления: \(url.absoluteString)")
        URLSession.shared.downloadTask(with: url) { [weak self] tmp, _, error in
            guard let self else { return }
            guard let tmp, error == nil else {
                DispatchQueue.main.async {
                    self.busy = false
                    self.alert("Не удалось скачать обновление", error?.localizedDescription ?? "")
                }
                return
            }
            let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("BrowserPicker-update.dmg")
            try? FileManager.default.removeItem(at: dmg)
            try? FileManager.default.moveItem(at: tmp, to: dmg)

            // Ставим туда же, где лежит текущая копия (обычно /Applications)
            let target = Bundle.main.bundleURL.path
            let script = """
            set -e
            MP=$(mktemp -d)
            hdiutil attach -nobrowse -quiet -mountpoint "$MP" "\(dmg.path)"
            test -d "$MP/BrowserPicker.app"
            while pgrep -x BrowserPicker >/dev/null; do sleep 0.2; done
            rm -rf "\(target)"
            cp -R "$MP/BrowserPicker.app" "\(target)"
            hdiutil detach -quiet "$MP" || true
            rm -f "\(dmg.path)"
            open "\(target)"
            """
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("browserpicker-update.sh")
            try? script.write(to: path, atomically: true, encoding: .utf8)

            DispatchQueue.main.async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/bash")
                task.arguments = [path.path]
                do {
                    try task.run()
                    Log.write("устанавливаю обновление и перезапускаюсь")
                    NSApp.terminate(nil)
                } catch {
                    self.busy = false
                    self.alert("Не удалось установить обновление", error.localizedDescription)
                }
            }
        }.resume()
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    private func confirm(_ title: String, _ text: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "Обновить")
        a.addButton(withTitle: "Позже")
        return a.runModal() == .alertFirstButtonReturn
    }
}
