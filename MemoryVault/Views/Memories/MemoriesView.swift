import SwiftData
import SwiftUI

struct MemoriesView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case timeline = "Timeline", calendar = "Calendar", people = "People", types = "Types"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Memory.sortDate, order: .reverse) private var memories: [Memory]
    @SceneStorage("memoriesMode") private var mode: Mode = .timeline
    @State private var search = ""
    @State private var randomMemory: Memory?
    @State private var showAsk = false

    private var searchResults: [Memory] { memories.filter { $0.matches(search: search) } }

    var body: some View {
        NavigationStack {
            Group {
                if memories.isEmpty {
                    ContentUnavailableView(
                        "No memories yet",
                        systemImage: "sparkles",
                        description: Text("Log your first one from the Log tab — just tap the mic and talk.")
                    )
                } else if !search.isEmpty {
                    List(searchResults) { memory in
                        NavigationLink(value: memory) { MemoryRow(memory: memory) }
                    }
                    .listStyle(.plain)
                    .overlay {
                        if searchResults.isEmpty { ContentUnavailableView.search(text: search) }
                    }
                } else {
                    VStack(spacing: 0) {
                        Picker("View", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.bottom, 8)

                        switch mode {
                        case .timeline: TimelineList(memories: memories)
                        case .calendar: CalendarBrowseView(memories: memories)
                        case .people: PeopleBrowseGrid()
                        case .types: TypesBrowseView(memories: memories)
                        }
                    }
                }
            }
            .navigationTitle("Memories")
            .searchable(text: $search, prompt: "Search stories, people, tags")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { randomMemory = memories.randomElement() } label: {
                        Image(systemName: "dice")
                    }
                    .accessibilityLabel("Random memory")
                    .disabled(memories.isEmpty)
                    Button { showAsk = true } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                    }
                    .accessibilityLabel("Ask your memories")
                    .disabled(memories.isEmpty)
                }
            }
            .navigationDestination(item: $randomMemory) { MemoryDetailView(memory: $0) }
            .sheet(isPresented: $showAsk) { AskVaultView() }
            .vaultDestinations()
        }
    }
}

private struct TimelineList: View {
    let memories: [Memory]

    private var sections: [(title: String, items: [Memory])] {
        var order: [String] = []
        var grouped: [String: [Memory]] = [:]
        for memory in memories {
            let key = memory.memoryDate.sectionTitle
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(memory)
        }
        // Memories arrive sorted newest first; "Undated" sorts last because its sortDate is distantPast.
        return order.map { (title: $0, items: grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            let needsReview = memories.filter { $0.analysisState == .needsReview }
            if !needsReview.isEmpty {
                Section {
                    NavigationLink(value: MemoryFilterRoute(kind: .needsReview)) {
                        Label("\(needsReview.count) memor\(needsReview.count == 1 ? "y needs" : "ies need") people confirmed",
                              systemImage: "person.fill.questionmark")
                            .foregroundStyle(.orange)
                    }
                }
            }
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.items) { memory in
                        NavigationLink(value: memory) { MemoryRow(memory: memory) }
                            .swipeActions(edge: .leading) {
                                Button {
                                    memory.isFavorite.toggle()
                                } label: {
                                    Label("Favorite", systemImage: memory.isFavorite ? "star.slash" : "star")
                                }
                                .tint(.yellow)
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct PeopleBrowseGrid: View {
    @Query(sort: \Person.name) private var people: [Person]

    private var ranked: [Person] {
        people.sorted { $0.memories.count > $1.memories.count }
    }

    var body: some View {
        ScrollView {
            if people.isEmpty {
                ContentUnavailableView("No people yet", systemImage: "person.2",
                                       description: Text("People are added automatically as you log memories."))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 16)], spacing: 20) {
                ForEach(ranked) { person in
                    NavigationLink(value: person) {
                        VStack(spacing: 6) {
                            PersonAvatar(person: person, size: 68)
                            Text(person.displayName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text("\(person.memories.count) \(person.memories.count == 1 ? "memory" : "memories")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

private struct TypesBrowseView: View {
    let memories: [Memory]

    private var categoryCounts: [(id: String, count: Int)] {
        var counts: [String: Int] = [:]
        for memory in memories {
            for id in memory.categories { counts[id, default: 0] += 1 }
        }
        return CategoryCatalog.ordered(counts.keys).map { (id: $0, count: counts[$0] ?? 0) }
    }

    var body: some View {
        List {
            Section {
                let favorites = memories.filter(\.isFavorite).count
                NavigationLink(value: MemoryFilterRoute(kind: .favorites)) {
                    LabeledContent("⭐️ Favorites", value: "\(favorites)")
                }
            }
            Section("Tone") {
                ForEach(Tone.allCases) { tone in
                    let count = memories.filter { $0.tone == tone }.count
                    if count > 0 {
                        NavigationLink(value: MemoryFilterRoute(kind: .tone(tone))) {
                            LabeledContent("\(tone.emoji) \(tone.label)", value: "\(count)")
                        }
                    }
                }
            }
            Section("Type of memory") {
                if categoryCounts.isEmpty {
                    Text("Memories get typed automatically (funny, sad, adventure…) once a Claude key is set.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(categoryCounts, id: \.id) { item in
                    let info = CategoryCatalog.info(for: item.id)
                    NavigationLink(value: MemoryFilterRoute(kind: .category(item.id))) {
                        LabeledContent("\(info.emoji) \(info.label)", value: "\(item.count)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct FilteredMemoriesView: View {
    let route: MemoryFilterRoute
    @Query(sort: \Memory.sortDate, order: .reverse) private var memories: [Memory]

    private var filtered: [Memory] { memories.filter(route.includes) }

    var body: some View {
        List(filtered) { memory in
            NavigationLink(value: memory) { MemoryRow(memory: memory) }
        }
        .listStyle(.plain)
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "tray")
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
