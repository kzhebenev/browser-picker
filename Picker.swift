import AppKit

final class PickerPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

// Окно выбора браузера: иконки браузеров, 1-9 выбирают, Return — подсвеченный, Esc — отмена.
final class PickerController: NSObject, NSWindowDelegate {
    private let urls: [URL]
    private let browsers: [Browser]
    private let preselected: String
    private let siteKey: String?
    private let completion: (_ browser: Browser?, _ remember: Bool) -> Void

    private var panel: PickerPanel!
    private var rememberBox: NSButton?
    private var finished = false

    init(urls: [URL], browsers: [Browser], preselected: String,
         completion: @escaping (_ browser: Browser?, _ remember: Bool) -> Void) {
        self.urls = urls
        self.browsers = browsers
        self.preselected = preselected
        self.completion = completion
        if let host = urls.first?.host(percentEncoded: false), !host.isEmpty {
            siteKey = Domain.siteKey(for: host)
        } else {
            siteKey = nil
        }
    }

    func show() {
        panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.finish(nil) }
        panel.onKey = { [weak self] in self?.handleKey($0) ?? false }

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        panel.contentView = effect

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 30, left: 18, bottom: 16, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            root.topAnchor.constraint(equalTo: effect.topAnchor),
            root.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        let linkText = urls.count == 1 ? urls[0].absoluteString : "\(urls[0].absoluteString) и ещё \(urls.count - 1)"
        let urlLabel = NSTextField(labelWithString: linkText)
        urlLabel.font = .systemFont(ofSize: 12)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.toolTip = urls.map(\.absoluteString).joined(separator: "\n")
        urlLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(urlLabel)

        // Сетка иконок по 6 в ряд
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 6
        var row: NSStackView?
        for (index, browser) in browsers.enumerated() {
            if index % 6 == 0 {
                let r = NSStackView()
                r.orientation = .horizontal
                r.spacing = 6
                grid.addArrangedSubview(r)
                row = r
            }
            row?.addArrangedSubview(makeButton(browser, index: index))
        }
        root.addArrangedSubview(grid)

        if let siteKey {
            let box = NSButton(checkboxWithTitle: "Запомнить для \(siteKey) (⇧ + цифра)", target: nil, action: nil)
            box.state = .off
            root.addArrangedSubview(box)
            rememberBox = box
        }

        let bottom = NSStackView()
        bottom.orientation = .horizontal
        bottom.spacing = 8
        let hint = NSTextField(labelWithString: "1–9 выбрать · ↩ подсвеченный · Esc отмена")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let copy = NSButton(title: "Скопировать ссылку", target: self, action: #selector(copyLink))
        copy.controlSize = .small
        let cancel = NSButton(title: "Отмена", target: self, action: #selector(cancelPressed))
        cancel.controlSize = .small
        [hint, spacer, copy, cancel].forEach(bottom.addArrangedSubview)
        root.addArrangedSubview(bottom)
        bottom.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true

        panel.layoutIfNeeded()
        let size = root.fittingSize
        panel.setContentSize(NSSize(width: max(size.width, 420), height: size.height))
        positionNearMouse()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
    }

    private func makeButton(_ browser: Browser, index: Int) -> NSButton {
        let button = NSButton(title: browser.name, image: browser.icon, target: self, action: #selector(buttonPressed(_:)))
        button.tag = index
        button.imagePosition = .imageAbove
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.font = .systemFont(ofSize: 11)
        button.lineBreakMode = .byTruncatingTail
        button.refusesFirstResponder = true
        button.toolTip = index < 9 ? "\(browser.name) — клавиша \(index + 1)" : browser.name
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        if browser.id == preselected {
            button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 92),
            button.heightAnchor.constraint(equalToConstant: 96),
        ])
        return button
    }

    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { panel.center(); return }
        var frame = panel.frame
        frame.origin.x = mouse.x - frame.width / 2
        frame.origin.y = mouse.y - frame.height - 12
        frame.origin.x = min(max(frame.origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
        frame.origin.y = min(max(frame.origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
        panel.setFrame(frame, display: false)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 36 || event.keyCode == 76 { // Return, Enter
            if let browser = browsers.first(where: { $0.id == preselected }) ?? browsers.first {
                finish(browser)
            }
            return true
        }
        // Цифры по keyCode: с Shift символы другие, а ⌥⌘ после клика ещё могут быть зажаты
        let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
                                        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9]
        if let digit = digitKeys[event.keyCode], digit <= browsers.count {
            // Shift + цифра — выбрать и запомнить для сайта
            if event.modifierFlags.contains(.shift) { rememberBox?.state = .on }
            finish(browsers[digit - 1])
            return true
        }
        return false
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        finish(browsers[sender.tag])
    }

    @objc private func cancelPressed() { finish(nil) }

    @objc private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
        finish(nil)
    }

    private func finish(_ browser: Browser?) {
        guard !finished else { return }
        finished = true
        let remember = rememberBox?.state == .on
        panel.orderOut(nil)
        panel.close()
        completion(browser, remember)
    }

    // Закрытие крестиком — то же, что отмена
    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }
}
