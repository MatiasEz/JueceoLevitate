import SwiftUI
import JueceoCore

struct BlocksView: View {
    @EnvironmentObject private var store: JudgingStore
    let blocks: [DanceBlock]
    let routines: [Routine]
    let onSelect: (Routine) -> Void

    @State private var searchText = ""
    @State private var selectedFilter: RoutineFilter = .all

    private enum RoutineFilter: String, CaseIterable, Identifiable {
        case all = "Todas"
        case pending = "Pendientes"
        case scored = "Calificadas"
        case favorites = "Mis favoritas"

        var id: String { rawValue }
    }

    private var filteredRoutines: [Routine] {
        routines.filter { routine in
            let matchesSearch: Bool
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let needle = searchText.normalizedKey
                matchesSearch = [routine.id, routine.name, routine.academy, routine.genre, routine.level, routine.division, routine.category]
                    .joined(separator: " ")
                    .normalizedKey
                    .contains(needle)
            }

            let result = store.result(for: routine)
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .favorites:
                matchesFilter = store.hasFavorite(routine)
            case .pending:
                matchesFilter = result.total == 0
            case .scored:
                matchesFilter = result.total > 0
            }
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterTabs

            ScrollView {
                LazyVStack(spacing: 12) {
                    if filteredRoutines.isEmpty {
                        ContentUnavailableView(
                            "Sin coreografías",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Cambia la búsqueda o el filtro seleccionado.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 420)
                    } else {
                        ForEach(filteredRoutines) { routine in
                            RoutineListRow(
                                routine: routine,
                                status: status(for: routine),
                                isActive: routine.id == store.selectedRoutineID,
                                onSelect: { onSelect(routine) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 28)
            }
        }
        .foregroundStyle(LevitTheme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LevitTheme.paper.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Coreografías del \(blocks.first?.name.lowercased() ?? "bloque")")
                    .font(.title2.weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                Text("\(filteredRoutines.count) de \(routines.count) visibles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LevitTheme.muted)
                TextField("Buscar coreografía", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .foregroundStyle(LevitTheme.ink)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(width: 300, height: 44)
            .background(LevitTheme.solidSurface, in: Capsule())
            .overlay(Capsule().stroke(LevitTheme.line))

            Button {} label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(LevitTheme.muted)
                    .background(LevitTheme.solidSurface, in: Circle())
                    .overlay(Circle().stroke(LevitTheme.line))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var filterTabs: some View {
        HStack(spacing: 24) {
            ForEach(RoutineFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    VStack(spacing: 7) {
                        Text(filter.rawValue)
                            .font(.callout.weight(.bold))
                            .foregroundStyle(selectedFilter == filter ? LevitTheme.pink : LevitTheme.muted)
                        Capsule()
                            .fill(selectedFilter == filter ? LevitTheme.pink : .clear)
                            .frame(width: 34, height: 3)
                    }
                    .frame(minWidth: 86)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 14)
    }

    private func status(for routine: Routine) -> RoutineStatus {
        if routine.id == store.selectedRoutineID {
            return .judging
        }
        return store.result(for: routine).total > 0 ? .scored : .pending
    }
}

private enum RoutineStatus {
    case scored
    case judging
    case pending

    var title: String {
        switch self {
        case .scored: "Calificada"
        case .judging: "En jueceo"
        case .pending: "Pendiente"
        }
    }

    var icon: String {
        switch self {
        case .scored: "checkmark.circle.fill"
        case .judging: "chart.bar.fill"
        case .pending: "clock"
        }
    }

    var color: Color {
        switch self {
        case .scored: .green
        case .judging: LevitTheme.pink
        case .pending: LevitTheme.muted
        }
    }
}

private struct RoutineListRow: View {
    let routine: Routine
    let status: RoutineStatus
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 18) {
                Text("#\(routine.id)")
                    .font(.headline.weight(.black))
                    .foregroundStyle(isActive ? LevitTheme.pink : LevitTheme.ink)
                    .frame(width: 62, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(routine.name)
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                        .lineLimit(1)
                    Text(routine.academy)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        LevitTag(routine.division)
                        if let level = routine.levelTagText {
                            LevitTag(level)
                        }
                        LevitTag(routine.category)
                        LevitTag(routine.genre)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: status.icon)
                    Text(status.title)
                        .font(.callout.weight(.bold))
                }
                .foregroundStyle(status.color)
                .frame(width: 128, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted.opacity(0.7))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(isActive ? LevitTheme.palePink : LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isActive ? LevitTheme.pink.opacity(0.18) : LevitTheme.line)
            )
            .shadow(color: .black.opacity(isActive ? 0.06 : 0.025), radius: 16, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}
