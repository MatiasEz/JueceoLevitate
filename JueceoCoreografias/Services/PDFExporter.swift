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
