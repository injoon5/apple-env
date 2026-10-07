import Foundation

/// A single to-do item.
public struct TodoItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

/// An ordered to-do list. Pure value type: the app wraps it in an observable model.
public struct TodoList: Hashable, Codable, Sendable {
    public private(set) var items: [TodoItem]

    public init(items: [TodoItem] = []) {
        self.items = items
    }

    /// Open items first, each group in insertion order.
    public var sorted: [TodoItem] {
        items.filter { !$0.isDone } + items.filter(\.isDone)
    }

    public var remainingCount: Int {
        items.count(where: { !$0.isDone })
    }

    /// Adds an item with a trimmed title. Returns `nil` and changes nothing when the title is blank.
    @discardableResult
    public mutating func add(_ title: String) -> TodoItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = TodoItem(title: trimmed)
        items.append(item)
        return item
    }

    public mutating func toggle(_ id: TodoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
    }

    public mutating func remove(_ id: TodoItem.ID) {
        items.removeAll { $0.id == id }
    }

    public mutating func removeCompleted() {
        items.removeAll(where: \.isDone)
    }
}
