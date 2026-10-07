import Foundation
import Testing

@testable import MyAppCore

@Suite struct TodoListTests {
    @Test func addTrimsTitle() throws {
        var list = TodoList()
        let added = list.add("  Buy milk \n")
        let item = try #require(added)
        #expect(item.title == "Buy milk")
        #expect(list.items == [item])
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func addIgnoresBlankTitles(_ title: String) {
        var list = TodoList()
        let added = list.add(title)
        #expect(added == nil)
        #expect(list.items.isEmpty)
    }

    @Test func toggleAndCount() throws {
        var list = TodoList()
        let added = list.add("First")
        let first = try #require(added)
        list.add("Second")
        #expect(list.remainingCount == 2)

        list.toggle(first.id)
        #expect(list.remainingCount == 1)
        #expect(list.sorted.map(\.title) == ["Second", "First"])

        list.toggle(first.id)
        #expect(list.remainingCount == 2)
    }

    @Test func removeCompleted() {
        var list = TodoList()
        list.add("Done")
        list.add("Open")
        list.toggle(list.items[0].id)

        list.removeCompleted()
        #expect(list.items.map(\.title) == ["Open"])
    }

    @Test func removeByID() {
        var list = TodoList()
        list.add("Keep")
        list.add("Drop")

        list.remove(list.items[1].id)
        #expect(list.items.map(\.title) == ["Keep"])
    }

    @Test func codableRoundTrip() throws {
        var list = TodoList()
        list.add("Persist me")
        let data = try JSONEncoder().encode(list)
        #expect(try JSONDecoder().decode(TodoList.self, from: data) == list)
    }
}
