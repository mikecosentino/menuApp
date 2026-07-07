import SwiftUI

/// Shared selection state so the AppDelegate can open Settings focused on a specific app.
final class SettingsSelection: ObservableObject {
    @Published var id: UUID?
}

/// Settings UI for creating, editing, and removing menu apps.
struct SettingsView: View {
    @ObservedObject var store: MenuAppStore
    @ObservedObject var selectionModel: SettingsSelection

    private var selection: UUID? {
        get { selectionModel.id }
        nonmutating set { selectionModel.id = newValue }
    }

    /// A binding that looks the app up by id on every access (never captures an index),
    /// so it can't read past the end of the array while a deletion is in flight.
    private func binding(for id: UUID) -> Binding<MenuApp> {
        Binding(
            get: { store.apps.first(where: { $0.id == id }) ?? MenuApp(name: "", urlString: "") },
            set: { newValue in
                guard let idx = store.apps.firstIndex(where: { $0.id == id }) else { return }
                store.apps[idx] = newValue
                store.save()
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            if let id = selection, store.apps.contains(where: { $0.id == id }) {
                MenuAppEditor(app: binding(for: id))
            } else {
                ContentUnavailablePlaceholder()
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectionModel.id) {
                ForEach(store.apps) { app in
                    HStack {
                        Image(systemName: app.symbolName.isEmpty ? "globe" : app.symbolName)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name.isEmpty ? "Untitled" : app.name)
                                .lineLimit(1)
                            Text(app.urlString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .tag(app.id)
                }
                .onDelete { offsets in
                    store.remove(at: offsets)
                }
            }

            Divider()
            HStack(spacing: 4) {
                Button(action: addApp) {
                    Image(systemName: "plus")
                }
                .help("Add a menu app")

                Button(action: removeSelected) {
                    Image(systemName: "minus")
                }
                .help("Remove selected")
                .disabled(selection == nil)

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    private func addApp() {
        let new = MenuApp(name: "New Site", urlString: "https://")
        store.add(new)
        selection = new.id
    }

    private func removeSelected() {
        guard let id = selection, let app = store.apps.first(where: { $0.id == id }) else { return }
        store.remove(app)
        selection = store.apps.first?.id
    }
}

/// Editor form for a single menu app.
struct MenuAppEditor: View {
    @Binding var app: MenuApp
    @State private var symbolQuery = ""

    private var filteredSymbols: [String] {
        let q = symbolQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SymbolCatalog.all }
        return SymbolCatalog.all.filter { $0.contains(q) }
    }

    var body: some View {
        Form {
            Section("Site") {
                TextField("Name", text: $app.name)
                TextField("URL", text: $app.urlString, prompt: Text("https://example.com"))
                    .autocorrectionDisabled()
            }

            Section("User Agent") {
                Picker("Identify as", selection: $app.userAgentMode) {
                    ForEach(UserAgentMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                if app.userAgentMode == .custom {
                    TextField("Custom UA string", text: $app.customUserAgent)
                        .autocorrectionDisabled()
                        .font(.system(.caption, design: .monospaced))
                }
                Text("Controls how the site sees the window — e.g. Mobile Safari for the phone layout, or a desktop browser for the full site.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Window Size") {
                HStack {
                    Stepper(value: $app.width, in: 240...1400, step: 10) {
                        Text("Width: \(Int(app.width)) pt")
                    }
                }
                HStack {
                    Stepper(value: $app.height, in: 200...1400, step: 10) {
                        Text("Height: \(Int(app.height)) pt")
                    }
                }
                HStack(spacing: 8) {
                    presetButton("iPhone", 390, 760)
                    presetButton("Compact", 340, 560)
                    presetButton("Tall", 414, 896)
                }
                Text("You can also drag the window's bottom-right corner to resize; the size updates here live.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opacity: \(Int(app.opacity * 100))%")
                    HStack {
                        Image(systemName: "circle.dotted")
                            .foregroundStyle(.secondary)
                        Slider(value: $app.opacity, in: 0.2...1.0)
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Behavior") {
                Toggle("Always on top", isOn: $app.alwaysOnTop)
                Toggle("Keep open when it loses focus", isOn: $app.pinnedOpen)
                Toggle("Auto-hide toolbar", isOn: $app.autoHideToolbar)
                Text("Hides the window's toolbar to maximize the page; move the pointer to the top edge of the window to reveal it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Fit window to video in theater mode", isOn: $app.fitTheaterToVideo)
                Text("Entering theater mode resizes the window to the video's shape so there are no bars above or below it, and keeps that aspect ratio while you resize.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            symbolSection
        }
        .formStyle(.grouped)
        .padding()
    }

    private var symbolSection: some View {
        Section("Menubar Icon") {
            HStack {
                Image(systemName: SymbolCatalog.isValid(app.symbolName) ? app.symbolName : "globe")
                    .font(.system(size: 16))
                    .frame(width: 24)
                TextField("Search symbols (or type an exact SF Symbol name)", text: $symbolQuery)
                    .textFieldStyle(.roundedBorder)
                if SymbolCatalog.isValid(symbolQuery) && !filteredSymbols.contains(symbolQuery) {
                    Button("Use “\(symbolQuery)”") { app.symbolName = symbolQuery }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 9), spacing: 8) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button {
                            app.symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .frame(width: 28, height: 28)
                                .background(app.symbolName == symbol ? Color.accentColor.opacity(0.25) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.borderless)
                        .help(symbol)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 150)

            if filteredSymbols.isEmpty {
                Text("No matches. If you know the exact SF Symbol name, type it above and click “Use”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func presetButton(_ title: String, _ w: Double, _ h: Double) -> some View {
        Button(title) {
            app.width = w
            app.height = h
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct ContentUnavailablePlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Select a menu app, or add one with +")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
