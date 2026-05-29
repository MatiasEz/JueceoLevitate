import Foundation
import UIKit

enum JudgingSheetPDFExporter {
    static func export(
        routine: Routine,
        judge: String,
        template: JudgingTemplate,
        sourceName: String,
        blockName: String,
        fileName: String,
        feedback: String,
        penalty: Double,
        scoreForCriterion: (Criterion) -> Double
    ) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filenameWithoutExtension(fileName))
            .appendingPathExtension("pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 28
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Jueceo Coreografías",
            kCGPDFContextTitle as String: fileName
        ]

        let criteria = template.criteria.sorted { $0.id < $1.id }
        let subtotal = criteria.reduce(0) { $0 + scoreForCriterion($1) }
        let total = subtotal > 0 ? max(0, subtotal + penalty) : 0
        let maxTotal = template.maxScore > 0 ? template.maxScore : criteria.reduce(0) { $0 + $1.maxScore }

        do {
            try UIGraphicsPDFRenderer(bounds: page, format: format).writePDF(to: url) { context in
                context.beginPage()
                drawBackground(page: page)
                let criteriaTop = drawHeader(
                    sourceName: sourceName,
                    blockName: blockName,
                    routine: routine,
                    judge: judge,
                    total: total,
                    maxTotal: maxTotal,
                    margin: margin,
                    page: page
                )
                let footerTop = page.height - 156
                drawCriteria(
                    criteria: criteria,
                    y: criteriaTop,
                    bottomY: footerTop - 8,
                    margin: margin,
                    page: page,
                    scoreForCriterion: scoreForCriterion
                )
                drawFooter(
                    feedback: feedback,
                    total: total,
                    maxTotal: maxTotal,
                    penalty: penalty,
                    y: footerTop,
                    margin: margin,
                    page: page
                )
            }
            return url
        } catch {
            return nil
        }
    }

    private static func drawBackground(page: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(Theme.black.cgColor)
        context.fill(page)

        drawHalftoneDots(
            origin: CGPoint(x: 18, y: 18),
            rows: 10,
            columns: 18,
            spacing: 8,
            radius: 1.45,
            color: Theme.pink.withAlphaComponent(0.34)
        )
        drawHalftoneDots(
            origin: CGPoint(x: page.width - 150, y: 40),
            rows: 8,
            columns: 16,
            spacing: 8,
            radius: 1.25,
            color: Theme.white.withAlphaComponent(0.13)
        )

        drawDiagonalStroke(
            from: CGPoint(x: page.width - 110, y: 12),
            to: CGPoint(x: page.width + 16, y: 116),
            width: 19,
            color: Theme.pink.withAlphaComponent(0.72)
        )
        drawDiagonalStroke(
            from: CGPoint(x: page.width - 162, y: 44),
            to: CGPoint(x: page.width - 24, y: 156),
            width: 7,
            color: Theme.pink.withAlphaComponent(0.42)
        )
        drawDiagonalStroke(
            from: CGPoint(x: -18, y: page.height - 64),
            to: CGPoint(x: 164, y: page.height - 6),
            width: 17,
            color: Theme.pink.withAlphaComponent(0.55)
        )
        drawDiagonalStroke(
            from: CGPoint(x: page.width - 34, y: 190),
            to: CGPoint(x: page.width - 4, y: 690),
            width: 9,
            color: Theme.pink.withAlphaComponent(0.32)
        )
        drawEnergySweep(page: page)

    }

    private static func drawHeader(
        sourceName: String,
        blockName: String,
        routine: Routine,
        judge: String,
        total: Double,
        maxTotal: Double,
        margin: CGFloat,
        page: CGRect
    ) -> CGFloat {
        let fullWidth = page.width - margin * 2
        let heroTop: CGFloat = 24

        drawBrandLogo(
            in: CGRect(x: margin, y: heroTop - 4, width: 178, height: 52)
        )
        drawText(
            "CDMX 2026",
            in: CGRect(x: margin + 214, y: heroTop + 18, width: 156, height: 26),
            size: 21,
            weight: .heavy,
            color: Theme.pink,
            alignment: .left
        )
        drawDiagonalStroke(
            from: CGPoint(x: margin + 4, y: heroTop + 72),
            to: CGPoint(x: margin + 178, y: heroTop + 64),
            width: 2.4,
            color: Theme.white.withAlphaComponent(0.42)
        )

        drawBrushBand(CGRect(x: margin, y: heroTop + 81, width: 248, height: 34), color: Theme.pink)
        drawText(
            "HOJA DE JUECEO",
            in: CGRect(x: margin + 14, y: heroTop + 88, width: 220, height: 20),
            size: 16,
            weight: .black,
            color: Theme.white,
            alignment: .center
        )
        drawText(
            "\(sourceName) / \(blockName)".uppercased(),
            in: CGRect(x: margin, y: heroTop + 121, width: fullWidth - 148, height: 16),
            size: 8.6,
            weight: .semibold,
            color: Theme.silver,
            alignment: .left
        )

        drawScoreCard(
            total: total,
            maxTotal: maxTotal,
            rect: CGRect(x: page.width - margin - 126, y: heroTop + 12, width: 126, height: 104)
        )

        let cardY = heroTop + 146
        let cardHeight: CGFloat = 154
        let card = CGRect(x: margin, y: cardY, width: fullWidth, height: cardHeight)
        drawAngledShape(
            CGRect(x: margin + fullWidth - 142, y: cardY - 9, width: 154, height: 36),
            inset: 18,
            color: Theme.pink.withAlphaComponent(0.55)
        )
        drawDiagonalStroke(
            from: CGPoint(x: margin + 22, y: cardY - 8),
            to: CGPoint(x: margin + 208, y: cardY - 18),
            width: 1.3,
            color: Theme.pink.withAlphaComponent(0.55)
        )
        drawRoundedRect(card, fill: Theme.surface, stroke: Theme.pink.withAlphaComponent(0.62), cornerRadius: 14, lineWidth: 1.1)
        drawAngledShape(
            CGRect(x: card.maxX - 78, y: card.minY, width: 78, height: 34),
            inset: 18,
            color: Theme.pink.withAlphaComponent(0.92)
        )
        drawAngledShape(
            CGRect(x: card.maxX - 34, y: card.minY, width: 34, height: 34),
            inset: 10,
            color: Theme.black.withAlphaComponent(0.24)
        )
        drawBrushBand(CGRect(x: margin + 14, y: cardY + 12, width: 96, height: 10), color: Theme.pink.withAlphaComponent(0.9))

        drawText(
            "#\(routine.id)",
            in: CGRect(x: margin + 16, y: cardY + 24, width: 82, height: 22),
            size: 16,
            weight: .black,
            color: Theme.pink,
            alignment: .left
        )
        drawText(
            titleCase(routine.name),
            in: CGRect(x: margin + 91, y: cardY + 22, width: fullWidth - 108, height: 25),
            size: 18,
            weight: .black,
            color: Theme.black,
            alignment: .left
        )
        drawText(
            clean(routine.academy, fallback: "Sin academia").uppercased(),
            in: CGRect(x: margin + 16, y: cardY + 50, width: fullWidth - 32, height: 15),
            size: 9.3,
            weight: .heavy,
            color: Theme.gray,
            alignment: .left
        )

        let gap: CGFloat = 8
        let pillWidth = (fullWidth - 32 - gap * 2) / 3
        let firstRowY = cardY + 72
        drawMetaPill(label: "JUEZ", value: judge, rect: CGRect(x: margin + 16, y: firstRowY, width: pillWidth, height: 34))
        drawMetaPill(label: "GÉNERO / MODALIDAD", value: routine.genre, rect: CGRect(x: margin + 16 + pillWidth + gap, y: firstRowY, width: pillWidth, height: 34))
        drawMetaPill(label: "CATEGORIA", value: routine.category, rect: CGRect(x: margin + 16 + (pillWidth + gap) * 2, y: firstRowY, width: pillWidth, height: 34))

        let secondRowY = firstRowY + 38
        drawMetaPill(label: "DIVISION", value: routine.division, rect: CGRect(x: margin + 16, y: secondRowY, width: pillWidth, height: 30), compact: true)
        drawMetaPill(label: "NIVEL", value: routine.level, rect: CGRect(x: margin + 16 + pillWidth + gap, y: secondRowY, width: pillWidth, height: 30), compact: true)
        drawMetaPill(label: "# PARTICIPACION", value: routine.id, rect: CGRect(x: margin + 16 + (pillWidth + gap) * 2, y: secondRowY, width: pillWidth, height: 30), compact: true)

        return card.maxY + 14
    }

    private static func drawScoreCard(total: Double, maxTotal: Double, rect: CGRect) {
        drawRoundedRect(rect, fill: Theme.deepGray, stroke: Theme.pink, cornerRadius: 12, lineWidth: 1.2)
        drawText(
            "TOTAL",
            in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 12),
            size: 7.5,
            weight: .black,
            color: Theme.silver,
            alignment: .center
        )
        drawText(
            total.formatted(.number.precision(.fractionLength(0...1))),
            in: CGRect(x: rect.minX + 8, y: rect.minY + 30, width: rect.width - 16, height: 36),
            size: 31,
            weight: .black,
            color: Theme.pink,
            alignment: .center
        )
        drawText(
            "DE \(maxTotal.formatted(.number.precision(.fractionLength(0...1))))",
            in: CGRect(x: rect.minX + 12, y: rect.minY + 69, width: rect.width - 24, height: 14),
            size: 8.2,
            weight: .heavy,
            color: Theme.white,
            alignment: .center
        )
        drawBrushBand(
            CGRect(x: rect.minX + 18, y: rect.maxY - 17, width: rect.width - 36, height: 7),
            color: Theme.pink.withAlphaComponent(0.72)
        )
    }

    private static func drawCriteria(
        criteria: [Criterion],
        y: CGFloat,
        bottomY: CGFloat,
        margin: CGFloat,
        page: CGRect,
        scoreForCriterion: (Criterion) -> Double
    ) {
        let fullWidth = page.width - margin * 2
        let panel = CGRect(x: margin, y: y, width: fullWidth, height: bottomY - y)
        drawRoundedRect(panel, fill: Theme.surface, stroke: Theme.pink.withAlphaComponent(0.42), cornerRadius: 13, lineWidth: 0.95)

        let groups = sectionGroups(criteria)
        guard !criteria.isEmpty else {
            drawText(
                "SIN CRITERIOS DE JUECEO",
                in: panel.insetBy(dx: 18, dy: 28),
                size: 13,
                weight: .black,
                color: Theme.gray,
                alignment: .center
            )
            return
        }

        let tableX = panel.minX + 10
        let tableWidth = panel.width - 20
        let contentInset: CGFloat = 8
        var currentY = panel.minY + contentInset
        let contentBottom = panel.maxY - contentInset
        let rowHeight = criteriaRowHeight(
            criteriaCount: criteria.count,
            sectionCount: groups.count,
            availableHeight: panel.height - contentInset * 2
        )
        let criterionFont: CGFloat
        if rowHeight <= 15.6 {
            criterionFont = 6.45
        } else if rowHeight <= 17.2 {
            criterionFont = 7.05
        } else {
            criterionFont = 8.15
        }
        let compactRow = rowHeight <= 15.6
        let idWidth: CGFloat = 34
        let scoreWidth: CGFloat = 64
        let maxWidth: CGFloat = 52
        let criterionWidth = tableWidth - idWidth - maxWidth - scoreWidth

        drawBrushBand(CGRect(x: tableX + tableWidth - 166, y: currentY - 2, width: 152, height: 9), color: Theme.pink.withAlphaComponent(0.82))

        drawTableCell(
            rect: CGRect(x: tableX, y: currentY, width: idWidth, height: Layout.columnHeaderHeight),
            text: "#",
            fill: Theme.black,
            fontSize: 8,
            weight: .black,
            color: Theme.white
        )
        drawTableCell(
            rect: CGRect(x: tableX + idWidth, y: currentY, width: criterionWidth, height: Layout.columnHeaderHeight),
            text: "CRITERIO",
            fill: Theme.black,
            fontSize: 8,
            weight: .black,
            color: Theme.white,
            alignment: .left
        )
        drawTableCell(
            rect: CGRect(x: tableX + idWidth + criterionWidth, y: currentY, width: maxWidth, height: Layout.columnHeaderHeight),
            text: "MAX",
            fill: Theme.black,
            fontSize: 8,
            weight: .black,
            color: Theme.white
        )
        drawTableCell(
            rect: CGRect(x: tableX + idWidth + criterionWidth + maxWidth, y: currentY, width: scoreWidth, height: Layout.columnHeaderHeight),
            text: "PUNTAJE",
            fill: Theme.pink,
            fontSize: 8,
            weight: .black,
            color: Theme.white
        )
        currentY += Layout.columnHeaderHeight

        for section in groups {
            if currentY + Layout.sectionHeight + rowHeight > contentBottom + 0.5 {
                break
            }

            drawSectionHeader(
                rect: CGRect(x: tableX, y: currentY, width: tableWidth, height: Layout.sectionHeight),
                text: section.title.uppercased(),
                index: groups.firstIndex(where: { $0.title == section.title }) ?? 0
            )
            currentY += Layout.sectionHeight

            for (index, criterion) in section.criteria.enumerated() {
                if currentY + rowHeight > contentBottom + 0.5 {
                    return
                }
                let rowFill = index.isMultiple(of: 2) ? Theme.white : Theme.rowGray
                let score = scoreForCriterion(criterion)
                drawTableCell(
                    rect: CGRect(x: tableX, y: currentY, width: idWidth, height: rowHeight),
                    text: "\(criterion.id)",
                    fill: rowFill,
                    fontSize: compactRow ? 7.3 : 8.5,
                    weight: .black,
                    color: Theme.black
                )
                drawTableCell(
                    rect: CGRect(x: tableX + idWidth, y: currentY, width: criterionWidth, height: rowHeight),
                    text: criterion.label,
                    fill: rowFill,
                    fontSize: criterionFont,
                    weight: .semibold,
                    color: Theme.black,
                    alignment: .left
                )
                drawTableCell(
                    rect: CGRect(x: tableX + idWidth + criterionWidth, y: currentY, width: maxWidth, height: rowHeight),
                    text: criterion.maxScore.formatted(.number.precision(.fractionLength(0...1))),
                    fill: rowFill,
                    fontSize: compactRow ? 7.3 : 8.4,
                    weight: .black,
                    color: Theme.gray
                )
                drawScoreCell(
                    rect: CGRect(x: tableX + idWidth + criterionWidth + maxWidth, y: currentY, width: scoreWidth, height: rowHeight),
                    score: score,
                    rowFill: rowFill
                )
                currentY += rowHeight
            }
            currentY += Layout.sectionGap
        }
    }

    private static func drawFooter(
        feedback: String,
        total: Double,
        maxTotal: Double,
        penalty: Double,
        y: CGFloat,
        margin: CGFloat,
        page: CGRect
    ) {
        let fullWidth = page.width - margin * 2
        let summary = CGRect(x: margin, y: y, width: fullWidth, height: 44)
        drawRoundedRect(summary, fill: Theme.deepGray, stroke: Theme.pink.withAlphaComponent(0.8), cornerRadius: 13, lineWidth: 1)

        let gap: CGFloat = 10
        let metricWidth = (fullWidth - 28 - gap * 2) / 3
        drawFooterMetric(label: "TOTAL", value: total.formatted(.number.precision(.fractionLength(0...1))), rect: CGRect(x: margin + 14, y: y + 8, width: metricWidth, height: 28), accent: Theme.pink)
        drawFooterMetric(label: "MÁXIMO", value: maxTotal.formatted(.number.precision(.fractionLength(0...1))), rect: CGRect(x: margin + 14 + metricWidth + gap, y: y + 8, width: metricWidth, height: 28), accent: Theme.white)
        drawFooterMetric(label: "PENALIZACIÓN", value: penalty.formatted(.number.precision(.fractionLength(0...1))), rect: CGRect(x: margin + 14 + (metricWidth + gap) * 2, y: y + 8, width: metricWidth, height: 28), accent: Theme.white)

        let feedbackCard = CGRect(x: margin, y: y + 54, width: fullWidth, height: 94)
        drawRoundedRect(feedbackCard, fill: Theme.surface, stroke: Theme.silver.withAlphaComponent(0.55), cornerRadius: 12, lineWidth: 0.8)
        drawText(
            "RETROALIMENTACIÓN",
            in: CGRect(x: feedbackCard.minX + 14, y: feedbackCard.minY + 10, width: 176, height: 12),
            size: 8.2,
            weight: .black,
            color: Theme.pink,
            alignment: .left
        )
        drawWrappedText(
            feedback.trimmingCharacters(in: .whitespacesAndNewlines),
            in: CGRect(x: feedbackCard.minX + 14, y: feedbackCard.minY + 29, width: feedbackCard.width - 28, height: feedbackCard.height - 40),
            size: 8.4,
            weight: .medium,
            color: Theme.black,
            alignment: .left
        )
    }

    private static func drawMetaPill(label: String, value: String, rect: CGRect, compact: Bool = false) {
        drawRoundedRect(rect, fill: Theme.pillFill, stroke: Theme.pillStroke, cornerRadius: compact ? 7 : 8, lineWidth: 0.55)
        drawText(
            label,
            in: CGRect(x: rect.minX + 9, y: rect.minY + (compact ? 5 : 6), width: rect.width - 18, height: 9),
            size: compact ? 5.9 : 6.1,
            weight: .black,
            color: Theme.pink,
            alignment: .left
        )
        drawText(
            clean(value, fallback: "-"),
            in: CGRect(x: rect.minX + 9, y: rect.minY + (compact ? 15 : 17), width: rect.width - 18, height: compact ? 10 : 13),
            size: compact ? 7.8 : 8.5,
            weight: .heavy,
            color: Theme.black,
            alignment: .left
        )
    }

    private static func drawFooterMetric(label: String, value: String, rect: CGRect, accent: UIColor) {
        drawText(
            label,
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 9),
            size: 6.3,
            weight: .black,
            color: Theme.silver,
            alignment: .center
        )
        drawText(
            value,
            in: CGRect(x: rect.minX, y: rect.minY + 10, width: rect.width, height: 17),
            size: 13,
            weight: .black,
            color: accent,
            alignment: .center
        )
    }

    private static func criteriaRowHeight(criteriaCount: Int, sectionCount: Int, availableHeight: CGFloat) -> CGFloat {
        let sectionSpace = CGFloat(max(sectionCount, 1)) * Layout.sectionHeight
        let gaps = CGFloat(max(sectionCount, 1)) * Layout.sectionGap
        let rows = CGFloat(max(criteriaCount, 1))
        let usable = availableHeight - Layout.columnHeaderHeight - sectionSpace - gaps
        return min(Layout.maxRowHeight, max(Layout.minRowHeight, usable / rows))
    }

    private static func sectionGroups(_ criteria: [Criterion]) -> [(title: String, criteria: [Criterion])] {
        Dictionary(grouping: criteria, by: \.section)
            .map { title, items in (clean(title, fallback: "CRITERIOS"), items.sorted { $0.id < $1.id }) }
            .sorted { lhs, rhs in
                (lhs.criteria.first?.id ?? 0) < (rhs.criteria.first?.id ?? 0)
            }
    }

    private static func drawRoundedRect(
        _ rect: CGRect,
        fill: UIColor,
        stroke: UIColor,
        cornerRadius: CGFloat = 10,
        lineWidth: CGFloat = 0.7
    ) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        context.saveGState()
        context.setFillColor(fill.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        context.setStrokeColor(stroke.cgColor)
        context.setLineWidth(lineWidth)
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawTableCell(
        rect: CGRect,
        text: String,
        fill: UIColor,
        fontSize: CGFloat,
        weight: UIFont.Weight = .regular,
        color: UIColor = .black,
        alignment: NSTextAlignment = .center
    ) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setFillColor(fill.cgColor)
        context.fill(rect)
        context.setStrokeColor(Theme.grid.cgColor)
        context.setLineWidth(0.34)
        context.stroke(rect)
        context.restoreGState()
        let verticalPadding: CGFloat = rect.height <= 16 ? 1.4 : 4
        let textHeight = min(rect.height - verticalPadding, fontSize * 2.25)
        let textY = rect.midY - textHeight / 2
        drawText(
            text,
            in: CGRect(x: rect.minX + 6, y: textY, width: rect.width - 12, height: textHeight),
            size: fontSize,
            weight: weight,
            color: color,
            alignment: alignment
        )
    }

    private static func drawSectionHeader(rect: CGRect, text: String, index: Int) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setFillColor(Theme.pink.cgColor)
        context.fill(rect)
        context.setStrokeColor(Theme.grid.cgColor)
        context.setLineWidth(0.34)
        context.stroke(rect)
        context.restoreGState()

        drawAngledShape(
            CGRect(x: rect.maxX - 96, y: rect.minY, width: 96, height: rect.height),
            inset: 18,
            color: Theme.black.withAlphaComponent(0.24)
        )
        drawText(
            String(format: "%02d", index + 1),
            in: CGRect(x: rect.maxX - 44, y: rect.minY + 3, width: 32, height: rect.height - 6),
            size: 7.3,
            weight: .black,
            color: Theme.white.withAlphaComponent(0.72),
            alignment: .right
        )
        drawText(
            text,
            in: CGRect(x: rect.minX + 13, y: rect.minY + 3, width: rect.width - 68, height: rect.height - 6),
            size: 8.6,
            weight: .black,
            color: Theme.white,
            alignment: .left
        )
    }

    private static func drawScoreCell(rect: CGRect, score: Double, rowFill: UIColor) {
        let fill = score > 0 ? Theme.pinkTint.withAlphaComponent(0.55) : rowFill
        drawTableCell(rect: rect, text: "", fill: fill, fontSize: 8)
        guard score > 0 else { return }

        let compact = rect.height <= 15.6
        let pill = rect.insetBy(dx: compact ? 10 : 8, dy: max(2.0, rect.height * 0.17))
        drawRoundedRect(pill, fill: Theme.pink, stroke: Theme.pink, cornerRadius: pill.height / 2, lineWidth: 0)
        drawText(
            score.formatted(.number.precision(.fractionLength(0...1))),
            in: pill.insetBy(dx: 4, dy: 1),
            size: compact ? 7.5 : 8.9,
            weight: .black,
            color: Theme.white,
            alignment: .center
        )

        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setStrokeColor(Theme.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(0.7)
        context.move(to: CGPoint(x: pill.minX + 7, y: pill.minY + 3))
        context.addLine(to: CGPoint(x: pill.maxX - 7, y: pill.minY + 1.5))
        context.strokePath()
        context.restoreGState()
    }

    private static func drawBrushBand(_ rect: CGRect, color: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setFillColor(color.cgColor)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + 6, y: rect.minY + 4))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 11, y: rect.maxY - 4))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.close()
        context.addPath(path.cgPath)
        context.fillPath()

        context.setLineCap(.round)
        context.setStrokeColor(color.withAlphaComponent(0.72).cgColor)
        for index in 0..<5 {
            let offset = CGFloat(index) * 5
            context.setLineWidth(index.isMultiple(of: 2) ? 1.4 : 0.8)
            context.move(to: CGPoint(x: rect.minX - 8 + offset * 0.6, y: rect.minY + 3 + offset))
            context.addLine(to: CGPoint(x: rect.maxX + 10 - offset, y: rect.minY + 1 + offset))
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawAngledShape(_ rect: CGRect, inset: CGFloat, color: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setFillColor(color.cgColor)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.close()
        context.addPath(path.cgPath)
        context.fillPath()
        context.restoreGState()
    }

    private static func drawDiagonalStroke(from start: CGPoint, to end: CGPoint, width: CGFloat, color: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawEnergySweep(page: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setLineCap(.round)

        let upper = UIBezierPath()
        upper.move(to: CGPoint(x: -24, y: 188))
        upper.addCurve(
            to: CGPoint(x: page.width + 20, y: 128),
            controlPoint1: CGPoint(x: 154, y: 112),
            controlPoint2: CGPoint(x: 380, y: 210)
        )
        context.setStrokeColor(Theme.pink.withAlphaComponent(0.24).cgColor)
        context.setLineWidth(2.2)
        context.addPath(upper.cgPath)
        context.strokePath()

        let lower = UIBezierPath()
        lower.move(to: CGPoint(x: page.width + 14, y: page.height - 210))
        lower.addCurve(
            to: CGPoint(x: -26, y: page.height - 120),
            controlPoint1: CGPoint(x: 402, y: page.height - 138),
            controlPoint2: CGPoint(x: 172, y: page.height - 238)
        )
        context.setStrokeColor(Theme.white.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(1.5)
        context.addPath(lower.cgPath)
        context.strokePath()

        context.setStrokeColor(Theme.pink.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(0.8)
        for offset in stride(from: CGFloat(0), through: 52, by: 13) {
            context.move(to: CGPoint(x: page.width - 96 + offset, y: 250 + offset * 1.6))
            context.addLine(to: CGPoint(x: page.width - 54 + offset, y: 352 + offset * 1.3))
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawHalftoneDots(
        origin: CGPoint,
        rows: Int,
        columns: Int,
        spacing: CGFloat,
        radius: CGFloat,
        color: UIColor
    ) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setFillColor(color.cgColor)
        for row in 0..<rows {
            for column in 0..<columns {
                let fade = CGFloat(rows - row + columns - column) / CGFloat(rows + columns)
                let dotRadius = max(0.35, radius * fade)
                let point = CGPoint(
                    x: origin.x + CGFloat(column) * spacing,
                    y: origin.y + CGFloat(row) * spacing
                )
                context.fillEllipse(in: CGRect(x: point.x, y: point.y, width: dotRadius * 2, height: dotRadius * 2))
            }
        }
        context.restoreGState()
    }

    private static func drawBrandLogo(in rect: CGRect, alpha: CGFloat = 1, color: UIColor = Theme.white) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.setAlpha(alpha)
        if let image = UIImage(named: "LevitateLogo") {
            image.withRenderingMode(.alwaysOriginal)
                .draw(in: aspectFit(image.size, in: rect))
        } else {
            drawText(
                "Levitate",
                in: rect,
                size: min(rect.height * 0.72, 42),
                weight: .black,
                color: color,
                alignment: .left
            )
        }
        context.restoreGState()
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }

        let scale = min(rect.width / size.width, rect.height / size.height)
        let fittedSize = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: rect.midX - fittedSize.width / 2,
            y: rect.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
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
        paragraph.minimumLineHeight = size * 1.05
        paragraph.maximumLineHeight = size * 1.18
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
    }

    private static func drawWrappedText(
        _ text: String,
        in rect: CGRect,
        size: CGFloat,
        weight: UIFont.Weight = .regular,
        color: UIColor = .black,
        alignment: NSTextAlignment = .center,
        minimumSize: CGFloat = 6.8
    ) {
        let fittedSize = fittingFontSize(
            for: text,
            in: rect,
            size: size,
            minimumSize: minimumSize,
            weight: weight,
            alignment: alignment
        )
        let attributes = wrappedTextAttributes(size: fittedSize, weight: weight, color: color, alignment: alignment)
        text.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
    }

    private static func fittingFontSize(
        for text: String,
        in rect: CGRect,
        size: CGFloat,
        minimumSize: CGFloat,
        weight: UIFont.Weight,
        alignment: NSTextAlignment
    ) -> CGFloat {
        var currentSize = size
        while currentSize > minimumSize {
            let attributes = wrappedTextAttributes(size: currentSize, weight: weight, color: .black, alignment: alignment)
            let measured = (text as NSString).boundingRect(
                with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            if measured.height <= rect.height {
                return currentSize
            }
            currentSize -= 0.2
        }
        return minimumSize
    }

    private static func wrappedTextAttributes(
        size: CGFloat,
        weight: UIFont.Weight,
        color: UIColor,
        alignment: NSTextAlignment
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = size * 1.12
        paragraph.maximumLineHeight = size * 1.24
        return [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }

    private static func titleCase(_ value: String) -> String {
        value.localizedLowercase.capitalized
    }

    private static func clean(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
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
        return compact.isEmpty ? "hoja-de-jueceo" : compact
    }

    private enum Theme {
        static let black = UIColor(red: 0.018, green: 0.018, blue: 0.02, alpha: 1)
        static let deepGray = UIColor(red: 0.055, green: 0.055, blue: 0.06, alpha: 1)
        static let gray = UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1)
        static let silver = UIColor(red: 0.72, green: 0.72, blue: 0.72, alpha: 1)
        static let rowGray = UIColor(red: 0.945, green: 0.945, blue: 0.95, alpha: 1)
        static let surface = UIColor(red: 0.985, green: 0.985, blue: 0.985, alpha: 1)
        static let white = UIColor.white
        static let pink = UIColor(red: 0.93, green: 0.0, blue: 0.36, alpha: 1)
        static let pinkTint = UIColor(red: 1, green: 0.89, blue: 0.93, alpha: 1)
        static let pillFill = UIColor(red: 0.965, green: 0.965, blue: 0.97, alpha: 1)
        static let pillStroke = UIColor(red: 0.84, green: 0.84, blue: 0.86, alpha: 1)
        static let grid = UIColor(red: 0.76, green: 0.76, blue: 0.78, alpha: 1)
    }

    private enum Layout {
        static let columnHeaderHeight: CGFloat = 20
        static let sectionHeight: CGFloat = 16.5
        static let sectionGap: CGFloat = 2
        static let minRowHeight: CGFloat = 13.8
        static let maxRowHeight: CGFloat = 22.5
    }
}
