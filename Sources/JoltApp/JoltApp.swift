import AppKit
import SwiftUI

@main
struct JoltApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var model = AppModel.shared
  @StateObject private var preferences = AppPreferences.shared

  var body: some Scene {
    Window("Jolt", id: "search") {
      SearchView()
        .environmentObject(model)
        .environmentObject(preferences)
        .environmentObject(model.images)
        .background(
          WindowAccessor { window in
            window.identifier = NSUserInterfaceItemIdentifier("search")
            model.register(searchWindow: window)
          }
        )
        .onExitCommand { model.handleSearchEscape() }
    }
    .defaultSize(
      width: SearchWindowMetrics.defaultSize.width,
      height: SearchWindowMetrics.defaultSize.height
    )
    .windowResizability(.contentMinSize)
    .windowStyle(.hiddenTitleBar)

    MenuBarExtra("Jolt", systemImage: "magnifyingglass") {
      Button("Search Issues") { model.showSearchWindow() }
      Button("Reset Size and Center") { model.centerSearchWindow() }
      SettingsMenuButton()
        .environmentObject(model)
      Divider()
      Button("Quit Jolt") { NSApp.terminate(nil) }
    }

    Settings {
      SettingsView()
        .environmentObject(model)
        .environmentObject(preferences)
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
  func applicationDidFinishLaunching(_ notification: Notification) {
    let preferences = AppPreferences.shared
    preferences.applyDockPolicy()
    preferences.applyAppearance()
    do {
      try HotKeyService.shared.register(preferences.shortcut) {
        AppModel.shared.showSearchWindow()
      }
    } catch {
      AppModel.shared.errorMessage = error.userFacingMessage
    }
    AppModel.shared.start()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    AppModel.shared.showSearchWindow()
    return true
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
