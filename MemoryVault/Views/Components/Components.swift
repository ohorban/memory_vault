import SwiftUI

/// Lays out children left-to-right, wrapping onto new lines (for tag chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct Chip: View {
    let text: String
    var systemImage: String?
    var isSelected = false
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? tint.opacity(0.2) : Color(.secondarySystemBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? tint : .clear, lineWidth: 1))
        .foregroundStyle(isSelected ? tint : .primary)
    }
}

struct PersonAvatar: View {
    let person: Person?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let data = person?.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(color.gradient)
                    Text(person?.initials ?? "?")
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(person?.displayName ?? "Person")
    }

    private var color: Color {
        let palette: [Color] = [.orange, .pink, .purple, .indigo, .blue, .teal, .green, .mint, .brown, .red]
        let key = person?.id.uuidString ?? ""
        let sum = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

/// Overlapping row of small avatars.
struct AvatarStack: View {
    let people: [Person]
    var size: CGFloat = 22
    var limit = 4

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(people.prefix(limit)) { person in
                PersonAvatar(person: person, size: size)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
            }
            if people.count > limit {
                Text("+\(people.count - limit)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, size * 0.4)
            }
        }
    }
}

struct MemoryRow: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(memory.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if memory.isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).imageScale(.small)
                }
                Spacer(minLength: 0)
            }
            Text(memory.memoryDate.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(memory.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                if !memory.people.isEmpty { AvatarStack(people: memory.sortedPeople) }
                Text(memory.categories.prefix(4).map { CategoryCatalog.info(for: $0).emoji }.joined(separator: " "))
                    .font(.caption)
                if memory.analysisState == .needsReview {
                    Label("Confirm people", systemImage: "person.fill.questionmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if !memory.audioFileNames.isEmpty {
                    Image(systemName: "waveform").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

/// A small transient message at the bottom of the screen.
struct Toast: Equatable {
    var message: String
    var isProgress = false
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            if toast.isProgress { ProgressView().controlSize(.small) }
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Navigation targets shared by every tab's NavigationStack.
struct MemoryFilterRoute: Hashable {
    enum Kind: Hashable {
        case category(String)
        case tone(Tone)
        case favorites
        case needsReview
    }

    let kind: Kind

    var title: String {
        switch kind {
        case let .category(id):
            let info = CategoryCatalog.info(for: id)
            return "\(info.emoji) \(info.label)"
        case let .tone(tone): return "\(tone.emoji) \(tone.label)"
        case .favorites: return "⭐️ Favorites"
        case .needsReview: return "Needs confirming"
        }
    }

    func includes(_ memory: Memory) -> Bool {
        switch kind {
        case let .category(id): memory.categories.contains(id)
        case let .tone(tone): memory.tone == tone
        case .favorites: memory.isFavorite
        case .needsReview: memory.analysisState == .needsReview || memory.analysisState == .failed
        }
    }
}

extension View {
    func vaultDestinations() -> some View {
        navigationDestination(for: Memory.self) { MemoryDetailView(memory: $0) }
            .navigationDestination(for: Person.self) { PersonDetailView(person: $0) }
            .navigationDestination(for: MemoryFilterRoute.self) { FilteredMemoriesView(route: $0) }
    }
}

extension TimeInterval {
    var clockText: String {
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
