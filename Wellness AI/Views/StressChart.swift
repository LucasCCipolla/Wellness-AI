import SwiftUI

struct StressChart: View {
    let points: [StressDataPoint]
    @State private var selectedPointId: UUID? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if points.isEmpty {
                NoDataView()
            } else {
                let sortedPoints = points.sorted { $0.timestamp < $1.timestamp }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { proxy in
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(sortedPoints) { point in
                                BarView(
                                    point: point,
                                    isSelected: selectedPointId == point.id,
                                    maxHeight: 100
                                )
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        if selectedPointId == point.id {
                                            selectedPointId = nil
                                        } else {
                                            selectedPointId = point.id
                                        }
                                    }
                                }
                                .id(point.id)
                            }
                        }
                        .frame(minHeight: 130, alignment: .bottom)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                        .onAppear {
                            if let lastId = sortedPoints.last?.id {
                                proxy.scrollTo(lastId, anchor: .trailing)
                            }
                        }
                    }
                }
                .frame(height: 130)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground).opacity(0.5))
                )
            }
        }
    }
}

struct BarView: View {
    let point: StressDataPoint
    let isSelected: Bool
    let maxHeight: CGFloat
    
    private var barColor: Color {
        switch point.stressScore {
        case 0..<30: return .green
        case 30..<50: return .blue
        case 50..<70: return .orange
        case 70...100: return .red
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            if isSelected {
                Text("\(Int(point.stressScore))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(barColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(barColor.opacity(0.1))
                    .cornerRadius(4)
                    .transition(.scale.combined(with: .opacity))
            }
            
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? barColor : barColor.opacity(0.7))
                .frame(width: 22, height: max(6, CGFloat(point.stressScore / 100.0) * maxHeight))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
            
            Text(point.timeLabel.components(separatedBy: ":").first ?? "")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
    }
}

struct NoDataView: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("No stress data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Spacer()
        }
        .frame(height: 120)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground).opacity(0.5)))
    }
}
