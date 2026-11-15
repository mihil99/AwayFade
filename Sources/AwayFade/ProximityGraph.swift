import AwayFadeCore
import SwiftUI

struct ProximityGraph: View {
    let bands: [ProximityBand]
    let liveRSSI: Double?
    let activeBandIndex: Int?
    @Binding var selectedBandID: Int?
    let moveBand: (_ id: Int, _ anchorRSSI: Double, _ volumeMultiplier: Double) -> Void

    @State private var draggedBandIndex: Int?

    private let signalNear = -30.0
    private let signalFar = -95.0

    var body: some View {
        GeometryReader { geometry in
            let plot = CGRect(x: 8, y: 18, width: geometry.size.width - 16, height: geometry.size.height - 36)
            Canvas { context, _ in
                drawGrid(context: &context, plot: plot)
                drawCurve(context: &context, plot: plot)
                drawLiveReading(context: &context, plot: plot)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        dragPoint(at: value.location, in: plot)
                    }
                    .onEnded { _ in
                        draggedBandIndex = nil
                    }
            )
            .help("Drag a curve point left or right for signal, and up or down for volume")
            .overlay(alignment: .bottom) {
                HStack {
                    Text("Near")
                    Spacer()
                    Text("Far")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            }
        }
        .frame(height: 146)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Proximity volume graph")
        .accessibilityValue(accessibilitySummary)
    }

    private func drawGrid(context: inout GraphicsContext, plot: CGRect) {
        for fraction in [0.0, 0.5, 1.0] {
            let y = plot.minY + plot.height * fraction
            var path = Path()
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(path, with: .color(.secondary.opacity(0.16)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
    }

    private func drawCurve(context: inout GraphicsContext, plot: CGRect) {
        guard !bands.isEmpty else { return }
        var path = Path()
        let sampleCount = 120
        for sample in 0 ... sampleCount {
            let fraction = Double(sample) / Double(sampleCount)
            let rssi = signalNear + (signalFar - signalNear) * fraction
            let point = CGPoint(
                x: plot.minX + plot.width * fraction,
                y: y(for: ProximityLogic.volumeMultiplier(for: rssi, bands: bands), in: plot)
            )
            if sample == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, lineJoin: .round))

        for (index, band) in bands.enumerated() {
            let isSelected = selectedBandID == band.id
            let isDragged = draggedBandIndex == index
            let diameter = isDragged || isSelected ? 12.0 : 9.0
            let pointX = x(for: band.anchorRSSI, in: plot)
            let pointY = y(for: band.volumeMultiplier, in: plot)
            let point = CGRect(
                x: pointX - diameter / 2,
                y: pointY - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.fill(Path(ellipseIn: point), with: .color(.accentColor))
            context.stroke(Path(ellipseIn: point), with: .color(.white), lineWidth: 2)

            let putLabelBelow = pointY < plot.minY + 18
            let label = Text(band.name.isEmpty ? "Point" : band.name)
                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .accentColor : .secondary)
            context.draw(
                label,
                at: CGPoint(x: pointX, y: pointY + (putLabelBelow ? 9 : -9)),
                anchor: putLabelBelow ? .top : .bottom
            )
        }
    }

    private func drawLiveReading(context: inout GraphicsContext, plot: CGRect) {
        guard let liveRSSI else { return }
        let liveX = x(for: liveRSSI, in: plot)
        var line = Path()
        line.move(to: CGPoint(x: liveX, y: plot.minY))
        line.addLine(to: CGPoint(x: liveX, y: plot.maxY))
        context.stroke(line, with: .color(.primary.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

        if activeBandIndex != nil {
            let liveVolume = ProximityLogic.volumeMultiplier(for: liveRSSI, bands: bands)
            let point = CGRect(
                x: liveX - 5,
                y: y(for: liveVolume, in: plot) - 5,
                width: 10,
                height: 10
            )
            context.fill(Path(ellipseIn: point), with: .color(.accentColor))
            context.stroke(Path(ellipseIn: point.insetBy(dx: -2, dy: -2)), with: .color(.white), lineWidth: 2)
        }
    }

    private func x(for rssi: Double, in plot: CGRect) -> CGFloat {
        let fraction = min(max((signalNear - rssi) / (signalNear - signalFar), 0), 1)
        return plot.minX + plot.width * fraction
    }

    private func y(for volume: Double, in plot: CGRect) -> CGFloat {
        plot.maxY - plot.height * min(max(volume, 0), 1)
    }

    private func dragPoint(at location: CGPoint, in plot: CGRect) {
        if draggedBandIndex == nil {
            draggedBandIndex = bands.indices.min { lhs, rhs in
                distance(from: location, toBandAt: lhs, in: plot)
                    < distance(from: location, toBandAt: rhs, in: plot)
            }.flatMap { distance(from: location, toBandAt: $0, in: plot) <= 22 ? $0 : nil }
        }

        guard let index = draggedBandIndex, bands.indices.contains(index) else { return }
        selectedBandID = bands[index].id
        let xFraction = min(max((location.x - plot.minX) / plot.width, 0), 1)
        let yFraction = min(max((plot.maxY - location.y) / plot.height, 0.1), 1)
        let rssi = signalNear + (signalFar - signalNear) * Double(xFraction)
        moveBand(bands[index].id, rssi, Double(yFraction))
    }

    private func distance(from location: CGPoint, toBandAt index: Int, in plot: CGRect) -> CGFloat {
        let band = bands[index]
        let dx = location.x - x(for: band.anchorRSSI, in: plot)
        let dy = location.y - y(for: band.volumeMultiplier, in: plot)
        return sqrt(dx * dx + dy * dy)
    }

    private var accessibilitySummary: String {
        guard let activeBandIndex, bands.indices.contains(activeBandIndex) else { return "No signal reading" }
        let band = bands[activeBandIndex]
        let volume = liveRSSI.map { ProximityLogic.volumeMultiplier(for: $0, bands: bands) }
            ?? band.volumeMultiplier
        return "Current level \(band.name), volume \(Int((volume * 100).rounded())) percent"
    }
}
