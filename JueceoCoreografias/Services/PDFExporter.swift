import Foundation
import JueceoCore
import UIKit

enum PDFExporter {
    static func export(
        results: [RoutineResult],
        judges: [String],
        sourceName: String,
        title: String = "Calificaciones y dictamen final",
        templateForRoutine: (Routine) -> JudgingTemplate,
        scoreForCriterion: (Routine, String, Criterion) -> Double,
        penaltyForRoutine: (Routine, String) -> Double
    ) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename(for: title))
            .appendingPathExtension("pdf")

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Jueceo Coreografías",
            kCGPDFContextTitle as String: title
        ]

        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        let margin: CGFloat = 24
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let groups = groupedResults(results)
        let placementsByRoutineID = dictamenPlacements(from: results)

        do {
            try renderer.writePDF(to: url) { context in
                var didStartPage = false

                for group in groups {
                    let template = templateForRoutine(group.results.first?.routine ?? results.first?.routine ?? placeholderRoutine)
                    let criteria = template.criteria.sorted { $0.id < $1.id }
                    var y = margin

                    context.beginPage()
                    didStartPage = true
                    y = drawPageHeader(title: title, sourceName: sourceName, groupTitle: group.title, y: y, margin: margin, page: page)
                    y = drawTableHeader(criteria: criteria, y: y, margin: margin, page: page)

                    for (routineIndex, result) in group.results.enumerated() {
                        let rowCount = max(judges.count, 1)
                        let neededHeight = CGFloat(rowCount) * Layout.rowHeight
                        if y + neededHeight > page.height - margin {
                            context.beginPage()
                            y = margin
                            y = drawPageHeader(title: title, sourceName: sourceName, groupTitle: "\(group.title) - continuacion", y: y, margin: margin, page: page)
                            y = drawTableHeader(criteria: criteria, y: y, margin: margin, page: page)
                        }

                        let fill = routineIndex.isMultiple(of: 2) ? Theme.paleYellow : .white
                        drawRoutineRows(
                            result: result,
                            placement: placementsByRoutineID[result.routine.id] ?? .position(routineIndex + 1),
                            y: y,
                            judges: judges,
                            criteria: criteria,
                            fill: fill,
                            page: page,
                            margin: margin,
                            scoreForCriterion: scoreForCriterion,
                            penaltyForRoutine: penaltyForRoutine
                        )
                        y += neededHeight
                    }
                }

                if !didStartPage {
                    context.beginPage()
                    _ = drawPageHeader(title: title, sourceName: sourceName, groupTitle: "Sin resultados", y: margin, margin: margin, page: page)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    static func exportDictamen(
        results: [RoutineResult],
        sourceName: String,
        title: String = "Dictamen final",
        specialAwards: [SpecialAwardSummary] = []
    ) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename(for: title))
            .appendingPathExtension("pdf")

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Jueceo Coreografías",
            kCGPDFContextTitle as String: title
        ]

        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        let margin: CGFloat = 24
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let sections = DictamenBuilder.sections(from: results)

        do {
            try renderer.writePDF(to: url) { context in
                var didStartPage = false
                var y = margin

                for section in sections {
                    y = margin
                    context.beginPage()
                    didStartPage = true
                    y = drawDictamenTitle(sectionTitle: section.genre, y: y, margin: margin, page: page)
                    y += 14

                    for category in section.categories {
                        let neededHeight = DictamenPDFLayout.categoryCardHeight(rowCount: category.rows.count)
                        if y + neededHeight > page.height - margin {
                            context.beginPage()
                            y = margin
                            y = drawDictamenTitle(sectionTitle: section.genre, y: y, margin: margin, page: page)
                            y += 14
                        }

                        y = drawDictamenCategoryCard(category, y: y, margin: margin, page: page)
                    }
                }

                if !specialAwards.isEmpty {
                    if !didStartPage {
                        context.beginPage()
                        didStartPage = true
                        y = drawDictamenTitle(sectionTitle: clean(sourceName, fallback: "SIN DICTAMEN"), y: margin, margin: margin, page: page)
                        y += 14
                    }

                    let neededHeight = DictamenPDFLayout.specialAwardsHeight(rowCount: specialAwards.count)
                    if y + neededHeight > page.height - margin {
                        context.beginPage()
                        y = drawDictamenTitle(sectionTitle: clean(sourceName, fallback: "SIN DICTAMEN"), y: margin, margin: margin, page: page)
                        y += 14
                    }
                    _ = drawDictamenSpecialAwardsCard(specialAwards, y: y, margin: margin, page: page)
                }

                if !didStartPage {
                    context.beginPage()
                    _ = drawDictamenTitle(sectionTitle: clean(sourceName, fallback: "SIN DICTAMEN"), y: margin, margin: margin, page: page)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    static func exportCompleteBlockRanking(
        sections: [(block: DanceBlock, results: [RoutineResult])],
        title: String = "Ranking de puntaje total por bloque"
    ) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ranking_por_bloque_completo")
            .appendingPathExtension("pdf")

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Jueceo Coreografías",
            kCGPDFContextTitle as String: title
        ]

        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        let margin: CGFloat = 38
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let topRows = completeRankingTopRows(from: sections)

        do {
            try renderer.writePDF(to: url) { context in
                var pageNumber = 0

                func finishPage() {
                    guard pageNumber > 0 else { return }
                    drawCompleteRankingFooter(pageNumber: pageNumber, page: page, margin: margin)
                }

                func beginRankingPage(sectionTitle: String, detail: String) -> CGFloat {
                    finishPage()
                    context.beginPage()
                    pageNumber += 1

                    var y = margin
                    y = drawCompleteRankingHeader(title: title, y: y, margin: margin, page: page)
                    y += 18
                    y = drawCompleteRankingSectionHeader(title: sectionTitle, detail: detail, y: y, margin: margin, page: page)
                    y += 10
                    return drawCompleteRankingTableHeader(y: y, margin: margin)
                }

                for section in sections {
                    let blockName = clean(section.block.name, fallback: clean(section.block.title, fallback: "Bloque"))
                    var y = beginRankingPage(
                        sectionTitle: blockName,
                        detail: "\(section.results.filter { $0.aggregateTotal > 0 }.count) coreografías con puntaje"
                    )

                    for (index, result) in section.results.enumerated() {
                        if y + CompleteRankingPDFLayout.rowHeight > page.height - margin - CompleteRankingPDFLayout.footerReservedHeight {
                            y = beginRankingPage(
                                sectionTitle: "\(blockName) - continuación",
                                detail: "\(section.results.filter { $0.aggregateTotal > 0 }.count) coreografías con puntaje"
                            )
                        }

                        drawCompleteRankingRow(
                            result: result,
                            y: y,
                            margin: margin,
                            rowIndex: index,
                            isTopRow: index == 0 && result.aggregateTotal > 0
                        )
                        y += CompleteRankingPDFLayout.rowHeight
                    }
                }

                var topY = beginRankingPage(sectionTitle: "TOP 15", detail: "15 coreografías con puntaje")
                topY = drawCompleteRankingTopHeader(y: topY - CompleteRankingPDFLayout.tableHeaderHeight, margin: margin)
                for (index, row) in topRows.enumerated() {
                    if topY + CompleteRankingPDFLayout.rowHeight > page.height - margin - CompleteRankingPDFLayout.footerReservedHeight {
                        topY = beginRankingPage(sectionTitle: "TOP 15 - continuación", detail: "15 coreografías con puntaje")
                        topY = drawCompleteRankingTopHeader(y: topY - CompleteRankingPDFLayout.tableHeaderHeight, margin: margin)
                    }

                    drawCompleteRankingTopRow(row, position: index + 1, y: topY, margin: margin, rowIndex: index)
                    topY += CompleteRankingPDFLayout.rowHeight
                }

                if sections.isEmpty && topRows.isEmpty {
                    _ = beginRankingPage(sectionTitle: "Sin resultados", detail: "0 coreografías con puntaje")
                }

                finishPage()
            }
            return url
        } catch {
            return nil
        }
    }

    private static func dictamenPlacements(from results: [RoutineResult]) -> [String: CompetitionPlacement] {
        var placements: [String: CompetitionPlacement] = [:]
        for section in DictamenBuilder.sections(from: results) {
            for category in section.categories {
                for row in category.rows {
                    placements[row.result.routine.id] = row.placement
                }
            }
        }
        return placements
    }

    private static func completeRankingTopRows(from sections: [(block: DanceBlock, results: [RoutineResult])]) -> [CompleteRankingRow] {
        sections
            .flatMap { section in
                section.results
                    .filter { $0.aggregateTotal > 0 }
                    .map { CompleteRankingRow(blockName: section.block.name, result: $0) }
            }
            .sorted(by: completeRankingOrder)
            .prefix(15)
            .map { $0 }
    }

    private static func completeRankingOrder(_ lhs: CompleteRankingRow, _ rhs: CompleteRankingRow) -> Bool {
        if abs(lhs.result.aggregateTotal - rhs.result.aggregateTotal) < 0.0001 {
            return completeRankingRoutineOrder(lhs.result.routine, rhs.result.routine)
        }
        return lhs.result.aggregateTotal > rhs.result.aggregateTotal
    }

    private static func completeRankingRoutineOrder(_ lhs: Routine, _ rhs: Routine) -> Bool {
        let lhsNumber = Int(lhs.id) ?? Int.max
        let rhsNumber = Int(rhs.id) ?? Int.max
        if lhsNumber == rhsNumber {
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
        return lhsNumber < rhsNumber
    }

    private static func drawCompleteRankingHeader(title: String, y: CGFloat, margin: CGFloat, page: CGRect) -> CGFloat {
        let logoRect = CGRect(x: margin, y: y, width: 166, height: CompleteRankingPDFLayout.logoHeight)
        drawCompleteRankingLogo(in: logoRect)

        drawText(
            title,
            in: CGRect(x: logoRect.maxX + 12, y: y + 13, width: page.width - logoRect.maxX - margin - 12, height: 30),
            size: 25,
            weight: .bold,
            color: CompleteRankingTheme.ink,
            alignment: .left
        )
        return y + CompleteRankingPDFLayout.logoHeight
    }

    private static func drawCompleteRankingLogo(in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(CompleteRankingTheme.primary.cgColor)
        context.fill(rect)

        guard let image = UIImage(named: AppBrand.competition.logoAssetName) else {
            drawText(
                AppBrand.competition.displayName,
                in: rect.insetBy(dx: 14, dy: 17),
                size: 22,
                weight: .bold,
                color: .white,
                alignment: .center
            )
            return
        }

        let imageRect = aspectFitRect(for: image.size, in: rect.insetBy(dx: 14, dy: 9))
        image.draw(in: imageRect)
    }

    private static func drawCompleteRankingSectionHeader(title: String, detail: String, y: CGFloat, margin: CGFloat, page: CGRect) -> CGFloat {
        let rect = CGRect(x: margin, y: y, width: page.width - margin * 2, height: CompleteRankingPDFLayout.sectionHeight)
        drawRankingRect(rect, fill: CompleteRankingTheme.palePink, stroke: CompleteRankingTheme.pinkStroke)
        drawText(
            title.uppercased(),
            in: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width * 0.52, height: 18),
            size: 18,
            weight: .bold,
            color: CompleteRankingTheme.ink,
            alignment: .left
        )
        drawText(
            detail,
            in: CGRect(x: rect.midX, y: rect.minY + 13, width: rect.width * 0.42, height: 14),
            size: 9.5,
            weight: .bold,
            color: CompleteRankingTheme.muted,
            alignment: .center
        )
        return rect.maxY
    }

    private static func drawCompleteRankingTableHeader(y: CGFloat, margin: CGFloat) -> CGFloat {
        let columns = CompleteRankingPDFLayout.columns(margin: margin)
        drawCompleteRankingHeaderCell("N° COREO", x: columns.numberX, y: y, width: columns.numberWidth, alignment: .center)
        drawCompleteRankingHeaderCell("COREO", x: columns.choreographyX, y: y, width: columns.choreographyWidth, alignment: .left)
        drawCompleteRankingHeaderCell("ACADEMIA", x: columns.academyX, y: y, width: columns.academyWidth, alignment: .left)
        drawCompleteRankingHeaderCell("PUNTAJE", x: columns.scoreX, y: y, width: columns.scoreWidth, alignment: .right)
        return y + CompleteRankingPDFLayout.tableHeaderHeight
    }

    private static func drawCompleteRankingTopHeader(y: CGFloat, margin: CGFloat) -> CGFloat {
        let columns = CompleteRankingPDFLayout.topColumns(margin: margin)
        drawCompleteRankingHeaderCell("POS.", x: columns.positionX, y: y, width: columns.positionWidth, alignment: .center)
        drawCompleteRankingHeaderCell("N° COREO", x: columns.numberX, y: y, width: columns.numberWidth, alignment: .center)
        drawCompleteRankingHeaderCell("COREO", x: columns.choreographyX, y: y, width: columns.choreographyWidth, alignment: .left)
        drawCompleteRankingHeaderCell("ACADEMIA", x: columns.academyX, y: y, width: columns.academyWidth, alignment: .left)
        drawCompleteRankingHeaderCell("BLOQUE", x: columns.blockX, y: y, width: columns.blockWidth, alignment: .left)
        drawCompleteRankingHeaderCell("PUNTAJE", x: columns.scoreX, y: y, width: columns.scoreWidth, alignment: .right)
        return y + CompleteRankingPDFLayout.tableHeaderHeight
    }

    private static func drawCompleteRankingHeaderCell(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, alignment: NSTextAlignment) {
        drawRankingCell(
            rect: CGRect(x: x, y: y, width: width, height: CompleteRankingPDFLayout.tableHeaderHeight),
            text: text,
            fill: CompleteRankingTheme.primary,
            fontSize: 8.6,
            weight: .bold,
            color: .white,
            alignment: alignment,
            padding: 8
        )
    }

    private static func drawCompleteRankingRow(
        result: RoutineResult,
        y: CGFloat,
        margin: CGFloat,
        rowIndex: Int,
        isTopRow: Bool
    ) {
        let columns = CompleteRankingPDFLayout.columns(margin: margin)
        let fill = isTopRow ? CompleteRankingTheme.palePink : (rowIndex.isMultiple(of: 2) ? .white : CompleteRankingTheme.alternateRow)
        let routine = result.routine
        drawRankingCell(rect: CGRect(x: columns.numberX, y: y, width: columns.numberWidth, height: CompleteRankingPDFLayout.rowHeight), text: routine.id, fill: fill, fontSize: 8.4, color: CompleteRankingTheme.ink)
        drawRankingCell(rect: CGRect(x: columns.choreographyX, y: y, width: columns.choreographyWidth, height: CompleteRankingPDFLayout.rowHeight), text: titleCase(routine.name), fill: fill, fontSize: 8.2, weight: .bold, color: CompleteRankingTheme.ink, alignment: .left, padding: 8)
        drawRankingCell(rect: CGRect(x: columns.academyX, y: y, width: columns.academyWidth, height: CompleteRankingPDFLayout.rowHeight), text: routine.academy.uppercased(), fill: fill, fontSize: 8.2, color: CompleteRankingTheme.ink, alignment: .left, padding: 8)
        drawRankingCell(rect: CGRect(x: columns.scoreX, y: y, width: columns.scoreWidth, height: CompleteRankingPDFLayout.rowHeight), text: completeRankingScoreText(result.aggregateTotal), fill: fill, fontSize: 9.4, weight: .bold, color: CompleteRankingTheme.ink, alignment: .right, padding: 8)
    }

    private static func drawCompleteRankingTopRow(
        _ row: CompleteRankingRow,
        position: Int,
        y: CGFloat,
        margin: CGFloat,
        rowIndex: Int
    ) {
        let columns = CompleteRankingPDFLayout.topColumns(margin: margin)
        let fill = position == 1 ? CompleteRankingTheme.palePink : (rowIndex.isMultiple(of: 2) ? .white : CompleteRankingTheme.alternateRow)
        let routine = row.result.routine
        drawRankingCell(rect: CGRect(x: columns.positionX, y: y, width: columns.positionWidth, height: CompleteRankingPDFLayout.rowHeight), text: "\(position)", fill: fill, fontSize: 8.4, weight: .bold, color: position <= 3 ? CompleteRankingTheme.primary : CompleteRankingTheme.ink)
        drawRankingCell(rect: CGRect(x: columns.numberX, y: y, width: columns.numberWidth, height: CompleteRankingPDFLayout.rowHeight), text: routine.id, fill: fill, fontSize: 8.4, color: CompleteRankingTheme.ink)
        drawRankingCell(rect: CGRect(x: columns.choreographyX, y: y, width: columns.choreographyWidth, height: CompleteRankingPDFLayout.rowHeight), text: titleCase(routine.name), fill: fill, fontSize: 8.2, weight: .bold, color: CompleteRankingTheme.ink, alignment: .left, padding: 8)
        drawRankingCell(rect: CGRect(x: columns.academyX, y: y, width: columns.academyWidth, height: CompleteRankingPDFLayout.rowHeight), text: routine.academy.uppercased(), fill: fill, fontSize: 8.2, color: CompleteRankingTheme.ink, alignment: .left, padding: 8)
        drawRankingCell(rect: CGRect(x: columns.blockX, y: y, width: columns.blockWidth, height: CompleteRankingPDFLayout.rowHeight), text: row.blockName.uppercased(), fill: fill, fontSize: 8.2, color: CompleteRankingTheme.ink, alignment: .left, padding: 8)
        drawRankingCell(rect: CGRect(x: columns.scoreX, y: y, width: columns.scoreWidth, height: CompleteRankingPDFLayout.rowHeight), text: completeRankingScoreText(row.result.aggregateTotal), fill: fill, fontSize: 9.4, weight: .bold, color: CompleteRankingTheme.ink, alignment: .right, padding: 8)
    }

    private static func drawCompleteRankingFooter(pageNumber: Int, page: CGRect, margin: CGFloat) {
        drawText(
            "\(AppBrand.competition.displayName) · Ranking de puntaje total",
            in: CGRect(x: margin, y: page.height - 20, width: page.width * 0.42, height: 10),
            size: 7.5,
            weight: .bold,
            color: CompleteRankingTheme.muted,
            alignment: .left
        )
        drawText(
            "Página \(pageNumber)",
            in: CGRect(x: page.width - margin - 90, y: page.height - 20, width: 90, height: 10),
            size: 7.5,
            weight: .bold,
            color: CompleteRankingTheme.muted,
            alignment: .right
        )
    }

    private static func drawRankingCell(
        rect: CGRect,
        text: String,
        fill: UIColor,
        fontSize: CGFloat,
        weight: UIFont.Weight = .regular,
        color: UIColor = .black,
        alignment: NSTextAlignment = .center,
        padding: CGFloat = 4
    ) {
        drawRankingRect(rect, fill: fill, stroke: CompleteRankingTheme.line)
        drawText(text, in: rect.insetBy(dx: padding, dy: 5), size: fontSize, weight: weight, color: color, alignment: alignment)
    }

    private static func drawRankingRect(_ rect: CGRect, fill: UIColor, stroke: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(fill.cgColor)
        context.fill(rect)
        context.setStrokeColor(stroke.cgColor)
        context.setLineWidth(0.45)
        context.stroke(rect)
    }

    private static func completeRankingScoreText(_ value: Double) -> String {
        value > 0 ? value.formatted(.number.precision(.fractionLength(0))) : "-"
    }

    private static func aspectFitRect(for imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    private static func groupedResults(_ results: [RoutineResult]) -> [(title: String, results: [RoutineResult])] {
        let grouped = Dictionary(grouping: results) { result in
            clean(result.routine.genre, fallback: "SIN GÉNERO")
        }

        return grouped
            .map { title, items in
                (
                    title,
                    items.sorted {
                        if $0.total == $1.total {
                            return (Int($0.routine.id) ?? Int.max) < (Int($1.routine.id) ?? Int.max)
                        }
                        return $0.total > $1.total
                    }
                )
            }
            .sorted { lhs, rhs in lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
    }

    private static func drawPageHeader(title: String, sourceName: String, groupTitle: String, y: CGFloat, margin: CGFloat, page: CGRect) -> CGFloat {
        let fullWidth = page.width - margin * 2
        let headerTitle = clean(sourceName, fallback: "")
        let displayedTitle = headerTitle.isEmpty ? groupTitle : "\(headerTitle) - \(groupTitle)"
        drawCell(
            rect: CGRect(x: margin, y: y, width: fullWidth, height: 30),
            text: displayedTitle.uppercased(),
            fill: .white,
            fontSize: 22,
            weight: .bold
        )

        let metaY = y + 32
        drawText(title, in: CGRect(x: margin, y: metaY, width: fullWidth * 0.58, height: 16), size: 9.5, color: .darkGray)
        drawText(sourceName, in: CGRect(x: page.midX, y: metaY, width: page.midX - margin, height: 16), size: 9.5, color: .darkGray, alignment: .right)
        return metaY + 24
    }

    private static func drawTableHeader(criteria: [Criterion], y: CGFloat, margin: CGFloat, page: CGRect) -> CGFloat {
        let metrics = Layout.metrics(criteriaCount: criteria.count, pageWidth: page.width, margin: margin)
        var x = margin

        drawCell(rect: CGRect(x: x, y: y, width: metrics.numberWidth, height: Layout.headerHeight), text: "#", fill: Theme.headerFill, fontSize: 8, weight: .bold)
        x += metrics.numberWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.routineWidth, height: Layout.headerHeight), text: "COREOGRAFÍA", fill: Theme.headerFill, fontSize: 8, weight: .bold)
        x += metrics.routineWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.judgeWidth, height: Layout.headerHeight), text: "JUEZ", fill: Theme.headerFill, fontSize: 8, weight: .bold)
        x += metrics.judgeWidth

        let sections = sectionSpans(for: criteria)
        for span in sections {
            let sectionX = x + CGFloat(span.start) * metrics.criterionWidth
            let sectionWidth = CGFloat(span.count) * metrics.criterionWidth
            drawCell(
                rect: CGRect(x: sectionX, y: y, width: sectionWidth, height: Layout.sectionHeight),
                text: span.title.uppercased(),
                fill: .white,
                fontSize: 8.2,
                weight: .bold
            )
        }

        let idY = y + Layout.sectionHeight
        let labelY = idY + Layout.idHeight
        let maxY = labelY + Layout.labelHeight
        for (index, criterion) in criteria.enumerated() {
            let criterionX = x + CGFloat(index) * metrics.criterionWidth
            drawCell(
                rect: CGRect(x: criterionX, y: idY, width: metrics.criterionWidth, height: Layout.idHeight),
                text: "\(criterion.id)",
                fill: Theme.headerFill,
                fontSize: 7.5,
                weight: .bold
            )
            drawCell(
                rect: CGRect(x: criterionX, y: labelY, width: metrics.criterionWidth, height: Layout.labelHeight),
                text: criterion.label,
                fill: .white,
                fontSize: 5.2,
                weight: .regular,
                alignment: .center,
                padding: 2
            )
            drawCell(
                rect: CGRect(x: criterionX, y: maxY, width: metrics.criterionWidth, height: Layout.maxHeight),
                text: criterion.maxScore.formatted(.number.precision(.fractionLength(0...1))),
                fill: Theme.headerFill,
                fontSize: 7,
                weight: .bold
            )
        }

        x += CGFloat(criteria.count) * metrics.criterionWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.totalWidth, height: Layout.headerHeight), text: "TOTAL", fill: Theme.headerFill, fontSize: 7.4, weight: .bold)
        x += metrics.totalWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.averageWidth, height: Layout.headerHeight), text: "PROM.", fill: Theme.headerFill, fontSize: 7.4, weight: .bold)
        x += metrics.averageWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.placeWidth, height: Layout.headerHeight), text: "LUGAR", fill: Theme.headerFill, fontSize: 7.4, weight: .bold)

        return y + Layout.headerHeight
    }

    private static func drawRoutineRows(
        result: RoutineResult,
        placement: CompetitionPlacement,
        y: CGFloat,
        judges: [String],
        criteria: [Criterion],
        fill: UIColor,
        page: CGRect,
        margin: CGFloat,
        scoreForCriterion: (Routine, String, Criterion) -> Double,
        penaltyForRoutine: (Routine, String) -> Double
    ) {
        let metrics = Layout.metrics(criteriaCount: criteria.count, pageWidth: page.width, margin: margin)
        let rowJudges = judges.isEmpty ? ["-"] : judges

        for (judgeIndex, judge) in rowJudges.enumerated() {
            let rowY = y + CGFloat(judgeIndex) * Layout.rowHeight
            var x = margin
            let isFirstJudge = judgeIndex == 0
            let subtotal = criteria.reduce(0) { sum, criterion in
                sum + scoreForCriterion(result.routine, judge, criterion)
            }
            let judgeTotal = subtotal > 0 ? max(0, subtotal + penaltyForRoutine(result.routine, judge)) : 0

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.numberWidth, height: Layout.rowHeight),
                text: isFirstJudge ? result.routine.id : "",
                fill: fill,
                fontSize: 7.6,
                weight: isFirstJudge ? .bold : .regular
            )
            x += metrics.numberWidth

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.routineWidth, height: Layout.rowHeight),
                text: isFirstJudge ? titleCase(result.routine.name) : "",
                fill: fill,
                fontSize: 7,
                weight: isFirstJudge ? .semibold : .regular,
                alignment: .left
            )
            x += metrics.routineWidth

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.judgeWidth, height: Layout.rowHeight),
                text: judge,
                fill: fill,
                fontSize: 7,
                weight: .semibold
            )
            x += metrics.judgeWidth

            for criterion in criteria {
                let score = scoreForCriterion(result.routine, judge, criterion)
                drawCell(
                    rect: CGRect(x: x, y: rowY, width: metrics.criterionWidth, height: Layout.rowHeight),
                    text: score > 0 ? score.formatted(.number.precision(.fractionLength(0...1))) : "",
                    fill: fill,
                    fontSize: 7.2
                )
                x += metrics.criterionWidth
            }

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.totalWidth, height: Layout.rowHeight),
                text: judgeTotal > 0 ? judgeTotal.formatted(.number.precision(.fractionLength(0...1))) : "",
                fill: fill,
                fontSize: 7.3,
                weight: .bold
            )
            x += metrics.totalWidth

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.averageWidth, height: Layout.rowHeight),
                text: isFirstJudge && result.total > 0 ? result.total.formatted(.number.precision(.fractionLength(1...2))) : "",
                fill: fill,
                fontSize: 7.3,
                weight: .bold
            )
            x += metrics.averageWidth

            drawCell(
                rect: CGRect(x: x, y: rowY, width: metrics.placeWidth, height: Layout.rowHeight),
                text: isFirstJudge && result.total > 0 ? placement.shortLabel : "",
                fill: fill,
                fontSize: placement.isParticipation ? 5.7 : 7.3,
                weight: .bold
            )
        }
    }

    private static func drawDictamenTitle(sectionTitle: String, y: CGFloat, margin: CGFloat, page: CGRect) -> CGFloat {
        drawDictamenCell(
            rect: CGRect(x: margin, y: y, width: page.width - margin * 2, height: DictamenPDFLayout.titleHeight),
            text: "GENERO \(sectionTitle.uppercased())",
            fill: Theme.dictamenTitleFill,
            fontSize: 22,
            weight: .bold,
            color: .white
        )
        if let context = UIGraphicsGetCurrentContext() {
            context.setFillColor(Theme.dictamenAccent.cgColor)
            context.fill(CGRect(x: margin, y: y, width: 6, height: DictamenPDFLayout.titleHeight))
        }
        return y + DictamenPDFLayout.titleHeight
    }

    private static func drawDictamenCategoryCard(_ category: DictamenCategorySection, y: CGFloat, margin: CGFloat, page: CGRect) -> CGFloat {
        guard UIGraphicsGetCurrentContext() != nil else { return y }

        let cardWidth = page.width - margin * 2
        let cardHeight = DictamenPDFLayout.categoryCardHeight(rowCount: category.rows.count) - DictamenPDFLayout.categorySpacing
        let cardRect = CGRect(x: margin, y: y, width: cardWidth, height: cardHeight)
        drawRoundedRect(cardRect, radius: 10, fill: .white, stroke: Theme.dictamenSoftStroke)

        let contentX = cardRect.minX + DictamenPDFLayout.cardInset
        let contentWidth = cardRect.width - DictamenPDFLayout.cardInset * 2
        var currentY = cardRect.minY + DictamenPDFLayout.cardInset

        drawText(
            category.title.uppercased(),
            in: CGRect(x: contentX, y: currentY + 2, width: contentWidth * 0.72, height: 20),
            size: 13.5,
            weight: .bold,
            color: .black,
            alignment: .left
        )

        let countRect = CGRect(x: cardRect.maxX - DictamenPDFLayout.cardInset - 74, y: currentY, width: 74, height: 22)
        drawRoundedRect(countRect, radius: 11, fill: Theme.dictamenHeaderFill, stroke: Theme.dictamenSoftStroke)
        drawText(
            "\(category.rows.count) rutinas",
            in: countRect.insetBy(dx: 6, dy: 4),
            size: 8.5,
            weight: .bold,
            color: .darkGray
        )

        currentY += DictamenPDFLayout.cardHeaderHeight

        for (index, row) in category.rows.enumerated() {
            let rowRect = CGRect(x: contentX, y: currentY, width: contentWidth, height: DictamenPDFLayout.cardRowHeight)
            let fill = row.placement.isFirstPlace ? Theme.dictamenPink.withAlphaComponent(0.70) : Theme.dictamenAltFill
            drawRoundedRect(rowRect, radius: 9, fill: fill, stroke: Theme.dictamenSoftStroke)

            let badgeSize: CGFloat = 28
            let badgeWidth = row.placement.isParticipation ? CGFloat(38) : badgeSize
            let badgeRect = CGRect(x: rowRect.minX + 9, y: rowRect.midY - badgeSize / 2, width: badgeWidth, height: badgeSize)
            drawRoundedRect(
                badgeRect,
                radius: badgeSize / 2,
                fill: row.placement.isFirstPlace ? Theme.dictamenAccent : Theme.dictamenHeaderFill,
                stroke: Theme.dictamenSoftStroke
            )
            drawText(
                row.placement.shortLabel,
                in: badgeRect.insetBy(dx: 2, dy: 7),
                size: row.placement.isParticipation ? 7.4 : 9.5,
                weight: .bold,
                color: row.placement.isFirstPlace ? .white : Theme.dictamenAccent
            )

            let scoreWidth: CGFloat = 58
            let participationRect = CGRect(x: badgeRect.maxX + 8, y: rowRect.midY - 12, width: 44, height: 24)
            drawRoundedRect(
                participationRect,
                radius: 8,
                fill: Theme.dictamenHeaderFill,
                stroke: Theme.dictamenSoftStroke
            )
            drawText(
                "#\(clean(row.result.routine.id, fallback: "-"))",
                in: participationRect.insetBy(dx: 3, dy: 6),
                size: 8.8,
                weight: .bold,
                color: Theme.dictamenAccent
            )

            let textX = participationRect.maxX + 10
            let textWidth = rowRect.width - (textX - rowRect.minX) - scoreWidth - 18
            drawText(
                clean(row.result.routine.name, fallback: "SIN DATO"),
                in: CGRect(x: textX, y: rowRect.minY + 7, width: textWidth, height: 16),
                size: 11.5,
                weight: .bold,
                color: .black,
                alignment: .left
            )
            let metaText = "\(clean(row.result.routine.academy, fallback: "SIN DATO").uppercased())   \(clean(row.result.routine.state, fallback: "SIN DATO").uppercased())"
            drawText(
                metaText,
                in: CGRect(x: textX, y: rowRect.minY + 24, width: textWidth, height: 12),
                size: 7.5,
                weight: .bold,
                color: .darkGray,
                alignment: .left
            )

            let scoreRect = CGRect(x: rowRect.maxX - scoreWidth - 10, y: rowRect.minY + 7, width: scoreWidth, height: 30)
            drawText(
                row.result.aggregateTotal.formatted(.number.precision(.fractionLength(0...1))),
                in: CGRect(x: scoreRect.minX, y: scoreRect.minY, width: scoreRect.width, height: 18),
                size: 14,
                weight: .bold,
                color: .black,
                alignment: .right
            )
            drawText(
                "pts",
                in: CGRect(x: scoreRect.minX, y: scoreRect.minY + 17, width: scoreRect.width, height: 10),
                size: 7,
                weight: .bold,
                color: .darkGray,
                alignment: .right
            )

            currentY += DictamenPDFLayout.cardRowHeight + (index == category.rows.count - 1 ? 0 : DictamenPDFLayout.cardRowSpacing)
        }

        return cardRect.maxY + DictamenPDFLayout.categorySpacing
    }

    private static func drawDictamenSpecialAwardsCard(_ awards: [SpecialAwardSummary], y: CGFloat, margin: CGFloat, page: CGRect) -> CGFloat {
        guard UIGraphicsGetCurrentContext() != nil else { return y }

        let cardWidth = page.width - margin * 2
        let cardHeight = DictamenPDFLayout.specialAwardsHeight(rowCount: awards.count) - DictamenPDFLayout.categorySpacing
        let cardRect = CGRect(x: margin, y: y, width: cardWidth, height: cardHeight)
        drawRoundedRect(cardRect, radius: 10, fill: .white, stroke: Theme.dictamenSoftStroke)

        let contentX = cardRect.minX + DictamenPDFLayout.cardInset
        let contentWidth = cardRect.width - DictamenPDFLayout.cardInset * 2
        var currentY = cardRect.minY + DictamenPDFLayout.cardInset

        drawRoundedRect(
            CGRect(x: contentX, y: currentY, width: contentWidth, height: 32),
            radius: 9,
            fill: Theme.dictamenTitleFill,
            stroke: Theme.dictamenSoftStroke
        )
        drawText(
            "PREMIOS ESPECIALES",
            in: CGRect(x: contentX + 12, y: currentY + 8, width: contentWidth - 24, height: 16),
            size: 13,
            weight: .bold,
            color: .white,
            alignment: .left
        )

        currentY += 42

        for (index, award) in awards.enumerated() {
            let rowRect = CGRect(x: contentX, y: currentY, width: contentWidth, height: DictamenPDFLayout.specialAwardRowHeight)
            drawRoundedRect(rowRect, radius: 9, fill: Theme.dictamenAltFill, stroke: Theme.dictamenSoftStroke)

            let labelWidth: CGFloat = 190
            drawText(
                award.category.title.uppercased(),
                in: CGRect(x: rowRect.minX + 12, y: rowRect.minY + 9, width: labelWidth, height: 14),
                size: 8.8,
                weight: .bold,
                color: Theme.dictamenAccent,
                alignment: .left
            )

            let routineMeta: String
            if let routine = award.routine {
                routineMeta = "\(clean(routine.academy, fallback: "SIN DATO").uppercased())   \(clean(routine.state, fallback: "SIN DATO").uppercased())"
            } else {
                routineMeta = ""
            }

            let routineX = rowRect.minX + labelWidth + 22
            let routineWidth = rowRect.width - labelWidth - 34
            drawText(
                award.displayValue,
                in: CGRect(x: routineX, y: rowRect.minY + 7, width: routineWidth, height: 16),
                size: 11.5,
                weight: .bold,
                color: award.isAssigned ? .black : .darkGray,
                alignment: .left
            )
            if !routineMeta.isEmpty {
                drawText(
                    routineMeta,
                    in: CGRect(x: routineX, y: rowRect.minY + 24, width: routineWidth, height: 11),
                    size: 7.4,
                    weight: .bold,
                    color: .darkGray,
                    alignment: .left
                )
            }

            currentY += DictamenPDFLayout.specialAwardRowHeight + (index == awards.count - 1 ? 0 : DictamenPDFLayout.cardRowSpacing)
        }

        return cardRect.maxY + DictamenPDFLayout.categorySpacing
    }

    private static func drawDictamenHeader(y: CGFloat, margin: CGFloat, page: CGRect) -> CGFloat {
        let metrics = DictamenPDFLayout.metrics(pageWidth: page.width, margin: margin)
        var x = margin

        drawDictamenCell(rect: CGRect(x: x, y: y, width: metrics.categoryWidth, height: DictamenPDFLayout.headerHeight), text: "CATEGORIA", fill: Theme.dictamenHeaderFill, fontSize: 13, weight: .bold)
        x += metrics.categoryWidth
        drawDictamenCell(rect: CGRect(x: x, y: y, width: metrics.stateWidth, height: DictamenPDFLayout.headerHeight), text: "ESTADO", fill: Theme.dictamenHeaderFill, fontSize: 13, weight: .bold)
        x += metrics.stateWidth
        drawDictamenCell(rect: CGRect(x: x, y: y, width: metrics.academyWidth, height: DictamenPDFLayout.headerHeight), text: "ACADEMIA", fill: Theme.dictamenHeaderFill, fontSize: 13, weight: .bold)
        x += metrics.academyWidth
        drawDictamenCell(rect: CGRect(x: x, y: y, width: metrics.choreographyWidth, height: DictamenPDFLayout.headerHeight), text: "COREOGRAFÍA", fill: Theme.dictamenHeaderFill, fontSize: 13, weight: .bold)
        x += metrics.choreographyWidth
        drawDictamenCell(rect: CGRect(x: x, y: y, width: metrics.scoreWidth, height: DictamenPDFLayout.headerHeight), text: "PUNTAJE", fill: Theme.dictamenHeaderFill, fontSize: 13, weight: .bold)
        x += metrics.scoreWidth
        drawDictamenCell(rect: CGRect(x: x, y: y, width: metrics.positionWidth, height: DictamenPDFLayout.headerHeight), text: "TABLA DE\nPOSICIONES", fill: Theme.dictamenHeaderFill, fontSize: 12, weight: .bold)

        return y + DictamenPDFLayout.headerHeight
    }

    private static func drawDictamenCategory(_ category: DictamenCategorySection, y: CGFloat, margin: CGFloat, page: CGRect) {
        let metrics = DictamenPDFLayout.metrics(pageWidth: page.width, margin: margin)
        let blockHeight = CGFloat(max(category.rows.count, 1)) * DictamenPDFLayout.rowHeight
        var x = margin

        drawDictamenCell(
            rect: CGRect(x: x, y: y, width: metrics.categoryWidth, height: blockHeight),
            text: category.title.uppercased(),
            fill: Theme.dictamenPink,
            fontSize: 13,
            weight: .bold
        )
        x += metrics.categoryWidth

        for (index, row) in category.rows.enumerated() {
            let rowY = y + CGFloat(index) * DictamenPDFLayout.rowHeight
            let fill = index.isMultiple(of: 2) ? Theme.dictamenRowFill : Theme.dictamenAltFill
            x = margin + metrics.categoryWidth

            drawDictamenCell(rect: CGRect(x: x, y: rowY, width: metrics.stateWidth, height: DictamenPDFLayout.rowHeight), text: clean(row.result.routine.state, fallback: "SIN DATO").uppercased(), fill: fill, fontSize: 12, weight: .bold)
            x += metrics.stateWidth
            drawDictamenCell(rect: CGRect(x: x, y: rowY, width: metrics.academyWidth, height: DictamenPDFLayout.rowHeight), text: clean(row.result.routine.academy, fallback: "SIN DATO").uppercased(), fill: fill, fontSize: 11.5, weight: .bold)
            x += metrics.academyWidth
            drawDictamenCell(rect: CGRect(x: x, y: rowY, width: metrics.choreographyWidth, height: DictamenPDFLayout.rowHeight), text: clean(row.result.routine.name, fallback: "SIN DATO"), fill: fill, fontSize: 12.2, weight: .bold)
            x += metrics.choreographyWidth
            drawDictamenCell(rect: CGRect(x: x, y: rowY, width: metrics.scoreWidth, height: DictamenPDFLayout.rowHeight), text: row.result.aggregateTotal.formatted(.number.precision(.fractionLength(0...1))), fill: fill, fontSize: 13, weight: .bold)
            x += metrics.scoreWidth
            drawDictamenCell(rect: CGRect(x: x, y: rowY, width: metrics.positionWidth, height: DictamenPDFLayout.rowHeight), text: row.placement.tableLabel, fill: fill, fontSize: row.placement.isParticipation ? 8.4 : 13, weight: .bold)
        }
    }

    private static func drawDictamenCell(
        rect: CGRect,
        text: String,
        fill: UIColor,
        fontSize: CGFloat,
        weight: UIFont.Weight,
        color: UIColor = .black
    ) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(fill.cgColor)
        context.fill(rect)
        context.setStrokeColor(Theme.grid.cgColor)
        context.setLineWidth(0.75)
        context.stroke(rect)

        let textRect = rect.insetBy(dx: 4, dy: 3)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = fontSize * 1.03
        paragraph.maximumLineHeight = fontSize * 1.16

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textHeight = ceil(attributedText.boundingRect(
            with: CGSize(width: textRect.width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        ).height)
        let drawHeight = min(textRect.height, textHeight)
        let drawRect = CGRect(
            x: textRect.minX,
            y: textRect.midY - drawHeight / 2,
            width: textRect.width,
            height: drawHeight
        )
        attributedText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    private static func drawRoundedRect(_ rect: CGRect, radius: CGFloat, fill: UIColor, stroke: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        context.setFillColor(fill.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.setStrokeColor(stroke.cgColor)
        context.setLineWidth(0.8)
        context.addPath(path.cgPath)
        context.strokePath()
    }

    private static func sectionSpans(for criteria: [Criterion]) -> [(title: String, start: Int, count: Int)] {
        var spans: [(title: String, start: Int, count: Int)] = []
        for (index, criterion) in criteria.enumerated() {
            let section = clean(criterion.section, fallback: "CRITERIOS")
            if let last = spans.last, last.title == section {
                spans[spans.count - 1] = (last.title, last.start, last.count + 1)
            } else {
                spans.append((section, index, 1))
            }
        }
        return spans
    }

    private static func drawCell(
        rect: CGRect,
        text: String,
        fill: UIColor,
        fontSize: CGFloat,
        weight: UIFont.Weight = .regular,
        color: UIColor = .black,
        alignment: NSTextAlignment = .center,
        padding: CGFloat = 3
    ) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(fill.cgColor)
        context.fill(rect)
        context.setStrokeColor(Theme.grid.cgColor)
        context.setLineWidth(0.55)
        context.stroke(rect)

        let textRect = rect.insetBy(dx: padding, dy: 2)
        drawText(text, in: textRect, size: fontSize, weight: weight, color: color, alignment: alignment)
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        size: CGFloat,
        weight: UIFont.Weight = .regular,
        color: UIColor = .black,
        alignment: NSTextAlignment = .center
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.minimumLineHeight = size * 1.02
        paragraph.maximumLineHeight = size * 1.14
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
    }

    private static func clean(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func titleCase(_ value: String) -> String {
        value.localizedLowercase.capitalized
    }

    private static func filename(for title: String) -> String {
        let allowed = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
        let compact = String(allowed)
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return compact.isEmpty ? "dictamen-final" : compact
    }

    private static let placeholderRoutine = Routine(
        id: "",
        blockID: nil,
        block: "",
        name: "",
        academy: "",
        division: "",
        genre: "",
        level: "",
        category: "",
        choreographer: "",
        participant: nil,
        state: "",
        time: "",
        duration: ""
    )

    private struct CompleteRankingRow {
        let blockName: String
        let result: RoutineResult
    }

    private enum CompleteRankingTheme {
        static var primary: UIColor { AppBrand.competition.colorPalette.primary.uiColor }
        static var palePink: UIColor { AppBrand.competition.colorPalette.accentTint.lightUIColor }
        static var ink: UIColor { AppBrand.competition.colorPalette.ink.lightUIColor }
        static var muted: UIColor { AppBrand.competition.colorPalette.muted.lightUIColor }
        static let alternateRow = UIColor(white: 0.955, alpha: 1)
        static let line = UIColor(white: 0.0, alpha: 0.08)
        static var pinkStroke: UIColor { primary.withAlphaComponent(0.23) }
    }

    private enum CompleteRankingPDFLayout {
        static let logoHeight: CGFloat = 60
        static let sectionHeight: CGFloat = 38
        static let tableHeaderHeight: CGFloat = 24
        static let rowHeight: CGFloat = 23
        static let footerReservedHeight: CGFloat = 24

        static func columns(margin: CGFloat) -> Columns {
            let x = margin + 8
            let numberWidth: CGFloat = 62
            let choreographyWidth: CGFloat = 260
            let academyWidth: CGFloat = 220
            let scoreWidth: CGFloat = 86
            return Columns(
                numberX: x,
                numberWidth: numberWidth,
                choreographyX: x + numberWidth,
                choreographyWidth: choreographyWidth,
                academyX: x + numberWidth + choreographyWidth,
                academyWidth: academyWidth,
                scoreX: x + numberWidth + choreographyWidth + academyWidth,
                scoreWidth: scoreWidth
            )
        }

        static func topColumns(margin: CGFloat) -> TopColumns {
            let x = margin + 8
            let positionWidth: CGFloat = 46
            let numberWidth: CGFloat = 62
            let choreographyWidth: CGFloat = 230
            let academyWidth: CGFloat = 190
            let blockWidth: CGFloat = 80
            let scoreWidth: CGFloat = 86
            return TopColumns(
                positionX: x,
                positionWidth: positionWidth,
                numberX: x + positionWidth,
                numberWidth: numberWidth,
                choreographyX: x + positionWidth + numberWidth,
                choreographyWidth: choreographyWidth,
                academyX: x + positionWidth + numberWidth + choreographyWidth,
                academyWidth: academyWidth,
                blockX: x + positionWidth + numberWidth + choreographyWidth + academyWidth,
                blockWidth: blockWidth,
                scoreX: x + positionWidth + numberWidth + choreographyWidth + academyWidth + blockWidth,
                scoreWidth: scoreWidth
            )
        }

        struct Columns {
            let numberX: CGFloat
            let numberWidth: CGFloat
            let choreographyX: CGFloat
            let choreographyWidth: CGFloat
            let academyX: CGFloat
            let academyWidth: CGFloat
            let scoreX: CGFloat
            let scoreWidth: CGFloat
        }

        struct TopColumns {
            let positionX: CGFloat
            let positionWidth: CGFloat
            let numberX: CGFloat
            let numberWidth: CGFloat
            let choreographyX: CGFloat
            let choreographyWidth: CGFloat
            let academyX: CGFloat
            let academyWidth: CGFloat
            let blockX: CGFloat
            let blockWidth: CGFloat
            let scoreX: CGFloat
            let scoreWidth: CGFloat
        }
    }

    private enum Theme {
        static var paleYellow: UIColor { AppBrand.competition.colorPalette.accentTint.lightUIColor.withAlphaComponent(0.48) }
        static var headerFill: UIColor { AppBrand.competition.colorPalette.accentTint.lightUIColor.withAlphaComponent(0.68) }
        static let grid = UIColor(white: 0.12, alpha: 1)
        static var dictamenAccent: UIColor { AppBrand.competition.colorPalette.primary.uiColor }
        static var dictamenTitleFill: UIColor { AppBrand.competition.colorPalette.ink.lightUIColor }
        static var dictamenHeaderFill: UIColor { AppBrand.competition.colorPalette.accentTint.lightUIColor }
        static let dictamenSoftStroke = UIColor(white: 0.0, alpha: 0.10)
        static var dictamenPink: UIColor { AppBrand.competition.colorPalette.accentTint.lightUIColor }
        static let dictamenRowFill = UIColor(white: 0.84, alpha: 1)
        static let dictamenAltFill = UIColor(white: 0.93, alpha: 1)
    }

    private enum DictamenPDFLayout {
        static let titleHeight: CGFloat = 38
        static let headerHeight: CGFloat = 58
        static let rowHeight: CGFloat = 36
        static let categorySpacing: CGFloat = 14
        static let cardInset: CGFloat = 12
        static let cardHeaderHeight: CGFloat = 34
        static let cardRowHeight: CGFloat = 44
        static let cardRowSpacing: CGFloat = 7
        static let specialAwardRowHeight: CGFloat = 42

        static func categoryCardHeight(rowCount: Int) -> CGFloat {
            let rows = CGFloat(max(rowCount, 1))
            let gaps = CGFloat(max(rowCount - 1, 0)) * cardRowSpacing
            return cardInset * 2 + cardHeaderHeight + rows * cardRowHeight + gaps + categorySpacing
        }

        static func specialAwardsHeight(rowCount: Int) -> CGFloat {
            let rows = CGFloat(max(rowCount, 1))
            let gaps = CGFloat(max(rowCount - 1, 0)) * cardRowSpacing
            return cardInset * 2 + 42 + rows * specialAwardRowHeight + gaps + categorySpacing
        }

        static func metrics(pageWidth: CGFloat, margin: CGFloat) -> DictamenMetrics {
            let availableWidth = pageWidth - margin * 2
            let categoryWidth: CGFloat = 94
            let stateWidth: CGFloat = 74
            let academyWidth: CGFloat = 190
            let scoreWidth: CGFloat = 76
            let positionWidth: CGFloat = 92
            let choreographyWidth = availableWidth - categoryWidth - stateWidth - academyWidth - scoreWidth - positionWidth

            return DictamenMetrics(
                categoryWidth: categoryWidth,
                stateWidth: stateWidth,
                academyWidth: academyWidth,
                choreographyWidth: choreographyWidth,
                scoreWidth: scoreWidth,
                positionWidth: positionWidth
            )
        }

        struct DictamenMetrics {
            let categoryWidth: CGFloat
            let stateWidth: CGFloat
            let academyWidth: CGFloat
            let choreographyWidth: CGFloat
            let scoreWidth: CGFloat
            let positionWidth: CGFloat
        }
    }

    private enum Layout {
        static let sectionHeight: CGFloat = 18
        static let idHeight: CGFloat = 15
        static let labelHeight: CGFloat = 48
        static let maxHeight: CGFloat = 15
        static let rowHeight: CGFloat = 18

        static var headerHeight: CGFloat {
            sectionHeight + idHeight + labelHeight + maxHeight
        }

        static func metrics(criteriaCount: Int, pageWidth: CGFloat, margin: CGFloat) -> Metrics {
            let safeCriteriaCount = max(criteriaCount, 1)
            let numberWidth: CGFloat = 34
            let judgeWidth: CGFloat = 54
            let totalWidth: CGFloat = 38
            let averageWidth: CGFloat = 42
            let placeWidth: CGFloat = 34
            let availableWidth = pageWidth - margin * 2
            let fixedWidth = numberWidth + judgeWidth + totalWidth + averageWidth + placeWidth
            let routineWidth = criteriaCount > 15 ? CGFloat(100) : CGFloat(126)
            let criterionWidth = max(24, (availableWidth - fixedWidth - routineWidth) / CGFloat(safeCriteriaCount))

            return Metrics(
                numberWidth: numberWidth,
                routineWidth: routineWidth,
                judgeWidth: judgeWidth,
                criterionWidth: criterionWidth,
                totalWidth: totalWidth,
                averageWidth: averageWidth,
                placeWidth: placeWidth
            )
        }

        struct Metrics {
            let numberWidth: CGFloat
            let routineWidth: CGFloat
            let judgeWidth: CGFloat
            let criterionWidth: CGFloat
            let totalWidth: CGFloat
            let averageWidth: CGFloat
            let placeWidth: CGFloat
        }
    }
}
