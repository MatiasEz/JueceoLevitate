import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var store: JudgingStore

    private var favorites: [FavoriteSelectionSummary] {
        store.favoriteSummaries
    }

    private var groupedFavorites: [(category: FavoriteCategory, favorites: [FavoriteSelectionSummary])] {
        FavoriteCategory.allCases.compactMap { category in
            let items = favorites.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                summaryGrid
                favoritesContent
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(maxWidth: 1240, alignment: .leading)
        }
        .background(LevitTheme.paper.ignoresSafeArea())
        .foregroundStyle(LevitTheme.ink)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Favoritos")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(LevitTheme.ink)
                Text(store.selectedBlock?.name ?? "Todos los bloques")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 18) {
                EventPill()
                BlockPill()
                SyncPill(status: store.syncStatus, pendingCount: store.pendingSyncCount)
            }
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            FavoriteMetricCard(
                icon: "star.fill",
                value: "\(favorites.count)",
                label: "Total",
                detail: store.pendingSyncCount == 0 ? "Sin pendientes" : "\(store.pendingSyncCount) por subir"
            )

            ForEach(FavoriteCategory.allCases) { category in
                FavoriteMetricCard(
                    icon: category.systemImage,
                    value: "\(favorites.filter { $0.category == category }.count)",
                    label: category.title,
                    detail: "Favoritos marcados"
                )
            }
        }
    }

    @ViewBuilder
    private var favoritesContent: some View {
        if favorites.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groupedFavorites, id: \.category) { group in
                    FavoriteCategorySection(category: group.category, favorites: group.favorites)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "star.slash")
                .font(.title3.weight(.bold))
                .foregroundStyle(LevitTheme.muted)
                .frame(width: 48, height: 48)
                .background(LevitTheme.softFill, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Todavia no hay favoritos")
                    .font(.headline.weight(.black))
                Text("Cuando un juez marque vestuario, coreografia o musica, va a aparecer aca.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(LevitTheme.cardStroke))
        .shadow(color: .black.opacity(0.045), radius: 22, x: 0, y: 12)
    }
}

private struct FavoriteMetricCard: View {
    let icon: String
    let value: String
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 36, height: 36)
                    .background(LevitTheme.palePink, in: Circle())
                Text(value)
                    .font(.title2.monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LevitTheme.muted)
                Text(detail)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.cardStroke))
    }
}

private struct FavoriteCategorySection: View {
    let category: FavoriteCategory
    let favorites: [FavoriteSelectionSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: category.systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 38, height: 38)
                    .background(LevitTheme.palePink, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.title3.weight(.black))
                    Text("\(favorites.count) seleccion\(favorites.count == 1 ? "" : "es")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }

                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 12)], spacing: 12) {
                ForEach(favorites) { favorite in
                    FavoriteSummaryCard(favorite: favorite)
                }
            }
        }
        .padding(20)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(LevitTheme.cardStroke))
        .shadow(color: .black.opacity(0.045), radius: 22, x: 0, y: 12)
    }
}

private struct FavoriteSummaryCard: View {
    let favorite: FavoriteSelectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Text("#\(favorite.routine.id)")
                    .font(.callout.monospacedDigit().weight(.black))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 58, height: 42)
                    .background(LevitTheme.palePink, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(favorite.routine.name)
                        .font(.headline.weight(.black))
                        .foregroundStyle(LevitTheme.ink)
                        .lineLimit(1)
                    Text(favorite.routine.academy)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                        .lineLimit(1)
                }

                Spacer()
            }

            Divider().overlay(LevitTheme.line)

            HStack(spacing: 9) {
                FavoriteChip(icon: "person.fill", text: favorite.judge)
                FavoriteChip(icon: "square.stack.3d.up.fill", text: favorite.blockName)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }
}

private struct FavoriteChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.black))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(LevitTheme.pink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(LevitTheme.palePink, in: Capsule())
    }
}
