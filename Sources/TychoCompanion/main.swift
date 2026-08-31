import AppKit
import SpriteKit
import TychoCompanionKit

@main @MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let coordinator = DisplayCoordinator()
    private var inspectTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "water.waves", accessibilityDescription: "Tycho Companion")
        let menu = NSMenu()
        menu.addItem(withTitle: "Hide Diorama", action: #selector(toggleVisible), keyEquivalent: "")
        menu.addItem(withTitle: "Inspect for 15 seconds", action: #selector(enableInspect), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh demo scene", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings / connection guidance", action: #selector(showGuidance), keyEquivalent: ",")
        let open = menu.addItem(withTitle: "Open Tycho", action: #selector(openTycho), keyEquivalent: "")
        open.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tycho Companion", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
        coordinator.show(catalog: DemoSnapshot.catalog)
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }
    @objc private func toggleVisible() { coordinator.isVisible ? coordinator.hide() : coordinator.show(catalog: DemoSnapshot.catalog); statusItem.menu?.item(at: 0)?.title = coordinator.isVisible ? "Hide Diorama" : "Show Diorama" }
    @objc private func enableInspect() { coordinator.setInspect(true); inspectTimer?.invalidate(); inspectTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in Task { @MainActor in self?.coordinator.setInspect(false) } } }
    @objc private func refresh() { coordinator.show(catalog: DemoSnapshot.catalog) }
    @objc private func displaysChanged() { if coordinator.isVisible { coordinator.show(catalog: DemoSnapshot.catalog) } }
    @objc private func sleep() { coordinator.pause(true) }
    @objc private func wake() { coordinator.pause(false); refresh() }
    @objc private func showGuidance() { NSApp.activate(ignoringOtherApps: true); let alert = NSAlert(); alert.messageText = "Connection boundary"; alert.informativeText = "This runnable slice displays a local demo by default. The next slice may accept only a configured loopback, Tailscale .ts.net, or MagicDNS HTTPS origin. It will keep a bearer token in Keychain, never UserDefaults or logs, and use only GET /servers/activity and GET /servers/resources."; alert.addButton(withTitle: "OK"); alert.runModal() }
    @objc private func openTycho() { /* Enabled only after a safe configured origin exists. */ }
    @objc private func quit() { NSApp.terminate(nil) }
}

private enum DemoSnapshot {
    static let catalog = ActivityCatalog(servers: [
        ActivityServer(key: "demo", name: "Demo shore", agents: [
            ActivityAgent(key: "harbor", name: "Harbor keeper", projectKey: "harbor", state: .running),
            ActivityAgent(key: "lantern", name: "Lantern keeper", projectKey: "lantern", state: .idle, unread: true),
            ActivityAgent(key: "gate", name: "Gate keeper", projectKey: "gate", state: .awaitingInput, promptQueueCount: 1),
            ActivityAgent(key: "weather", name: "Weather keeper", projectKey: "weather", state: .blocked)
        ])
    ])
}

@MainActor private final class DisplayCoordinator {
    private var windows: [ScenePanel] = []; private(set) var isVisible = false
    func show(catalog: ActivityCatalog) {
        let entities = SceneMapper.map(NormalizedSnapshot(catalog: catalog)); let screens = [NSScreen.main].compactMap { $0 }
        for window in windows { window.orderOut(nil) }; windows = screens.map { screen in
            let frame = screen.visibleFrame; let stripHeight = min(140, max(96, frame.height * 0.16)); let rect = NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: stripHeight)
            let panel = ScenePanel(frame: rect, entities: entities); panel.orderFrontRegardless(); return panel
        }; isVisible = true
    }
    func hide() { windows.forEach { $0.orderOut(nil); $0.pause(true) }; isVisible = false }
    func setInspect(_ active: Bool) { windows.forEach { $0.setInspect(active) } }
    func pause(_ paused: Bool) { windows.forEach { $0.pause(paused) } }
}

