import AppKit
import Carbon.HIToolbox
import JoltCore
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var preferences: AppPreferences
  @EnvironmentObject private var updater: AppUpdater
  @State private var cachedByteCount: Int64?
  @State private var isClearing = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        settingsSection("Appearance") {
          VStack(spacing: 0) {
            SettingsRow(
              title: "Theme",
              detail: "Choose how Jolt looks on this Mac."
            ) {
              ThemePicker(selection: $preferences.appearance)
            }
            SettingsDivider()
            SettingsRow(
              title: "Background transparency",
              detail: "Choose how much of the desktop shows through Jolt."
            ) {
              BackgroundPicker(selection: $preferences.background)
            }
          }
        }

        settingsSection("Search") {
          VStack(spacing: 0) {
            SettingsRow(
              title: "Results",
              detail: "Choose the maximum number of issues shown in Jolt."
            ) {
              SettingsMenuPicker(
                title: "Results",
                selection: $preferences.searchResultLimit,
                options: SearchResultLimit.allCases,
                optionTitle: { $0.title }
              )
            }
            SettingsDivider()
            SettingsRow(
              title: "Auto-reset search query",
              detail: "Clear the query after the search window is hidden."
            ) {
              SettingsMenuPicker(
                title: "Auto-reset search query",
                selection: $preferences.searchResetDelay,
                options: SearchResetDelay.allCases,
                optionTitle: { $0.title }
              )
            }
            SettingsDivider()
            SettingsRow(
              title: "Scope bar",
              detail: "Choose how Project and Issue Type filters are arranged."
            ) {
              SettingsMenuPicker(
                title: "Scope bar",
                selection: $preferences.scopeBarLayout,
                options: ScopeBarLayoutMode.allCases,
                optionTitle: { $0.title }
              )
            }
          }
        }

        settingsSection("Keyboard shortcut") {
          VStack(spacing: 0) {
            SettingsRow(
              title: "Show or hide Jolt",
              detail: "Use Command, Option, or Control with a key, or use F1–F12 by themselves. Shift alone isn’t supported."
            ) {
              ShortcutRecorderButton(
                shortcut: $preferences.shortcut,
                onValidationError: { model.shortcutErrorMessage = $0 },
                onReset: {
                  applyShortcut(.defaultShortcut)
                }
              ) { shortcut in
                applyShortcut(shortcut)
              }
            }

            if let error = model.shortcutErrorMessage {
              SettingsDivider()
              HStack(spacing: 7) {
                Spacer(minLength: 280)
                Label(error, systemImage: "exclamationmark.triangle")
                  .font(.caption)
                  .foregroundStyle(Color.red.opacity(0.72))
                  .fixedSize(horizontal: false, vertical: true)
              }
              .padding(.horizontal, 18)
              .padding(.vertical, 9)
            }
          }
        }

        settingsSection("Mac behavior") {
          VStack(spacing: 0) {
            SettingsRow(title: "Show in Dock and app switcher") {
              Toggle("Show in Dock and app switcher", isOn: $preferences.showDockIcon)
                .labelsHidden()
            }
            SettingsDivider()
            SettingsRow(
              title: "Start at login",
              detail: "Open Jolt automatically when you sign in."
            ) {
              Toggle(
                "Start at login",
                isOn: Binding(
                  get: { preferences.launchAtLogin },
                  set: { enabled in
                    do { try preferences.setLaunchAtLogin(enabled) } catch {
                      model.errorMessage = error.userFacingMessage
                    }
                  }
                )
              )
              .labelsHidden()
            }
          }
        }

        settingsSection("Jira & Data") {
          VStack(spacing: 0) {
            jiraAccountRow
            SettingsDivider()
            cachedDataRow
          }
        }

        settingsSection("Updates") {
          VStack(spacing: 0) {
            SettingsRow(title: "Check automatically", detail: "Look for new versions of Jolt each day.") {
              Toggle("Check automatically", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.setAutomaticChecks($0) }
              )).labelsHidden()
            }
            SettingsDivider()
            SettingsRow(title: "Download and install automatically", detail: "Install downloaded updates when you quit Jolt.") {
              Toggle("Download and install automatically", isOn: Binding(
                get: { updater.automaticallyDownloadsUpdates },
                set: { updater.setAutomaticDownloads($0) }
              ))
              .labelsHidden()
              .disabled(!updater.automaticallyChecksForUpdates)
            }
            SettingsDivider()
            SettingsRow(title: "Software updates", detail: "You may need to reconnect Jira after an update.") {
              Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
            }
            if let error = updater.startupError {
              Text("Updates are unavailable: \(error)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
            }
          }
        }

        settingsSection("About") {
          VStack(spacing: 0) {
            aboutRow
            SettingsDivider()
            SettingsRow(title: "Free and open source", detail: "Made by Simon. Supported by optional donations.") {
              HStack(spacing: 16) {
                Link("Source code", destination: JoltLinks.source)
                Link("Support Jolt on Ko-fi", destination: JoltLinks.support)
              }
            }
          }
        }

        if let error = model.errorMessage {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(.horizontal, 4)
        }
      }
      .padding(.horizontal, 30)
      .padding(.vertical, 26)
    }
    .frame(width: 740, height: 680)
    .background(Color(nsColor: .textBackgroundColor))
    .toggleStyle(.switch)
    .controlSize(.small)
    .task { await refreshCachedByteCount() }
    .onChange(of: preferences.searchResultLimit) { _, _ in
      model.scheduleSearch(immediate: true)
    }
    .background(
      WindowAccessor { window in
        model.register(settingsWindow: window)
      }
    )
    .onAppear { model.prepareToOpenSettings() }
    .onDisappear { model.settingsDidClose() }
  }

  @ViewBuilder
  private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.leading, 12)

      content()
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }

  private var jiraAccountRow: some View {
    SettingsRow(
      title: "Jira Account",
      detail: model.selectedSite.map { $0.url.host ?? $0.url.absoluteString }
        ?? "No API key saved"
    ) {
      if model.isAuthenticated {
        HStack(spacing: 10) {
          Link(destination: AtlassianURLs.apiTokens) {
            Label("Manage Atlassian API Key", systemImage: "arrow.up.right")
          }
          .buttonStyle(.borderless)

          Button("Delete…", role: .destructive) {
            model.logout()
          }
          .buttonStyle(.bordered)
        }
      } else {
        Text("Connect from the search window")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var cachedDataRow: some View {
    SettingsRow(
      title: "Cached Data",
      detail: "Metadata and issue-type images stored on this Mac."
    ) {
      HStack(spacing: 12) {
        Text(formattedCacheSize)
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)

        Button("Show in Finder") {
          Task {
            do {
              let directoryURL = try await model.cacheDirectoryURL()
              NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
            } catch {
              model.errorMessage = error.userFacingMessage
            }
          }
        }
        .buttonStyle(.borderless)

        Button("Clear…") {
          isClearing = true
          Task {
            await model.clearCachedData()
            await refreshCachedByteCount()
            isClearing = false
          }
        }
        .buttonStyle(.bordered)
        .disabled(isClearing)

        if isClearing {
          ProgressView()
            .controlSize(.small)
        }
      }
    }
  }

  private var aboutRow: some View {
    SettingsRow(
      title: "Jolt",
      detail: "Read-only Jira Cloud issue search"
    ) {
      Text("Version \(appVersion) (Build \(appBuildNumber))")
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
  }

  private var formattedCacheSize: String {
    guard let cachedByteCount else { return "Calculating…" }
    return ByteCountFormatter.string(fromByteCount: cachedByteCount, countStyle: .file)
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
  }

  private var appBuildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
      ?? "Development"
  }

  private func refreshCachedByteCount() async {
    cachedByteCount = await model.cachedDataByteCount()
  }

  private func applyShortcut(_ shortcut: KeyboardShortcutSpec) {
    do {
      try HotKeyService.shared.register(shortcut) { AppModel.shared.toggleSearchWindow() }
      preferences.shortcut = shortcut
      model.shortcutErrorMessage = nil
    } catch {
      model.shortcutErrorMessage = error.userFacingMessage
    }
  }
}

private struct SettingsRow<Trailing: View>: View {
  let title: String
  var detail: String?
  @ViewBuilder let trailing: () -> Trailing

  init(
    title: String,
    detail: String? = nil,
    @ViewBuilder trailing: @escaping () -> Trailing
  ) {
    self.title = title
    self.detail = detail
    self.trailing = trailing
  }

  var body: some View {
    HStack(alignment: .center, spacing: 28) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 13))
        if let detail {
          Text(detail)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      trailing()
        .fixedSize(horizontal: true, vertical: false)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
  }
}

