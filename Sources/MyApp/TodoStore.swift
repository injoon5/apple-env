import Foundation
import MyAppCore
import OSLog
import Observation

/// Observable wrapper around the `TodoList` value type, saved as JSON in Application Support.
@Observable
final class TodoStore {
    private(set) var list: TodoList

    private let fileURL: URL?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MyApp", category: "TodoStore")

    /// Pass `nil` to keep the list in memory only (previews, tests).
    init(fileURL: URL? = TodoStore.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
            let saved = try? JSONDecoder().decode(TodoList.self, from: data)
        {
            list = saved
        } else {
            list = TodoList()
        }
    }

    func add(_ title: String) {
        guard list.add(title) != nil else { return }
        save()
    }

    func toggle(_ item: TodoItem) {
        list.toggle(item.id)
        save()
    }

    func remove(_ item: TodoItem) {
        list.remove(item.id)
        save()
    }

    func removeCompleted() {
        list.removeCompleted()
        save()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(list).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save to-dos: \(error.localizedDescription)")
        }
    }

    nonisolated static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "todos.json")
    }
}
