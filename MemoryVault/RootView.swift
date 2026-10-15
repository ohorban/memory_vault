import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            LogMemoryView()
                .tabItem { Label("Log", systemImage: "square.and.pencil") }
                .tag(AppRouter.Tab.log)
            MemoriesView()
                .tabItem { Label("Memories", systemImage: "books.vertical") }
                .tag(AppRouter.Tab.memories)
            PeopleListView()
                .tabItem { Label("People", systemImage: "person.2") }
                .tag(AppRouter.Tab.people)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
        .sheet(item: $router.openMemory) { link in
            DeepLinkedMemoryView(id: link.id)
        }
    }
}

/// Opens a memory from a reminder notification.
private struct DeepLinkedMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var results: [Memory]

    init(id: UUID) {
        _results = Query(filter: #Predicate<Memory> { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let memory = results.first {
                    MemoryDetailView(memory: memory)
                } else {
                    ContentUnavailableView("Memory not found", systemImage: "questionmark.folder")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .vaultDestinations()
        }
    }
}