private struct SettingsDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.07))
      .frame(height: 0.5)
      .padding(.horizontal, 12)
  }
}

// Use a native popup so the selected text and arrow share one reliable hit target.
private struct SettingsMenuPicker<Value: Hashable & Identifiable>: NSViewRepresentable {
  let title: String
  @Binding var selection: Value
  let options: [Value]
  let optionTitle: (Value) -> String

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = NSPopUpButton(frame: .zero, pullsDown: false)
    button.isBordered = false
    button.alignment = .right
    button.font = .systemFont(ofSize: 13)
    button.controlSize = .regular
    button.target = context.coordinator
    button.action = #selector(Coordinator.selectionChanged(_:))
    return button
  }

  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.parent = self
    let titles = options.map(optionTitle)
    if button.itemTitles != titles {
      button.removeAllItems()
      button.addItems(withTitles: titles)
    }
    if let index = options.firstIndex(of: selection) {
      button.selectItem(at: index)
    }
    button.setAccessibilityLabel(title)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
    CGSize(width: 190, height: 28)
  }

  final class Coordinator: NSObject {
    var parent: SettingsMenuPicker

    init(_ parent: SettingsMenuPicker) {
      self.parent = parent
    }

    @objc func selectionChanged(_ sender: NSPopUpButton) {
      let index = sender.indexOfSelectedItem
      guard parent.options.indices.contains(index) else { return }
      parent.selection = parent.options[index]
    }
  }
}

