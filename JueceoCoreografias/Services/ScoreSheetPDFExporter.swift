import Foundation
import UIKit

enum ScoreSheetPDFExporter {
    static func export(
        results: [RoutineResult],
        judges: [String],
        sourceName: String,
        blockName: String,
        academyName: String?,
        fileName: String,
        positions: [String: Int],
        templateForRoutine: (Routine) -> JudgingTemplate,
        scoreForCriterion: (Routine, String, Criterion) -> Double,
        penaltyForRoutine: (Routine, String) -> Double
    ) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filenameWithoutExtension(fileName))
            .appendingPathExtension("pdf")

        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        let margin: CGFloat = 20
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Jueceo Coreografias",
            kCGPDFContextTitle as String: fileName
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let groups = groupedByGenre(results)
        let exportJudges = judges.isEmpty ? ["-"] : judges

        do {
            try renderer.writePDF(to: url) { context in
                var didStartPage = false

                for group in groups {
                    let criteria = templateForRoutine(group.results.first?.routine ?? placeholderRoutine)
                        .criteria
                        .sorted { $0.id < $1.id }
                    let sortedResults = group.results.sorted(by: routineOrder)
                    var y = margin

                    context.beginPage()
                    didStartPage = true
                    y = drawPageHeader(
                        sourceName: sourceName,
                        blockName: blockName,
                        academyName: academyName,
                        genre: group.genre,
                        y: y,
                        margin: margin,
                        page: page
                    )
                    y = drawTableHeader(criteria: criteria, y: y, margin: margin, page: page)

                    for result in sortedResults {
                        let neededHeight = CGFloat(exportJudges.count) * Layout.rowHeight
                        if y + neededHeight > page.height - margin {
                            context.beginPage()
                            y = margin
                            y = drawPageHeader(
                                sourceName: sourceName,
                                blockName: blockName,
                                academyName: academyName,
                                genre: "\(group.genre) - continuacion",
                                y: y,
                                margin: margin,
                                page: page
                            )
                            y = drawTableHeader(criteria: criteria, y: y, margin: margin, page: page)
                        }

                        let position = positions[result.routine.id]
                        drawRoutineRows(
                            result: result,
                            judges: exportJudges,
                            criteria: criteria,
                            position: position,
                            y: y,
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
                    _ = drawPageHeader(
                        sourceName: sourceName,
                        blockName: blockName,
                        academyName: academyName,
                        genre: "Sin calificaciones",
                        y: margin,
                        margin: margin,
                        page: page
                    )
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private static func groupedByGenre(_ results: [RoutineResult]) -> [(genre: String, results: [RoutineResult])] {
        Dictionary(grouping: results) { result in
            clean(result.routine.genre, fallback: "SIN GENERO")
        }
        .map { genre, items in (genre, items) }
        .sorted { lhs, rhs in lhs.genre.localizedStandardCompare(rhs.genre) == .orderedAscending }
    }

    private static func drawPageHeader(
        sourceName: String,
        blockName: String,
        academyName: String?,
        genre: String,
        y: CGFloat,
        margin: CGFloat,
        page: CGRect
    ) -> CGFloat {
        let fullWidth = page.width - margin * 2
        let title = "\(blockName) - \(genre)".uppercased()
        drawCell(
            rect: CGRect(x: margin, y: y, width: fullWidth, height: 28),
            text: title,
            fill: .white,
            fontSize: 20,
            weight: .bold
        )

        let meta = [
            clean(sourceName, fallback: "LEVITATE CDMX 2026"),
            academyName.map { "ACADEMIA: \(clean($0, fallback: "-"))" } ?? "TODAS LAS ACADEMIAS",
            "PENALIZACION: VER TABLA"
        ]
        drawText(
            meta.joined(separator: "  |  "),
            in: CGRect(x: margin, y: y + 32, width: fullWidth, height: 16),
            size: 9.5,
            color: .darkGray,
            alignment: .left
        )
        return y + 54
    }

    private static func drawTableHeader(criteria: [Criterion], y: CGFloat, margin: CGFloat, page: CGRect) -> CGFloat {
        let metrics = Layout.metrics(criteriaCount: criteria.count, pageWidth: page.width, margin: margin)
        var x = margin

        drawCell(rect: CGRect(x: x, y: y, width: metrics.numberWidth, height: Layout.headerHeight), text: "#", fill: Theme.headerFill, fontSize: 7.6, weight: .bold)
        x += metrics.numberWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.routineWidth, height: Layout.headerHeight), text: "COREOGRAFIA", fill: Theme.headerFill, fontSize: 7.6, weight: .bold)
        x += metrics.routineWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.academyWidth, height: Layout.headerHeight), text: "ACADEMIA", fill: Theme.headerFill, fontSize: 7.6, weight: .bold)
        x += metrics.academyWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.judgeWidth, height: Layout.headerHeight), text: "JUEZ", fill: Theme.headerFill, fontSize: 7.6, weight: .bold)
        x += metrics.judgeWidth

        for span in sectionSpans(for: criteria) {
            let sectionX = x + CGFloat(span.start) * metrics.criterionWidth
            let sectionWidth = CGFloat(span.count) * metrics.criterionWidth
            drawCell(
                rect: CGRect(x: sectionX, y: y, width: sectionWidth, height: Layout.sectionHeight),
                text: span.title.uppercased(),
                fill: .white,
                fontSize: 7.7,
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
                fontSize: 7,
                weight: .bold
            )
            drawCell(
                rect: CGRect(x: criterionX, y: labelY, width: metrics.criterionWidth, height: Layout.labelHeight),
                text: criterion.label,
                fill: .white,
                fontSize: 4.8,
                weight: .regular,
                alignment: .center,
                padding: 2
            )
            drawCell(
                rect: CGRect(x: criterionX, y: maxY, width: metrics.criterionWidth, height: Layout.maxHeight),
                text: formatScore(criterion.maxScore),
                fill: Theme.headerFill,
                fontSize: 6.6,
                weight: .bold
            )
        }

        x += CGFloat(max(criteria.count, 1)) * metrics.criterionWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.judgeTotalWidth, height: Layout.headerHeight), text: "TOTAL", fill: Theme.headerFill, fontSize: 7.2, weight: .bold)
        x += metrics.judgeTotalWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.scoreWidth, height: Layout.headerHeight), text: "PUNTAJE", fill: Theme.headerFill, fontSize: 6.8, weight: .bold)
        x += metrics.scoreWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.penaltyWidth, height: Layout.headerHeight), text: "PENAL.", fill: Theme.headerFill, fontSize: 6.8, weight: .bold)
        x += metrics.penaltyWidth
        drawCell(rect: CGRect(x: x, y: y, width: metrics.positionWidth, height: Layout.headerHeight), text: "POS.", fill: Theme.headerFill, fontSize: 7.2, weight: .bold)

        return y + Layout.headerHeight
    }

    private static func drawRoutineRows(
        result: RoutineResult,
        judges: [String],
        criteria: [Criterion],
        position: Int?,
        y: CGFloat,
        page: CGRect,
        margin: CGFloat,
        scoreForCriterion: (Routine, String, Criterion) -> Double,
        penaltyForRoutine: (Routine, String) -> Double
    ) {
        let metrics = Layout.metrics(criteriaCount: criteria.count, pageWidth: page.width, margin: margin)
        let aggregate = aggregateTotal(for: result, judges: judges)
        let aggregatePenalty = penaltyTotal(for: result, judges: judges)

        for (judgeIndex, judge) in judges.enumerated() {
            let rowY = y + CGFloat(judgeIndex) * Layout.rowHeight
            let isFirstJudge = judgeIndex == 0
            let fill = result.routine.id.hashValue.isMultiple(of: 2) ? Theme.paleYellow : .white
            let judgeTotal = criteria.reduce(0) { sum, criterion in
                sum + scoreForCriterion(result.routine, judge, criterion)
            }
            var x = margin

            drawCell(rect: CGRect(x: x, y: rowY, width: metrics.numberWidth, height: Layout.rowHeight), text: isFirstJudge ? result.routine.id : "", fill: fill, fontSize: 7.1, weight: .bold)
            x += metrics.numberWidth
            drawCell(rect: CGRect(x: x, y: rowY, width: metrics.routineWidth, height: Layout.rowHeight), text: isFirstJudge ? titleCase(result.routine.name) : "", fill: fill, fontSize: 6.6, weight: .semibold, alignment: .left)
            x += metrics.routineWidth
            drawCell(rect: CGRect(x: x, y: rowY, width: metrics.academyWidth, height: Layout.rowHeight), text: isFirstJudge ? result.routine.academy : "", fill: fill, fontSize: 6.2, weight: .regular, alignment: .left)
            x += metrics.academyWidth
            drawCell(rect: CGRect(x: x, y: rowY, width: metrics.judgeWidth, height: Layout.rowHeight), text: judge, fill: fill, fontSize: 6.7, weight: .semibold)
            x += metrics.judgeWidth

            for criterion in criteria {
                let score = scoreForCriterion(result.routine, judge, criterion)
                drawCell(
                    rect: CGRect(x: x, y: rowY, width: metrics.criterionWidth, height: Layout.rowHeight),
                    text: score > 0 ? formatScore(score) : "",
                    fill: fill,
                    fontSize: 6.8
                )
                x += metrics.criterionWidth
            }

            drawCell(rect: CGRect(x: x, y: rowY, width: metrics.judgeTotalWidth, height: Layout.rowHeight), text: judgeTotal > 0 ? formatScore(judgeTotal) : "", fill: fill, fontSize: 6.9, weight: .bold)
            x += metrics.judgeTotalWidth
            drawCell(rect: CGRect(x: x, y: rowY, width: metrics.scoreWidth, height: Layout.rowHeight), text: isFirstJudge && aggregate > 0 ? formatScore(aggregate) : "", fill: fill, fontSize: 6.9, weight: .bold)
            x += metrics.scoreWidth
            drawCell(rect: CGRect(x: x, y: rowY, width: metrics.penaltyWidth, height: Layout.rowHeight), text: isFirstJudge && aggregatePenalty != 0 ? formatScore(aggregatePenalty) : "", fill: fill, fontSize: 6.9, weight: .bold)
            x += metrics.penaltyWidth
            drawCell(rect: CGRect(x: x, y: rowY, width: metrics.positionWidth, height: Layout.rowHeight), text: isFirstJudge ? positionText(position, aggregate: aggregate) : "", fill: fill, fontSize: 6.9, weight: .bold)
        }
    }

    private static func aggregateTotal(for result: RoutineResult, judges: [String]) -> Double {
        let totalsByJudge = Dictionary(uniqueKeysWithValues: result.judgeTotals.map { ($0.judge, $0.total) })
        return judges.reduce(0) { sum, judge in
            sum + (totalsByJudge[judge] ?? 0)
        }
    }

    private static func penaltyTotal(for result: RoutineResult, judges: [String]) -> Double {
        let penaltiesByJudge = Dictionary(uniqueKeysWithValues: result.judgePenalties.map { ($0.judge, $0.value) })
        return judges.reduce(0) { sum, judge in
            sum + (penaltiesByJudge[judge] ?? 0)
        }
    }

    private static func positionText(_ position: Int?, aggregate: Double) -> String {
        guard aggregate > 0, let position else { return "" }
        return "\(position)°"
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
        if spans.isEmpty {
            spans.append(("CRITERIOS", 0, 1))
        }
        return spans
    }

    private static func routineOrder(_ lhs: RoutineResult, _ rhs: RoutineResult) -> Bool {
        let lhsNumber = Int(lhs.routine.id) ?? Int.max
        let rhsNumber = Int(rhs.routine.id) ?? Int.max
        if lhsNumber == rhsNumber {
            return lhs.routine.id.localizedStandardCompare(rhs.routine.id) == .orderedAscending
        }
        return lhsNumber < rhsNumber
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
        context.setLineWidth(0.5)
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
        paragraph.maximumLineHeight = size * 1.16
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

    private static func formatScore(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func filenameWithoutExtension(_ fileName: String) -> String {
        let name = fileName.hasSuffix(".pdf") ? String(fileName.dropLast(4)) : fileName
        let allowed = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
        let compact = String(allowed)
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return compact.isEmpty ? "calificaciones" : compact
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
        state: "",
        time: "",
        duration: ""
    )

    private enum Theme {
        static let paleYellow = UIColor(red: 0.996, green: 0.949, blue: 0.796, alpha: 1)
        static let headerFill = UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1)
        static let grid = UIColor(white: 0.12, alpha: 1)
    }

    private enum Layout {
        static let sectionHeight: CGFloat = 17
        static let idHeight: CGFloat = 13
        static let labelHeight: CGFloat = 42
        static let maxHeight: CGFloat = 13
        static let rowHeight: CGFloat = 17

        static var headerHeight: CGFloat {
            sectionHeight + idHeight + labelHeight + maxHeight
        }

        static func metrics(criteriaCount: Int, pageWidth: CGFloat, margin: CGFloat) -> Metrics {
            let safeCriteriaCount = max(criteriaCount, 1)
            let numberWidth: CGFloat = 30
            let judgeWidth: CGFloat = 46
            let judgeTotalWidth: CGFloat = 38
            let scoreWidth: CGFloat = 44
            let penaltyWidth: CGFloat = 42
            let positionWidth: CGFloat = 34
            let routineWidth: CGFloat = criteriaCount > 15 ? 92 : 104
            let academyWidth: CGFloat = criteriaCount > 15 ? 96 : 112
            let availableWidth = pageWidth - margin * 2
            let fixedWidth = numberWidth + routineWidth + academyWidth + judgeWidth + judgeTotalWidth + scoreWidth + penaltyWidth + positionWidth
            let criterionWidth = max(21, (availableWidth - fixedWidth) / CGFloat(safeCriteriaCount))

            return Metrics(
                numberWidth: numberWidth,
                routineWidth: routineWidth,
                academyWidth: academyWidth,
                judgeWidth: judgeWidth,
                criterionWidth: criterionWidth,
                judgeTotalWidth: judgeTotalWidth,
                scoreWidth: scoreWidth,
                penaltyWidth: penaltyWidth,
                positionWidth: positionWidth
            )
        }

        struct Metrics {
            let numberWidth: CGFloat
            let routineWidth: CGFloat
            let academyWidth: CGFloat
            let judgeWidth: CGFloat
            let criterionWidth: CGFloat
            let judgeTotalWidth: CGFloat
            let scoreWidth: CGFloat
            let penaltyWidth: CGFloat
            let positionWidth: CGFloat
        }
    }
}
