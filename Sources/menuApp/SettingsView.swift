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

    private let symbolChoices = [
        "globe", "magnifyingglass", "envelope", "message", "bird", "music.note",
        "play.rectangle", "cart", "newspaper", "calendar", "checklist", "bubble.left",
        "photo", "bookmark", "house", "star", "bolt", "cloud"
    ]

    var body: some View {
        Form {
            Section("Site") {
                TextField("Name", text: $app.name)
                TextField("URL", text: $app.urlString, prompt: Text("https://example.com"))
                    .autocorrectionDisabled()
            }

            Section("Window Size") {
                HStack {
                    Stepper(value: $app.width, in: 280...900, step: 10) {
                        Text("Width: \(Int(app.width)) pt")
                    }
                }
                HStack {
                    Stepper(value: $app.height, in: 360...1200, step: 10) {
                        Text("Height: \(Int(app.height)) pt")
                    }
                }
                HStack(spacing: 8) {
                    presetButton("iPhone", 390, 760)
                    presetButton("Compact", 340, 560)
                    presetButton("Tall", 414, 896)
                }
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
            }

            Section("Menubar Icon") {
                Text("A monochrome symbol shown in the menubar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 9), spacing: 8) {
                    ForEach(symbolChoices, id: \.self) { symbol in
                        Button {
                            app.symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .frame(width: 28, height: 28)
                                .background(app.symbolName == symbol ? Color.accentColor.opacity(0.25) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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
