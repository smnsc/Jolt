import AppKit
import SwiftUI

@main
struct JoltApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var model = AppModel.shared
  @StateObject private var preferences = AppPreferences.shared
  @StateObject private var updater = AppUpdater.shared

  var body: some Scene {
    MenuBarExtra("Jolt", image: "MenuBarIcon") {
      Button("Search Issues") { model.showSearchWindow() }
      Button("Reset Size and Center") { model.centerSearchWindow() }
      SettingsMenuButton()
        .environmentObject(model)
      Divider()
      Button("Check for Updates…") { updater.checkForUpdates() }
        .disabled(!updater.canCheckForUpdates)
      Link("Support Jolt on Ko-fi", destination: JoltLinks.support)
      Divider()
      Button("Quit Jolt") { NSApp.terminate(nil) }
    }

    Settings {
      SettingsView()
        .environmentObject(model)
        .environmentObject(preferences)
        .environmentObject(updater)
    }
    .commands {
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…") { updater.checkForUpdates() }
          .disabled(!updater.canCheckForUpdates)
      }
    }
  }
}

private struct SettingsMenuButton: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button("Settings…") {
      model.prepareToOpenSettings()
      openSettings()
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var searchPanel: SearchPanel?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let preferences = AppPreferences.shared
    preferences.applyDockPolicy()
    preferences.applyAppearance()
    let panel = SearchPanel(model: AppModel.shared, preferences: preferences)
    searchPanel = panel
    AppModel.shared.register(searchWindow: panel)
    do {
      try HotKeyService.shared.register(preferences.shortcut) {
        AppModel.shared.toggleSearchWindow()
      }
    } catch {
      AppModel.shared.shortcutErrorMessage = error.userFacingMessage
    }
    AppModel.shared.start()
    AppModel.shared.showSearchWindow()
    AppUpdater.shared.start()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    AppPreferences.shared.applyDockPolicy()
    AppModel.shared.applicationDidBecomeActive()
  }

  func applicationDidResignActive(_ notification: Notification) {
    AppModel.shared.applicationDidResignActive()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    // Finish the Dock/Finder reopen event before restoring our policy and window.
    // We handle presentation ourselves, so suppress AppKit's default reopen handling.
    AppModel.shared.handleReopen()
    return false
  }
}

struct WindowAccessor: NSViewRepresentable {
  let onResolve: (NSWindow) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window { onResolve(window) }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      if let window = nsView.window { onResolve(window) }
    }
  }
}

// A nonactivating panel can take keyboard focus while the invoking full-screen app
// remains active. This style must be set at construction, not toggled on a SwiftUI window.
@MainActor
final class SearchPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  init(model: AppModel, preferences: AppPreferences) {
    super.init(
      contentRect: NSRect(origin: .zero, size: SearchWindowMetrics.defaultSize),
      styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    title = "Jolt"
    identifier = NSUserInterfaceItemIdentifier("search")
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = false
    animationBehavior = .utilityWindow
    let root = GeometryReader { _ in
      SearchView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(
      minWidth: SearchWindowMetrics.minimumSize.width,
      minHeight: SearchWindowMetrics.minimumSize.height
    )
    .environmentObject(model)
    .environmentObject(preferences)
    .environmentObject(model.images)
    .onExitCommand { model.handleSearchEscape() }
    let hostingView = NSHostingView(rootView: root)
    // AppModel owns minimum sizing; changing search content must not resize the panel.
    hostingView.sizingOptions = []
    contentView = hostingView
  }
}
