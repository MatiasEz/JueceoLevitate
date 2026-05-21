import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var store: JudgingStore

    private var favorites: [FavoriteSelectionSummary] {
        store.favoriteSummaries
    }

    private var rankingBlocks: [FavoriteRankingBlock] {
        store.favoriteRankingBlocks
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
        if rankingBlocks.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(rankingBlocks) { block in
                    FavoriteRankingBlockSection(block: block)
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
                Text("Todavía no hay favoritos")
                    .font(.headline.weight(.black))
                Text("Cuando los jueces marquen vestuario, coreografía o música, el top 3 va a aparecer acá.")
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

private struct FavoriteRankingBlockSection: View {
    let block: FavoriteRankingBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 38, height: 38)
                    .background(LevitTheme.palePink, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.blockName)
                        .font(.title3.weight(.black))
                    Text("\(block.totalVotes) voto\(block.totalVotes == 1 ? "" : "s")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LevitTheme.muted)
                }

                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach(block.categories) { category in
                    FavoriteRankingCategoryCard(ranking: category)
                }
            }
        }
        .padding(20)
        .background(LevitTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(LevitTheme.cardStroke))
        .shadow(color: .black.opacity(0.045), radius: 22, x: 0, y: 12)
    }
}

private struct FavoriteRankingCategoryCard: View {
    let ranking: FavoriteCategoryRanking

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: ranking.category.systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LevitTheme.pink)
                    .frame(width: 32, height: 32)
                    .background(LevitTheme.palePink, in: Circle())
                Text(ranking.category.title)
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                Spacer()
                Text("Top 3")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LevitTheme.muted)
            }

            if ranking.items.isEmpty {
                Text("Sin votos")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
                    .background(LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 8) {
                    ForEach(ranking.items) { item in
                        FavoriteRankingRow(item: item)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(LevitTheme.solidSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LevitTheme.line))
    }
}

private struct FavoriteRankingRow: View {
    let item: FavoriteRankingItem

    var body: some View {
        HStack(spacing: 12) {
            Text("\(item.rank)")
                .font(.headline.weight(.black))
                .foregroundStyle(item.rank == 1 ? .white : LevitTheme.pink)
                .frame(width: 34, height: 34)
                .background(item.rank == 1 ? LevitTheme.pink : LevitTheme.palePink, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.routine.academy.isEmpty ? item.routine.name : item.routine.academy)
                    .font(.callout.weight(.black))
                    .foregroundStyle(LevitTheme.ink)
                    .lineLimit(1)
                Text("#\(item.routine.id) \(item.routine.name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LevitTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(item.votes)")
                .font(.headline.monospacedDigit().weight(.black))
                .foregroundStyle(LevitTheme.ink)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(12)
        .background(item.rank == 1 ? LevitTheme.palePink.opacity(0.72) : LevitTheme.softFill, in: RoundedRectangle(cornerRadius: 14))
    }
}
