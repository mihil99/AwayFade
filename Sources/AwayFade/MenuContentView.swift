import AppKit
import AwayFadeCore
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tuningExpanded = false
    @State private var testingExpanded = false
    @State private var selectedBandID: Int?
    @State private var editingBandID: Int?
    @FocusState private var focusedBandID: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                statusCard
                graphCard
                levelEditor
                testingSection
                footer
            }
            .padding(16)
        }
        .frame(width: 410, height: 680)
        .background(.regularMaterial)
        .onChange(of: focusedBandID) { oldValue, newValue in
            if oldValue != nil, newValue == nil {
                editingBandID = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "airpodspro")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("AwayFade")
                        .font(.headline)
                    Text("v\(appVersion)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("Let audio recede as you walk away")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Fading", isOn: Binding(
                get: { model.isEnabled },
                set: { model.setEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.devices.isEmpty {
                Label("No connected Bluetooth headphones", systemImage: "airpodspro.chargingcase.wireless")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Headphones", selection: $model.selectedDeviceID) {
                    ForEach(model.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
            }

            HStack {
                Label(model.statusMessage, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                Spacer()
                if let rssi = model.smoothedRSSI {
                    Text(model.sensorSource)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(model.sensorSource == "Live" ? .green : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Text("\(Int(rssi.rounded())) dBm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Text("Output:")
                    .foregroundStyle(.secondary)
                Text(model.outputName)
                    .lineLimit(1)
                Spacer()
                if let baseline = model.baselinePercent {
                    Text("Reference \(baseline)%")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if let message = model.calibrationMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(message)
                        .font(.caption)
                    Spacer()
                    Button("Cancel") { model.cancelCalibration() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                .padding(8)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var graphCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Volume by proximity")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let index = model.activeBandIndex, model.bands.indices.contains(index) {
                    Text(model.bands[index].name)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
                Button {
                    let removedID = selectedBandID
                    if let id = model.removeCurvePoint(id: selectedBandID ?? -1) {
                        selectedBandID = id
                        if editingBandID == removedID {
                            editingBandID = nil
                            focusedBandID = nil
                        }
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .help("Remove the selected point")
                .disabled(selectedBand == nil || model.bands.count <= 2 || model.calibrationMessage != nil)

                Button {
                    selectedBandID = model.addCurvePoint()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a point in the widest gap")
                .disabled(model.bands.count >= 8)
            }
            ProximityGraph(
                bands: model.bands,
                liveRSSI: model.controlRSSI ?? model.smoothedRSSI,
                activeBandIndex: model.activeBandIndex,
                selectedBandID: $selectedBandID,
                moveBand: { id, anchor, volume in
                    model.updateBandPoint(id: id, anchorRSSI: anchor, volumeMultiplier: volume)
                }
            )
            Text("Drag points to shape the curve; rename and fine-tune them in Point details")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    private var levelEditor: some View {
        DisclosureGroup(isExpanded: $tuningExpanded) {
            VStack(spacing: 12) {
                ForEach(model.bands) { band in
                    bandRow(id: band.id)
                    if band.id != model.bands.last?.id { Divider() }
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Label("Point details", systemImage: "slider.horizontal.3")
                Spacer()
                Text("\(model.bands.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(12)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func bandRow(id: Int) -> some View {
        if let band = model.curvePoint(id: id) {
        VStack(spacing: 7) {
            HStack {
                Circle()
                    .fill(model.activeBandID == id ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
                if editingBandID == id {
                    TextField("Point label", text: Binding(
                        get: { model.curvePoint(id: id)?.name ?? "" },
                        set: { model.renameCurvePoint(id: id, name: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: 150)
                    .focused($focusedBandID, equals: id)
                    .onSubmit { finishEditingLabel() }
                } else {
                    Button {
                        selectedBandID = id
                        editingBandID = id
                        Task { @MainActor in focusedBandID = id }
                    } label: {
                        HStack(spacing: 4) {
                            Text(band.name.isEmpty ? "Point" : band.name)
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .help("Click to rename this point")
                }
                Spacer()
                Text("\(Int((band.volumeMultiplier * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.1")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { model.curvePoint(id: id)?.volumeMultiplier ?? band.volumeMultiplier },
                        set: { model.updateBandVolume(id: id, value: $0) }
                    ),
                    in: 0.1 ... 1
                )
                Image(systemName: "speaker.wave.3")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("Signal anchor")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { model.curvePoint(id: id)?.anchorRSSI ?? band.anchorRSSI },
                        set: { model.updateBandAnchor(id: id, value: $0) }
                    ),
                    in: model.anchorRange(forID: id),
                    step: 1
                )
                Text("\(Int(band.anchorRSSI))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
                Button("Calibrate") { model.startCalibration(forID: id) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(model.calibrationMessage != nil || (!model.selectedDeviceConnected && !model.simulationEnabled))
            }
        }
        }
    }

    private var testingSection: some View {
        DisclosureGroup("Testing", isExpanded: $testingExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use simulated signal", isOn: $model.simulationEnabled)
                if model.simulationEnabled {
                    HStack {
                        Text("Near")
                        Slider(
                            value: Binding(
                                get: { ProximityLogic.simulationSliderValue(forRSSI: model.simulatedRSSI) },
                                set: { model.simulatedRSSI = ProximityLogic.rssi(forSimulationSliderValue: $0) }
                            ),
                            in: 30 ... 95
                        )
                        Text("Far")
                    }
                    .font(.caption)
                    Text(model.isEnabled
                         ? "The simulated level and volume change immediately."
                         : "The graph changes immediately. Turn on Fading above to hear volume changes.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .font(.subheadline.weight(.semibold))
        .padding(12)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack {
            Button("Reset levels") { model.resetConfiguration() }
            if model.isEnabled {
                Button("Use current volume as reference") { model.captureCurrentVolumeAsReference() }
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .font(.caption)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var selectedBand: ProximityBand? {
        guard let selectedBandID else { return nil }
        return model.curvePoint(id: selectedBandID)
    }

    private func finishEditingLabel() {
        editingBandID = nil
        focusedBandID = nil
    }

    private var statusIcon: String {
        if model.isEnabled && model.outputMatchesSelection { return "wave.3.right.circle.fill" }
        if !model.selectedDeviceConnected { return "exclamationmark.circle" }
        return "circle.fill"
    }

    private var statusColor: Color {
        if model.isEnabled && model.outputMatchesSelection { return .green }
        if !model.selectedDeviceConnected { return .orange }
        return .secondary
    }
}
