import WidgetKit
import SwiftUI

struct WidgetData: Codable {
    let lastUpdated: Date
    let priorityMetrics: [WidgetMetric]
    let sleepReadiness: String
    let sleepReadinessIcon: String
    let topCondition: String?
}

struct WidgetMetric: Codable, Identifiable {
    var id: String { name }
    let name: String
    let value: String
    let unit: String
    let healthyRange: String
    let color: String
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), data: getPlaceholderData())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), data: getSavedData() ?? getPlaceholderData())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let savedData = getSavedData() ?? getPlaceholderData()
        let entry = SimpleEntry(date: Date(), data: savedData)
        
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func getSavedData() -> WidgetData? {
        let appGroupIdentifier = "group.com.wellnessai.nessa"
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
              let encoded = sharedDefaults.data(forKey: "widgetData") else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetData.self, from: encoded)
    }
    
    private func getPlaceholderData() -> WidgetData {
        WidgetData(
            lastUpdated: Date(),
            priorityMetrics: [
                WidgetMetric(name: "Resting Heart Rate", value: "68 BPM", unit: "", healthyRange: "60-100 BPM", color: "red"),
                WidgetMetric(name: "Heart Rate Variability", value: "48.5 ms", unit: "", healthyRange: "20-100 ms", color: "green")
            ],
            sleepReadiness: "Optimal",
            sleepReadinessIcon: "moon.zzz.fill",
            topCondition: "Hypertension"
        )
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct SmallWidgetView: View {
    let data: WidgetData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.indigo)
                Text("Nessa AI")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
            }
            
            if let metric = data.priorityMetrics.first {
                Spacer(minLength: 0)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Metric Icon + Related condition label
                    HStack(spacing: 6) {
                        Image(systemName: getIcon(for: metric.name))
                            .font(.caption2)
                            .foregroundColor(getMetricColor(metric.color))
                            .frame(width: 18, height: 18)
                            .background(getMetricColor(metric.color).opacity(0.15))
                            .clipShape(Circle())
                        
                        Text(data.topCondition ?? "General Health")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    
                    Text(metric.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .padding(.top, 2)
                    
                    Text(metric.value)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.vertical, 1)
                    
                    Text("Range: \(metric.healthyRange)")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
            } else {
                Spacer()
                Text("No priority metrics logged.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Spacer()
            }
            
            // Footer (Last Updated)
            Text("Updated \(formattedTime(data.lastUpdated))")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(12)
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct MediumWidgetView: View {
    let data: WidgetData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: Nessa AI title + Sleep Readiness status
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundColor(.indigo)
                    Text("Nessa AI")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Sleep Readiness status pill
                HStack(spacing: 4) {
                    Image(systemName: data.sleepReadinessIcon)
                        .font(.system(size: 10))
                        .foregroundColor(.indigo)
                    Text("Sleep: \(data.sleepReadiness)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.indigo.opacity(0.2))
                .cornerRadius(8)
            }
            .padding(.bottom, 2)
            
            // Priority Metrics Grid (up to 2 columns)
            HStack(spacing: 12) {
                if data.priorityMetrics.isEmpty {
                    Spacer()
                    Text("No priority metrics logged.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                } else {
                    ForEach(data.priorityMetrics) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Image(systemName: getIcon(for: metric.name))
                                    .font(.caption2)
                                    .foregroundColor(getMetricColor(metric.color))
                                    .frame(width: 20, height: 20)
                                    .background(getMetricColor(metric.color).opacity(0.15))
                                    .clipShape(Circle())
                                
                                Text(metric.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            
                            Text(metric.value)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.vertical, 1)
                            
                            Text("Range: \(metric.healthyRange)")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(getMetricColor(metric.color).opacity(0.15), lineWidth: 1)
                        )
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            // Footer with Condition Summary & Last Updated
            HStack {
                if let condition = data.topCondition {
                    Text("Focus: \(condition)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    Text("General Wellness")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                Text("Updated \(formattedTime(data.lastUpdated))")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(12)
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Global helpers for rendering
func getIcon(for name: String) -> String {
    switch name {
    case "Heart Rate": return "heart.fill"
    case "Resting Heart Rate": return "heart.fill"
    case "Heart Rate Variability": return "waveform.path.ecg"
    case "Oxygen Saturation": return "drop.fill"
    case "Respiratory Rate": return "wind"
    case "Steps": return "figure.walk"
    case "Sleep Duration": return "moon.fill"
    case "Wrist Temperature": return "thermometer.medium"
    case "Time in Daylight": return "sun.max.fill"
    case "Stress Level": return "brain"
    case "Mood": return "face.smiling.fill"
    case "Body Weight": return "scalemass.fill"
    case "BMI": return "scalemass"
    default: return "heart.text.square.fill"
    }
}

func getMetricColor(_ colorName: String) -> Color {
    switch colorName.lowercased() {
    case "red": return .red
    case "green": return .green
    case "blue": return .blue
    case "orange": return .orange
    case "purple": return .purple
    case "yellow": return .yellow
    case "indigo": return .indigo
    case "teal": return .teal
    default: return .blue
    }
}

struct ContainerBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 10/255, green: 14/255, blue: 27/255), Color(red: 22/255, green: 27/255, blue: 45/255)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack {
                HStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.12))
                        .frame(width: 130, height: 130)
                        .blur(radius: 35)
                        .offset(x: -15, y: -15)
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

struct Wellness_AI_WidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(data: entry.data)
            case .systemMedium:
                MediumWidgetView(data: entry.data)
            default:
                SmallWidgetView(data: entry.data)
            }
        }
        .containerBackground(for: .widget) {
            ContainerBackgroundView()
        }
    }
}

@main
struct Wellness_AI_Widget: Widget {
    let kind: String = "Wellness_AI_Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            Wellness_AI_WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Nessa Health")
        .description("Track your priority health focus metrics at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
