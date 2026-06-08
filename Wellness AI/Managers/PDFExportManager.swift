import SwiftUI
import PDFKit

class PDFExportManager {
    static let shared = PDFExportManager()
    
    @MainActor
    func generateHealthReport(
        userGoals: UserGoals,
        healthMetrics: HealthMetrics?,
        sevenDayMetrics: SevenDayHealthMetrics?
    ) -> URL? {
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595.2, height: 841.8)) // A4 size
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Nessa_Health_Report.pdf")
        
        do {
            try pdfRenderer.writePDF(to: tempURL) { context in
                context.beginPage()
                
                var yOffset: CGFloat = 40
                let margin: CGFloat = 40
                let contentWidth: CGFloat = 595.2 - (2 * margin)
                
                // Header
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 22),
                    .foregroundColor: UIColor.systemIndigo
                ]
                "Nessa Health Report".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: titleAttributes)
                yOffset += 26
                
                let dateAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                "Generated on \(Date().formatted(date: .long, time: .shortened))".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: dateAttributes)
                yOffset += 24
                
                // Patient Banner
                drawPatientBanner(y: &yOffset, margin: margin, width: contentWidth)
                
                // Executive Summary Section
                if let summary = userGoals.medicalInfo.executiveSummary {
                    drawSectionTitle("Clinical Executive Summary", y: &yOffset, margin: margin)
                    
                    let summaryAttr: [NSAttributedString.Key: Any] = [
                        .font: UIFont.italicSystemFont(ofSize: 11),
                        .foregroundColor: UIColor.darkGray
                    ]
                    let summaryRect = summary.boundingRect(
                        with: CGSize(width: contentWidth, height: 1000),
                        options: .usesLineFragmentOrigin,
                        attributes: summaryAttr,
                        context: nil
                    )
                    
                    let bgRect = CGRect(x: margin, y: yOffset - 5, width: contentWidth, height: summaryRect.height + 10)
                    let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: 6)
                    UIColor.systemGray6.withAlphaComponent(0.8).setFill()
                    bgPath.fill()
                    
                    summary.draw(in: CGRect(x: margin + 10, y: yOffset, width: contentWidth - 20, height: summaryRect.height), withAttributes: summaryAttr)
                    yOffset += summaryRect.height + 25
                }
                
                // Medical Information Section
                drawSectionTitle("Medical Profile & Treatment Plan", y: &yOffset, margin: margin)
                
                if !userGoals.medicalInfo.conditions.isEmpty {
                    drawSubHeader("Active Medical Conditions", y: &yOffset, margin: margin)
                    drawList(userGoals.medicalInfo.conditions, y: &yOffset, margin: margin + 8, width: contentWidth)
                }
                
                if !userGoals.medicalInfo.medications.isEmpty {
                    drawSubHeader("Current Medications", y: &yOffset, margin: margin)
                    let meds = userGoals.medicalInfo.medications.map { "\($0.name) (\($0.dosage) • \($0.frequency))" }
                    drawList(meds, y: &yOffset, margin: margin + 8, width: contentWidth)
                }
                
                if !userGoals.medicalInfo.allergies.isEmpty {
                    drawSubHeader("Allergies & Sensitivities", y: &yOffset, margin: margin)
                    drawList(userGoals.medicalInfo.allergies, y: &yOffset, margin: margin + 8, width: contentWidth)
                }
                
                // Start a new page for vitals grid and doctor sign-off
                context.beginPage()
                yOffset = 40
                
                // Clinical Biometric Baseline
                drawGridOfVitals(metrics: healthMetrics, sevenDayMetrics: sevenDayMetrics, y: &yOffset, margin: margin, width: contentWidth)
                
                // AI Priority Metrics Section
                if !userGoals.priorityMetrics.isEmpty {
                    drawSectionTitle("AI Priority Tracking Guidelines", y: &yOffset, margin: margin)
                    
                    for metric in userGoals.priorityMetrics {
                        if yOffset > 660 { context.beginPage(); yOffset = 40 }
                        
                        let metricTitleAttr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: UIColor.label]
                        "• \(metric.metricName) (Target: \(metric.healthyRange))".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: metricTitleAttr)
                        yOffset += 16
                        
                        let reasonAttr: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 10),
                            .foregroundColor: UIColor.secondaryLabel
                        ]
                        let reasonRect = CGRect(x: margin + 12, y: yOffset, width: contentWidth - 12, height: 100)
                        metric.reason.draw(in: reasonRect, withAttributes: reasonAttr)
                        
                        let reasonSize = metric.reason.boundingRect(
                            with: CGSize(width: contentWidth - 12, height: 1000),
                            options: .usesLineFragmentOrigin,
                            attributes: reasonAttr,
                            context: nil
                        )
                        yOffset += reasonSize.height + 12
                    }
                    yOffset += 10
                }
                
                // Physician Notes
                if yOffset > 680 { context.beginPage(); yOffset = 40 }
                drawPhysicianNotesBox(y: &yOffset, margin: margin, width: contentWidth)
                
                // Footer
                drawFooter(contextWidth: contentWidth, margin: margin)
            }
            return tempURL
        } catch {
            print("Could not create PDF: \(error)")
            return nil
        }
    }
    
    @MainActor
    func generateConditionReport(
        condition: String,
        userGoals: UserGoals,
        healthMetrics: HealthMetrics?,
        sevenDayMetrics: SevenDayHealthMetrics?
    ) -> URL? {
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595.2, height: 841.8)) // A4 size
        
        let sanitizedCondition = condition.replacingOccurrences(of: " ", with: "_")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Nessa_\(sanitizedCondition)_Report.pdf")
        
        do {
            try pdfRenderer.writePDF(to: tempURL) { context in
                context.beginPage()
                
                var yOffset: CGFloat = 40
                let margin: CGFloat = 40
                let contentWidth: CGFloat = 595.2 - (2 * margin)
                
                // Header Title
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.systemIndigo
                ]
                "Nessa Clinical Report - \(condition)".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: titleAttributes)
                yOffset += 26
                
                // Subtitle
                let dateAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                "Patient Care & Metric Summary • Generated on \(Date().formatted(date: .long, time: .shortened))".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: dateAttributes)
                yOffset += 24
                
                // Patient Banner
                drawPatientBanner(y: &yOffset, margin: margin, width: contentWidth)
                
                // Section 1: AI Management Insights
                if let existingInsight = userGoals.medicalInfo.insights[condition] {
                    drawSectionTitle("AI Management Insights", y: &yOffset, margin: margin)
                    
                    let insightAttr: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 11),
                        .foregroundColor: UIColor.darkGray
                    ]
                    let insightRect = existingInsight.boundingRect(
                        with: CGSize(width: contentWidth, height: 1000),
                        options: .usesLineFragmentOrigin,
                        attributes: insightAttr,
                        context: nil
                    )
                    
                    let bgRect = CGRect(x: margin, y: yOffset - 5, width: contentWidth, height: insightRect.height + 10)
                    let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: 6)
                    UIColor.systemPurple.withAlphaComponent(0.04).setFill()
                    bgPath.fill()
                    
                    existingInsight.draw(in: CGRect(x: margin + 10, y: yOffset, width: contentWidth - 20, height: insightRect.height), withAttributes: insightAttr)
                    yOffset += insightRect.height + 25
                }
                
                // Section 2: Related Priority Metrics
                let relatedMetrics = userGoals.priorityMetrics.filter { $0.relatedConditions.contains(condition) }
                if !relatedMetrics.isEmpty {
                    drawSectionTitle("Related Priority Metrics", y: &yOffset, margin: margin)
                    
                    for metric in relatedMetrics {
                        if yOffset > 720 { context.beginPage(); yOffset = 40 }
                        
                        let metricTitleAttr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 12)]
                        let valStr: String
                        if metric.isManual {
                            valStr = userGoals.getLatestManualValue(for: metric.metricName) ?? "N/A"
                        } else {
                            valStr = getCurrentValue(for: metric.metricName, healthMetrics: healthMetrics)
                        }
                        
                        "\(metric.metricName): \(valStr)".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: metricTitleAttr)
                        yOffset += 16
                        
                        let detailAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.secondaryLabel]
                        "Healthy Target Range: \(metric.healthyRange)".draw(at: CGPoint(x: margin + 10, y: yOffset), withAttributes: detailAttr)
                        yOffset += 14
                        
                        let reasonAttr: [NSAttributedString.Key: Any] = [
                            .font: UIFont.italicSystemFont(ofSize: 10),
                            .foregroundColor: UIColor.secondaryLabel
                        ]
                        let reasonRect = CGRect(x: margin + 10, y: yOffset, width: contentWidth - 10, height: 100)
                        metric.reason.draw(in: reasonRect, withAttributes: reasonAttr)
                        
                        let reasonSize = metric.reason.boundingRect(
                            with: CGSize(width: contentWidth - 10, height: 1000),
                            options: .usesLineFragmentOrigin,
                            attributes: reasonAttr,
                            context: nil
                        )
                        yOffset += reasonSize.height + 15
                    }
                }
                
                // Start page if needed
                if yOffset > 600 { context.beginPage(); yOffset = 40 }
                
                // Section 3: Recent Symptom Logs
                let symptomLogs = userGoals.symptomLogs.filter { $0.condition == condition }
                if !symptomLogs.isEmpty {
                    drawSectionTitle("Recent Symptom Logs (Last 7 Days)", y: &yOffset, margin: margin)
                    
                    let symptomsList = symptomLogs.sorted(by: { $0.timestamp > $1.timestamp }).prefix(7).map { log in
                        let dateStr = log.timestamp.formatted(date: .abbreviated, time: .omitted)
                        let notesStr = log.notes.map { " - \($0)" } ?? ""
                        return "\(dateStr): \(log.symptomName) (Severity: \(log.severity)/10)\(notesStr)"
                    }
                    drawList(Array(symptomsList), y: &yOffset, margin: margin + 8, width: contentWidth)
                }
                
                // Section 4: Daily Adherence & Action Compliance
                let adherenceLogs = userGoals.adherenceLogs.filter { $0.condition == condition }
                if !adherenceLogs.isEmpty {
                    if yOffset > 700 { context.beginPage(); yOffset = 40 }
                    drawSectionTitle("Treatment Compliance & Lifestyle Actions", y: &yOffset, margin: margin)
                    
                    let adherenceList = adherenceLogs.sorted(by: { $0.timestamp > $1.timestamp }).prefix(7).map { log in
                        let dateStr = log.timestamp.formatted(date: .abbreviated, time: .omitted)
                        let statusStr = log.isFollowed ? "Followed" : "Not Followed"
                        return "\(dateStr): \(log.actionName) — \(statusStr)"
                    }
                    drawList(Array(adherenceList), y: &yOffset, margin: margin + 8, width: contentWidth)
                }
                
                // Section 5: Related Medications
                let relatedMeds = userGoals.medicalInfo.medications
                if !relatedMeds.isEmpty {
                    if yOffset > 700 { context.beginPage(); yOffset = 40 }
                    drawSectionTitle("Associated Medications", y: &yOffset, margin: margin)
                    
                    let medsList = relatedMeds.map { medication in
                        return "\(medication.name) (\(medication.dosage) • \(medication.frequency))"
                    }
                    drawList(medsList, y: &yOffset, margin: margin + 8, width: contentWidth)
                }
                
                // Physician Notes
                if yOffset > 660 { context.beginPage(); yOffset = 40 }
                drawPhysicianNotesBox(y: &yOffset, margin: margin, width: contentWidth)
                
                // Footer
                drawFooter(contextWidth: contentWidth, margin: margin)
            }
            return tempURL
        } catch {
            print("Could not create Condition PDF: \(error)")
            return nil
        }
    }
    
    private func getCurrentValue(for metricName: String, healthMetrics: HealthMetrics?) -> String {
        guard let metrics = healthMetrics else { return "N/A" }
        switch metricName {
        case "Heart Rate":
            return metrics.heartRate != nil ? "\(Int(metrics.heartRate!)) BPM" : "N/A"
        case "Resting Heart Rate":
            return metrics.restingHeartRate != nil ? "\(Int(metrics.restingHeartRate!)) BPM" : "N/A"
        case "Blood Pressure":
            if let bp = metrics.bloodPressure {
                return "\(Int(bp.systolic))/\(Int(bp.diastolic))"
            }
            return "N/A"
        case "Oxygen Saturation":
            return metrics.oxygenSaturation != nil ? "\(Int(metrics.oxygenSaturation! * 100))%" : "N/A"
        case "Body Weight":
            return metrics.bodyMass != nil ? String(format: "%.1f kg", metrics.bodyMass!) : "N/A"
        case "Steps":
            return metrics.steps != nil ? "\(metrics.steps!)" : "N/A"
        case "Respiratory Rate":
            return metrics.respiratoryRate != nil ? String(format: "%.1f br/min", metrics.respiratoryRate!) : "N/A"
        default:
            return "N/A"
        }
    }
    
    private func drawPatientBanner(y: inout CGFloat, margin: CGFloat, width: CGFloat) {
        let bannerRect = CGRect(x: margin, y: y, width: width, height: 50)
        let bannerPath = UIBezierPath(roundedRect: bannerRect, cornerRadius: 6)
        UIColor.systemIndigo.withAlphaComponent(0.05).setFill()
        bannerPath.fill()
        
        let borderPath = UIBezierPath(roundedRect: bannerRect, cornerRadius: 6)
        UIColor.systemIndigo.withAlphaComponent(0.15).setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()
        
        let boldFont = UIFont.boldSystemFont(ofSize: 9)
        let regularFont = UIFont.systemFont(ofSize: 9)
        
        let labelAttr: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: UIColor.secondaryLabel]
        let valAttr: [NSAttributedString.Key: Any] = [.font: regularFont, .foregroundColor: UIColor.label]
        
        // Draw patient details columns
        "PATIENT:".draw(at: CGPoint(x: margin + 12, y: y + 10), withAttributes: labelAttr)
        "Nessa User".draw(at: CGPoint(x: margin + 12, y: y + 26), withAttributes: valAttr)
        
        "RECORD ID:".draw(at: CGPoint(x: margin + 130, y: y + 10), withAttributes: labelAttr)
        "NSA-2026-098".draw(at: CGPoint(x: margin + 130, y: y + 26), withAttributes: valAttr)
        
        "REPORT TYPE:".draw(at: CGPoint(x: margin + 240, y: y + 10), withAttributes: labelAttr)
        "7-Day Trend Analysis".draw(at: CGPoint(x: margin + 240, y: y + 26), withAttributes: valAttr)
        
        "CLINICAL SIGN-OFF:".draw(at: CGPoint(x: margin + 370, y: y + 10), withAttributes: labelAttr)
        "__________________".draw(at: CGPoint(x: margin + 370, y: y + 26), withAttributes: valAttr)
        
        y += 65
    }
    
    private func drawGridOfVitals(
        metrics: HealthMetrics?,
        sevenDayMetrics: SevenDayHealthMetrics?,
        y: inout CGFloat,
        margin: CGFloat,
        width: CGFloat
    ) {
        guard let current = metrics else { return }
        
        drawSectionTitle("Clinical Biometric Baseline Summary", y: &y, margin: margin)
        
        let cellWidth = (width - 15) / 2
        let cellHeight: CGFloat = 45
        
        struct VitalItem {
            let label: String
            let value: String
            let reference: String
            let color: UIColor
        }
        
        let avgHRV = sevenDayMetrics?.avgHeartRateVariability.map { String(format: "%.0f ms", $0) } ?? "N/A"
        let avgRHR = sevenDayMetrics?.avgRestingHeartRate.map { String(format: "%.0f BPM", $0) } ?? "N/A"
        let avgSleep = sevenDayMetrics?.avgSleepDuration.map { String(format: "%.1f hrs", $0) } ?? "N/A"
        
        let vitals = [
            VitalItem(label: "Heart Rate (Current)", value: current.heartRate.map { String(format: "%.0f BPM", $0) } ?? "N/A", reference: "Normal: 60-100 BPM", color: .systemRed),
            VitalItem(label: "Resting Heart Rate", value: current.restingHeartRate.map { String(format: "%.0f BPM", $0) } ?? "N/A", reference: "7d Avg: \(avgRHR)", color: .systemPink),
            VitalItem(label: "Heart Rate Variability", value: current.heartRateVariability.map { String(format: "%.0f ms", $0) } ?? "N/A", reference: "7d Avg: \(avgHRV)", color: .systemPurple),
            VitalItem(label: "Oxygen Saturation", value: current.oxygenSaturation.map { String(format: "%.1f%%", $0 * 100) } ?? "N/A", reference: "Normal: 95-100%", color: .systemBlue),
            VitalItem(label: "Sleep Duration", value: current.sleepAnalysis.map { samples in
                let total = samples.filter { $0.sleepType != .inBed && $0.sleepType != .awake }.reduce(0.0) { $0 + $1.duration }
                return String(format: "%.1f hrs", total / 3600.0)
            } ?? "N/A", reference: "7d Avg: \(avgSleep)", color: .systemTeal),
            VitalItem(label: "Respiratory Rate", value: current.respiratoryRate.map { String(format: "%.1f br/min", $0) } ?? "N/A", reference: "Normal: 12-20 bpm", color: .systemGreen)
        ]
        
        let boldFont = UIFont.boldSystemFont(ofSize: 9)
        let regularFont = UIFont.systemFont(ofSize: 11)
        let smallFont = UIFont.systemFont(ofSize: 8)
        
        for (index, vital) in vitals.enumerated() {
            let row = CGFloat(index / 2)
            let col = CGFloat(index % 2)
            
            let x = margin + col * (cellWidth + 15)
            let cellY = y + row * (cellHeight + 10)
            
            let cellRect = CGRect(x: x, y: cellY, width: cellWidth, height: cellHeight)
            let cellPath = UIBezierPath(roundedRect: cellRect, cornerRadius: 6)
            UIColor.systemGray6.withAlphaComponent(0.6).setFill()
            cellPath.fill()
            
            let borderPath = UIBezierPath(roundedRect: cellRect, cornerRadius: 6)
            UIColor.separator.withAlphaComponent(0.4).setStroke()
            borderPath.lineWidth = 0.5
            borderPath.stroke()
            
            let circleRect = CGRect(x: x + 8, y: cellY + 18, width: 6, height: 6)
            let circlePath = UIBezierPath(ovalIn: circleRect)
            vital.color.setFill()
            circlePath.fill()
            
            vital.label.draw(at: CGPoint(x: x + 8, y: cellY + 6), withAttributes: [.font: boldFont, .foregroundColor: UIColor.secondaryLabel])
            vital.value.draw(at: CGPoint(x: x + 18, y: cellY + 16), withAttributes: [.font: regularFont, .foregroundColor: UIColor.label])
            vital.reference.draw(at: CGPoint(x: x + 8, y: cellY + 32), withAttributes: [.font: smallFont, .foregroundColor: UIColor.tertiaryLabel])
        }
        
        y += CGFloat((vitals.count + 1) / 2) * (cellHeight + 10) + 15
    }
    
    private func drawPhysicianNotesBox(y: inout CGFloat, margin: CGFloat, width: CGFloat) {
        drawSectionTitle("Physician Notes & Recommendations", y: &y, margin: margin)
        
        let boxRect = CGRect(x: margin, y: y, width: width, height: 80)
        let boxPath = UIBezierPath(rect: boxRect)
        UIColor.systemBackground.setFill()
        boxPath.fill()
        
        let borderPath = UIBezierPath(rect: boxRect)
        UIColor.separator.setStroke()
        borderPath.lineWidth = 0.75
        borderPath.stroke()
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        "Notes:".draw(at: CGPoint(x: margin + 8, y: y + 6), withAttributes: attributes)
        
        let lineY1 = y + 25
        let lineY2 = y + 45
        let lineY3 = y + 65
        
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin + 8, y: lineY1))
        path.addLine(to: CGPoint(x: margin + width - 8, y: lineY1))
        path.move(to: CGPoint(x: margin + 8, y: lineY2))
        path.addLine(to: CGPoint(x: margin + width - 8, y: lineY2))
        path.move(to: CGPoint(x: margin + 8, y: lineY3))
        path.addLine(to: CGPoint(x: margin + width - 8, y: lineY3))
        
        let dashes: [CGFloat] = [2, 3]
        path.setLineDash(dashes, count: dashes.count, phase: 0)
        UIColor.separator.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        
        y += 95
    }
    
    private func drawSectionTitle(_ title: String, y: inout CGFloat, margin: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.label
        ]
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: attributes)
        y += 22
        
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: 595.2 - margin, y: y))
        UIColor.separator.setStroke()
        path.lineWidth = 0.75
        path.stroke()
        y += 12
    }
    
    private func drawSubHeader(_ title: String, y: inout CGFloat, margin: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.secondaryLabel
        ]
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: attributes)
        y += 15
    }
    
    private func drawList(_ items: [String], y: inout CGFloat, margin: CGFloat, width: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        for item in items {
            let bulletItem = "• \(item)"
            let rect = bulletItem.boundingRect(with: CGSize(width: width, height: 1000), options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
            bulletItem.draw(in: CGRect(x: margin, y: y, width: width, height: rect.height), withAttributes: attributes)
            y += rect.height + 4
        }
        y += 8
    }
    
    private func drawFooter(contextWidth: CGFloat, margin: CGFloat) {
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.lightGray
        ]
        let footerText = "Nessa Clinical PDF Report. For informational purposes only. Consult a healthcare professional."
        let footerRect = CGRect(x: margin, y: 841.8 - 30, width: contextWidth, height: 20)
        footerText.draw(in: footerRect, withAttributes: footerAttributes)
    }
}
