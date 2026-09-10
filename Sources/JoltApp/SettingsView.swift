import AppKit
import Carbon.HIToolbox
import JoltCore
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var preferences: AppPreferences
  @State private var cachedByteCount: Int64?
  @State private var isClearing = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
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
              title: "Background",
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
              Picker("Results", selection: $preferences.searchResultLimit) {
                ForEach(SearchResultLimit.allCases) { limit in
                  Text(limit.title).tag(limit)
                }
              }
              .labelsHidden()
              .pickerStyle(.menu)
              .frame(width: 210)
            }
            SettingsDivider()
            SettingsRow(
              title: "Scope Bar",
              detail: "Choose how Project and Issue Type filters are arranged."
            ) {
              Picker("Scope Bar", selection: $preferences.scopeBarLayout) {
                ForEach(ScopeBarLayoutMode.allCases) { mode in
                  Text(mode.title).tag(mode)
                }
              }
              .labelsHidden()
              .pickerStyle(.menu)
              .frame(width: 210)
            }
          }
        }

        settingsSection("Keyboard Shortcut") {
          VStack(spacing: 0) {
            SettingsRow(
              title: "Show or Hide Jolt",
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

        settingsSection("Mac Behavior") {
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

        settingsSection("About") {
          aboutRow
        }

        if let error = model.errorMessage {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(.horizontal, 4)
        }
      }
      .padding(28)
    }
    .frame(width: 680, height: 650)
    .background(Color(nsColor: .windowBackgroundColor))
    .task { await refreshCachedByteCount() }
    .onChange(of: preferences.searchResultLimit) { _, _ in
      model.scheduleSearch(immediate: true)
    }
    .onDisappear { model.settingsDidClose() }
  }

  @ViewBuilder
  private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
        .foregroundStyle(.secondary)
        .padding(.leading, 4)

      content()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
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
    HStack(alignment: .center, spacing: 24) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.body.weight(.medium))
        if let detail {
          Text(detail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      trailing()
        .fixedSize(horizontal: true, vertical: false)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }
}

private struct SettingsDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 18)
  }
}

private struct ThemePicker: View {
  @Binding var selection: AppearanceMode

  var body: some View {
    HStack(spacing: 8) {
      ForEach(AppearanceMode.allCases) { mode in
        Button {
          selection = mode
        } label: {
          VStack(spacing: 5) {
            Image(systemName: mode.systemImage)
              .font(.system(size: 15, weight: .semibold))
            Text(mode == .automatic ? "Auto" : mode.title)
              .font(.caption.weight(.medium))
          }
          .foregroundStyle(selection == mode ? Color.accentColor : Color.secondary)
          .frame(width: 64, height: 44)
          .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .background(
            selection == mode ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(
                selection == mode ? Color.accentColor : Color.secondary.opacity(0.25),
                lineWidth: selection == mode ? 2 : 1
              )
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) appearance")
        .accessibilityAddTraits(selection == mode ? .isSelected : [])
      }
    }
  }
}

private struct BackgroundPicker: View {
  @Binding var selection: BackgroundMode

  var body: some View {
    VStack(spacing: 3) {
      Slider(value: sliderValue, in: 0...2, step: 1)
        .frame(width: 260)
        .accessibilityLabel("Background")
        .accessibilityValue(selection.title)

      ZStack {
        HStack {
          modeButton(.opaque)
          Spacer()
          modeButton(.clear)
        }
        modeButton(.tinted)
      }
      .frame(width: 260)
    }
  }

  private var sliderValue: Binding<Double> {
    Binding(
      get: {
        Double(BackgroundMode.allCases.firstIndex(of: selection) ?? 1)
      },
      set: { value in
        let index = min(max(Int(value.rounded()), 0), BackgroundMode.allCases.count - 1)
        selection = BackgroundMode.allCases[index]
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
          .frame(minWidth: 142, minHeight: 34)
          .padding(.horizontal, 8)
          .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          .background(
            isRecording ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
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
