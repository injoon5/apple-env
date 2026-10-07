import MyAppCore
import SwiftUI

struct ContentView: View {
    @Environment(TodoStore.self) private var store
    @State private var newTitle = ""
    @FocusState private var isAdding: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("New to-do", text: $newTitle)
                        .focused($isAdding)
                        .submitLabel(.done)
                        .onSubmit { add() }
                }
                Section {
                    ForEach(store.list.sorted) { item in
                        TodoRow(item: item) { store.toggle(item) }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    store.remove(item)
                                }
                            }
                    }
                } footer: {
                    if !store.list.items.isEmpty {
                        Text("\(store.list.remainingCount) remaining")
                    }
                }
            }
            .animation(.default, value: store.list)
            .navigationTitle("To-dos")
            .toolbar {
                if store.list.items.contains(where: \.isDone) {
                    Button("Clear done") { store.removeCompleted() }
                }
            }
            .overlay {
                if store.list.items.isEmpty && !isAdding {
                    ContentUnavailableView(
                        "Nothing to do", systemImage: "checkmark.circle",
                        description: Text("Add a to-do above."))
                }
            }
        }
    }

    private func add() {
        store.add(newTitle)
        newTitle = ""
        isAdding = true
    }
}

private struct TodoRow: View {
    let item: TodoItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Label {
                Text(item.title)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
            } icon: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .accessibilityValue(item.isDone ? Text("Done") : Text("Not done"))
    }
}

#Preview {
    ContentView()
        .environment(TodoStore(fileURL: nil))
}