@MainActor private final class ScenePanel: NSPanel {
    private let spriteView: SKView
    init(frame: NSRect, entities: [SceneEntity]) {
        spriteView = SKView(frame: frame); super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; ignoresMouseEvents = true; level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1); collectionBehavior = [.auxiliary, .fullScreenNone]; isReleasedWhenClosed = false
        spriteView.allowsTransparency = true; spriteView.preferredFramesPerSecond = 15; spriteView.presentScene(CoastalScene(size: frame.size, entities: entities)); contentView = spriteView
    }
    func setInspect(_ active: Bool) { ignoresMouseEvents = !active; spriteView.preferredFramesPerSecond = active ? 30 : 15 }
    func pause(_ paused: Bool) { spriteView.isPaused = paused }
}

@MainActor private final class CoastalScene: SKScene {
    init(size: CGSize, entities: [SceneEntity]) { super.init(size: size); scaleMode = .resizeFill; backgroundColor = .clear; build(entities) }
    required init?(coder: NSCoder) { nil }
    private func build(_ entities: [SceneEntity]) {
        let sea = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: 42)); sea.fillColor = NSColor(calibratedRed: 0.05, green: 0.18, blue: 0.25, alpha: 0.68); sea.strokeColor = .clear; addChild(sea)
        let shore = SKShapeNode(rect: CGRect(x: 0, y: 35, width: size.width, height: 15)); shore.fillColor = NSColor(calibratedRed: 0.62, green: 0.48, blue: 0.30, alpha: 0.9); shore.strokeColor = .clear; addChild(shore)
        let positions = StripLayout.positions(count: entities.count, width: size.width)
        for (index, entity) in entities.enumerated() { let site = WorkshopNode(entity: entity); site.position = CGPoint(x: positions[index], y: 48); addChild(site) }
    }
}

@MainActor private final class WorkshopNode: SKNode {
    init(entity: SceneEntity) { super.init(); let house = SKShapeNode(rectOf: CGSize(width: 32, height: 25), cornerRadius: 3); house.fillColor = entity.stale ? .gray : .init(calibratedRed: 0.36, green: 0.24, blue: 0.16, alpha: 0.95); house.strokeColor = .init(white: 0.9, alpha: 0.35); house.position = CGPoint(x: 0, y: 14); addChild(house)
        let roof = SKShapeNode(path: triangle()); roof.fillColor = .init(calibratedRed: 0.77, green: 0.35, blue: 0.23, alpha: 0.95); roof.strokeColor = .clear; roof.position = CGPoint(x: 0, y: 29); addChild(roof)
        let cue = SKShapeNode(circleOfRadius: 6); cue.position = CGPoint(x: 15, y: 17); cue.fillColor = color(for: entity.cue); cue.strokeColor = .white; cue.lineWidth = 1.5; addChild(cue)
        if entity.unread { let mailbox = SKShapeNode(rectOf: CGSize(width: 10, height: 8)); mailbox.fillColor = .init(calibratedRed: 1, green: 0.75, blue: 0.18, alpha: 1); mailbox.position = CGPoint(x: -19, y: 8); addChild(mailbox) }
        if entity.cue == .workbench && !entity.stale { let action = SKAction.sequence([.moveBy(x: 3, y: 0, duration: 1.2), .moveBy(x: -3, y: 0, duration: 1.2)]); cue.run(.repeatForever(action)) }
    }
    required init?(coder: NSCoder) { nil }
    private func triangle() -> CGPath { let path = CGMutablePath(); path.move(to: CGPoint(x: -20, y: 0)); path.addLine(to: CGPoint(x: 0, y: 13)); path.addLine(to: CGPoint(x: 20, y: 0)); path.closeSubpath(); return path }
    private func color(for cue: VisualCue) -> NSColor { switch cue { case .rest: .systemTeal; case .workbench: .systemBlue; case .questionLantern: .systemOrange; case .closedGate: .systemRed; case .warmLamp: .systemYellow; case .rainCloud: .systemIndigo; case .crackedSign: .systemPurple; case .stoppedTool: .systemGray } }
}