private struct ThemePicker: View {
  @Binding var selection: AppearanceMode

  var body: some View {
    SettingsMenuPicker(
      title: "Theme",
      selection: $selection,
      options: AppearanceMode.allCases,
      optionTitle: { $0 == .automatic ? "System" : $0.title }
    )
  }
}

private struct BackgroundPicker: View {
  @Binding var selection: BackgroundMode
  private let modes: [BackgroundMode] = [.clear, .tinted, .opaque]

  var body: some View {
    VStack(spacing: 3) {
      Slider(value: sliderValue, in: 0...2, step: 1)
        .frame(width: 190)
        .accessibilityLabel("Background")
        .accessibilityValue(selection.title)

      ZStack {
        HStack {
          modeButton(.clear)
          Spacer()
          modeButton(.opaque)
        }
        modeButton(.tinted)
      }
      .frame(width: 190)
    }
  }

  private var sliderValue: Binding<Double> {
    Binding(
      get: {
        Double(modes.firstIndex(of: selection) ?? 1)
      },
      set: { value in
        let index = min(max(Int(value.rounded()), 0), modes.count - 1)
        selection = modes[index]
      }
    )
  }

  private func modeButton(_ mode: BackgroundMode) -> some View {
    Button(mode.title) {
      selection = mode
    }
    .buttonStyle(.plain)
    .font(.caption.weight(selection == mode ? .semibold : .regular))
    .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
    .accessibilityAddTraits(selection == mode ? .isSelected : [])
  }
}

private struct ShortcutRecorderButton: View {
  @Binding var shortcut: KeyboardShortcutSpec
  let onValidationError: (String?) -> Void
  let onReset: () -> Void
  let onCommit: (KeyboardShortcutSpec) -> Void
  @State private var isRecording = false
  @State private var monitor: Any?

  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      HStack(spacing: 10) {
        Button {
          stopRecording()
          onValidationError(nil)
          onReset()
        } label: {
          Image(systemName: "arrow.counterclockwise")
            .font(.system(size: 14, weight: .medium))
            .frame(width: 28, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(shortcut == .defaultShortcut && !isRecording)
        .help("Reset to the default shortcut, Option-J")
        .accessibilityLabel("Reset keyboard shortcut to Option-J")

        Button {
          isRecording ? stopRecording() : startRecording()
        } label: {
          Group {
            if isRecording {
              HStack(spacing: 7) {
                Image(systemName: "keyboard")
                Text("Press shortcut…")
                  .fontWeight(.medium)
              }
            } else {
              HStack(spacing: 4) {
                ForEach(Array(shortcut.keycapLabels.enumerated()), id: \.offset) { _, label in
                  Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(minWidth: 25, minHeight: 24)
                    .padding(.horizontal, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
              }
            }
          }
          .frame(minWidth: 110, minHeight: 30)
          .padding(.horizontal, 8)
          .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          .background(
            isRecording ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .stroke(isRecording ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
          }
        }
        .buttonStyle(.plain)
      }

      Text(isRecording ? "Recording · Esc to cancel" : "Click to change")
        .font(.caption2)
        .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
    }
    .onDisappear { stopRecording() }
  }

  private func startRecording() {
    isRecording = true
    onValidationError(nil)
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == UInt16(kVK_Escape) {
        stopRecording()
        return nil
      }

      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      var carbonModifiers: UInt32 = 0
      if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
      if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
      if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
      if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

      let functionKey = KeyboardShortcutSpec.functionKeyName(for: UInt32(event.keyCode))
      let includesPrimaryModifier =
        carbonModifiers & (UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)) != 0
      guard includesPrimaryModifier || (carbonModifiers == 0 && functionKey != nil) else {
        onValidationError(
          "Press Command, Option, or Control with a key, or press F1–F12 by itself."
        )
        return nil
      }

      let key = functionKey ?? event.charactersIgnoringModifiers?.uppercased()
      guard let key, !key.isEmpty else { return nil }

      let captured = KeyboardShortcutSpec(
        keyCode: UInt32(event.keyCode),
        modifiers: carbonModifiers,
        key: key
      )
      onCommit(captured)
      stopRecording()
      return nil
    }
  }

  private func stopRecording() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    isRecording = false
  }
}

private extension KeyboardShortcutSpec {
  var keycapLabels: [String] {
    var labels: [String] = []
    if modifiers & UInt32(controlKey) != 0 { labels.append("⌃") }
    if modifiers & UInt32(optionKey) != 0 { labels.append("⌥") }
    if modifiers & UInt32(shiftKey) != 0 { labels.append("⇧") }
    if modifiers & UInt32(cmdKey) != 0 { labels.append("⌘") }
    labels.append(key.uppercased())
    return labels
  }
}
