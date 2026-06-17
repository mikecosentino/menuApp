import Foundation
import Combine

/// Persists the list of menu apps to Application Support and publishes changes.
final class MenuAppStore: ObservableObject {
    @Published var apps: [MenuApp] = []

    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("menuApp", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("apps.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MenuApp].self, from: data) else {
            apps = MenuAppStore.defaultApps
            save()
            return
        }
        apps = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Mutations

    func add(_ app: MenuApp) {
        apps.append(app)
        save()
    }

    func update(_ app: MenuApp) {
        guard let idx = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[idx] = app
        save()
    }

    func remove(_ app: MenuApp) {
        apps.removeAll { $0.id == app.id }
        save()
    }

    func remove(at offsets: IndexSet) {
        apps.remove(atOffsets: offsets)
        save()
    }

    static let defaultApps: [MenuApp] = [
        MenuApp(name: "Google", urlString: "https://www.google.com", symbolName: "magnifyingglass")
    ]
}
