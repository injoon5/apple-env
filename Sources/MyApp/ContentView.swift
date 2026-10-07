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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear done", systemImage: "checkmark.circle.badge.xmark") {
                            store.removeCompleted()
                        }
                    }
                }
            }
            .overlay {
                if store.list.items.isEmpty {
                    ContentUnavailableView(
                        "Nothing to do",
                        systemImage: "checkmark.circle",
                        description: Text("Add a to-do below.")
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                AddBar(title: $newTitle, isFocused: $isAdding) { add() }
            }
        }
    }

    private func add() {
        store.add(newTitle)
        newTitle = ""
        isAdding = true
    }
}

/// Liquid Glass input bar: a glass text field and a prominent glass button
/// that blend into each other inside one container.
private struct AddBar: View {
    @Binding var title: String
    var isFocused: FocusState<Bool>.Binding
    let add: () -> Void

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                TextField("New to-do", text: $title)
                    .focused(isFocused)
                    .submitLabel(.done)
                    .onSubmit { add() }
                    .padding(.horizontal, 20)
                    .frame(minHeight: 52)
                    .glassEffect(.regular.interactive(), in: .capsule)

                Button {
                    add()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(!canAdd)
                .accessibilityLabel("Add to-do")
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
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
