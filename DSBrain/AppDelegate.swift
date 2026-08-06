import Cocoa
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var popoverHosting: NSViewController!
    private var statusBarHosting: NSHostingView<StatusBarView>!
    private let statusBarModel: StatusBarModel
    private var preferencesWindow: NSWindow?
    private let serverManager = ServerManager.shared
    private let fanController = FanController.shared
    private var refreshTimer: Timer?

    public override init() {
        statusBarModel = StatusBarModel(tray: ConfigManager.shared.load().tray)
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        loadConfigAndStart()
        fanController.start()
        startRefreshTimer()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        refreshTimer?.invalidate()
        fanController.resetIfNeededOnQuit()
        fanController.stop()
        serverManager.stop(killAdopted: false) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        // Bound the wait if graceful stop hangs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover.contentSize = NSSize(width: 400, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSApp.effectiveAppearance

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.image = nil
        button.title = ""
        button.toolTip = TrayStatus.stopped.tooltip

        statusBarHosting = makeStatusBarHosting()
        button.addSubview(statusBarHosting)
        pinStatusBarHosting(statusBarHosting, to: button)

        popoverHosting = makePopoverController()
        popover.contentViewController = popoverHosting
        updateTrayBadge()
    }

    private func pinStatusBarHosting(_ hosting: NSView, to button: NSStatusBarButton) {
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            hosting.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
    }

    private func makePopoverController() -> NSViewController {
        HostingViewController(rootView: PopoverView(
            serverManager: serverManager,
            fanController: fanController,
            onRestart: { [weak self] in self?.restartServer() },
            onQuit: { [weak self] in self?.quitApp() },
            onOpenPreferences: { [weak self] in self?.showPreferences() }
        ))
    }

    private func makeStatusBarHosting() -> NSHostingView<StatusBarView> {
        let hosting = NSHostingView(rootView: StatusBarView(
            serverManager: serverManager,
            fanController: fanController,
            model: statusBarModel
        ))
        hosting.appearance = NSAppearance(named: .darkAqua)
        return hosting
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        button.window?.makeKey()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        guard popover.isShown else { return }

        let savedAnimates = popover.animates
        popover.animates = false
        popover.performClose(nil)
        popover.animates = savedAnimates

        if let window = popover.contentViewController?.view.window {
            window.orderOut(nil)
        }
    }

    private func loadConfigAndStart() {
        let config = ConfigManager.shared.load()
        if config.autoStart {
            serverManager.start(config: config)
        }
    }

    private func restartServer() {
        let config = ConfigManager.shared.load()
        serverManager.restart(with: config)
    }

    private func quitApp() {
        closePopover()
        NSApplication.shared.terminate(nil)
    }

    private func showPreferences() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            self?.presentPreferencesWindow()
        }
    }

    private func presentPreferencesWindow() {
        if let existing = preferencesWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DSBrain Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreferencesView(
            fanController: fanController,
            onSaveAndRestart: { [weak self] config in
                self?.statusBarModel.reloadTrayConfig()
                self?.fanController.reloadConfig()
                self?.fanController.start()
                self?.serverManager.restart(with: config)
            }
        ))
        window.makeKeyAndOrderFront(nil)
        preferencesWindow = window
    }

    private func startRefreshTimer() {
        refreshTimer = RunLoopTimer.schedule(every: 1.0) { [weak self] _ in
            guard let self else { return }
            self.serverManager.tickActivity()
            self.updateTrayBadge()
        }
    }

    private func updateTrayBadge() {
        let status = TrayStatus.resolve(
            isRunning: serverManager.isRunning,
            errorMessage: serverManager.errorMessage,
            isLoadingModel: serverManager.isLoadingModel,
            isRequestBusy: serverManager.isRequestBusy
        )
        statusBarModel.trayStatus = status
        statusItem.button?.toolTip = status.tooltip

        if status == .busy || status == .loading {
            statusBarModel.badgePulseDimmed.toggle()
        } else {
            statusBarModel.badgePulseDimmed = false
        }
    }
}
