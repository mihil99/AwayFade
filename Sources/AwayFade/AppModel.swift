import AppKit
import AwayFadeCore
import Combine
import CoreAudio
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var devices: [BluetoothDeviceInfo] = []
    @Published var selectedDeviceID: String {
        didSet { defaults.set(selectedDeviceID, forKey: Keys.selectedDevice) }
    }
    @Published private(set) var rawRSSI: Int?
    @Published private(set) var smoothedRSSI: Double?
    @Published private(set) var controlRSSI: Double?
    @Published private(set) var activeBandIndex: Int?
    @Published private(set) var outputName = "No audio output"
    @Published private(set) var statusMessage = "Choose your AirPods to begin"
    @Published private(set) var sensorSource = "Waiting"
    @Published var bands: [ProximityBand] {
        didSet { persistBands() }
    }
    @Published var simulationEnabled = false {
        didSet { simulationModeChanged() }
    }
    @Published var simulatedRSSI = -56.0 {
        didSet {
            if simulationEnabled { applySimulationImmediately() }
        }
    }
    @Published private(set) var calibrationMessage: String?
    @Published private(set) var baselinePercent: Int?

    private enum Keys {
        static let selectedDevice = "selectedDevice"
        static let bands = "bands"
    }

    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "local.awayfade.app", category: "Sensor")
    private let bluetooth = BluetoothMonitor()
    private let volume = SystemVolumeController()
    private var pollTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var calibrationTask: Task<Void, Never>?
    private var signalHistory: [Double] = []
    private var pollCount = 0
    private var pendingBand: Int?
    private var pendingBandSamples = 0
    private var pendingControlDirection = 0
    private var pendingControlSamples = 0
    private var baselineDeviceID: AudioDeviceID?
    private var baselineVolume: Float?

    init() {
        selectedDeviceID = defaults.string(forKey: Keys.selectedDevice) ?? ""
        if let data = defaults.data(forKey: Keys.bands),
           let saved = try? JSONDecoder().decode([ProximityBand].self, from: data),
           (2 ... 8).contains(saved.count) {
            bands = saved
        } else {
            bands = ProximityBand.defaults
        }

        refreshDevices()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard !Task.isCancelled, let self else { break }
                await poll()
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    deinit {
        pollTask?.cancel()
        fadeTask?.cancel()
        calibrationTask?.cancel()
    }

    var selectedDeviceName: String? {
        devices.first(where: { $0.id == selectedDeviceID })?.name
    }

    var selectedDeviceConnected: Bool {
        selectedDeviceName != nil
    }

    var outputMatchesSelection: Bool {
        guard let selectedDeviceName else { return false }
        let output = normalized(outputName)
        let selected = normalized(selectedDeviceName)
        return output == selected || output.contains(selected) || selected.contains(output)
            || (output.contains("airpods") && selected.contains("airpods"))
    }

    var activeBandID: Int? {
        guard let activeBandIndex, bands.indices.contains(activeBandIndex) else { return nil }
        return bands[activeBandIndex].id
    }

    func curvePoint(id: Int) -> ProximityBand? {
        bands.first(where: { $0.id == id })
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard selectedDeviceConnected else {
                statusMessage = "Connect and select your AirPods first"
                return
            }
            guard outputMatchesSelection else {
                statusMessage = "Make the selected AirPods the Mac’s audio output"
                return
            }
            guard let output = volume.defaultOutput() else {
                statusMessage = "This audio output does not expose volume control"
                return
            }

            baselineDeviceID = output.id
            baselineVolume = output.volume
            baselinePercent = Int((output.volume * 100).rounded())
            isEnabled = true
            statusMessage = "Fading is active"
            applyProximityVolume()
        } else {
            isEnabled = false
            restoreBaseline()
            statusMessage = "Fading is off"
        }
    }

    func updateBandVolume(index: Int, value: Double) {
        guard bands.indices.contains(index) else { return }
        bands[index].volumeMultiplier = min(max(value, 0.1), 1)
        applyProximityVolume()
    }

    func updateBandVolume(id: Int, value: Double) {
        guard let index = bands.firstIndex(where: { $0.id == id }) else { return }
        updateBandVolume(index: index, value: value)
    }

    func updateBandAnchor(index: Int, value: Double) {
        guard ProximityLogic.validAnchor(value, at: index, in: bands) else { return }
        bands[index].anchorRSSI = value
        reevaluateBandImmediately()
    }

    func updateBandAnchor(id: Int, value: Double) {
        guard let index = bands.firstIndex(where: { $0.id == id }) else { return }
        updateBandAnchor(index: index, value: value)
    }

    func updateBandPoint(index: Int, anchorRSSI: Double, volumeMultiplier: Double) {
        guard bands.indices.contains(index) else { return }
        let range = anchorRange(for: index)
        bands[index].anchorRSSI = min(max(anchorRSSI, range.lowerBound), range.upperBound)
        bands[index].volumeMultiplier = min(max(volumeMultiplier, 0.1), 1)
        reevaluateBandImmediately()
    }

    func updateBandPoint(id: Int, anchorRSSI: Double, volumeMultiplier: Double) {
        guard let index = bands.firstIndex(where: { $0.id == id }) else { return }
        updateBandPoint(index: index, anchorRSSI: anchorRSSI, volumeMultiplier: volumeMultiplier)
    }

    @discardableResult
    func addCurvePoint() -> Int? {
        guard bands.count < 8 else { return nil }

        var slots: [(index: Int, upper: Double, lower: Double)] = []
        if let first = bands.first {
            slots.append((0, -30, first.anchorRSSI))
        }
        for index in 0 ..< bands.count - 1 {
            slots.append((index + 1, bands[index].anchorRSSI, bands[index + 1].anchorRSSI))
        }
        if let last = bands.last {
            slots.append((bands.count, last.anchorRSSI, -95))
        }

        guard let slot = slots
            .filter({ $0.upper - $0.lower >= 8 })
            .max(by: { ($0.upper - $0.lower) < ($1.upper - $1.lower) })
        else { return nil }

        let anchor = (slot.upper + slot.lower) / 2
        let volume = ProximityLogic.volumeMultiplier(for: anchor, bands: bands)
        let id = (bands.map(\.id).max() ?? -1) + 1
        bands.insert(
            ProximityBand(id: id, name: "Point \(id + 1)", anchorRSSI: anchor, volumeMultiplier: volume),
            at: slot.index
        )
        reevaluateBandImmediately()
        return id
    }

    @discardableResult
    func removeCurvePoint(id: Int) -> Int? {
        guard calibrationTask == nil,
              let index = bands.firstIndex(where: { $0.id == id }),
              let updated = ProximityLogic.removingPoint(id: id, from: bands)
        else { return nil }

        bands = updated
        reevaluateBandImmediately()
        return bands[min(index, bands.count - 1)].id
    }

    func renameCurvePoint(id: Int, name: String) {
        guard let index = bands.firstIndex(where: { $0.id == id }) else { return }
        bands[index].name = String(name.prefix(18))
    }

    func anchorRange(for index: Int) -> ClosedRange<Double> {
        guard bands.indices.contains(index) else { return -95 ... -30 }
        let lower = index < bands.count - 1 ? bands[index + 1].anchorRSSI + 4 : -95
        let upper = index > 0 ? bands[index - 1].anchorRSSI - 4 : -30
        return min(lower, upper) ... max(lower, upper)
    }

    func anchorRange(forID id: Int) -> ClosedRange<Double> {
        guard let index = bands.firstIndex(where: { $0.id == id }) else { return -95 ... -30 }
        return anchorRange(for: index)
    }

    func captureCurrentVolumeAsReference() {
        guard isEnabled,
              let rssi = controlRSSI ?? smoothedRSSI,
              let deviceID = baselineDeviceID,
              let current = volume.readVolume(deviceID: deviceID)
        else { return }

        let multiplier = Float(ProximityLogic.volumeMultiplier(for: rssi, bands: bands))
        baselineVolume = min(current / max(multiplier, 0.1), 1)
        baselinePercent = Int(((baselineVolume ?? current) * 100).rounded())
        statusMessage = "Reference volume updated"
    }

    func startCalibration(for index: Int) {
        guard bands.indices.contains(index), calibrationTask == nil else { return }
        calibrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for second in stride(from: 8, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                calibrationMessage = "Walk to the \(bands[index].name.lowercased()) position — sampling in \(second)s"
                try? await Task.sleep(for: .seconds(1))
            }

            NSSound.beep()
            calibrationMessage = "Hold still at the \(bands[index].name.lowercased()) position…"
            var samples: [Double] = []
            for _ in 0 ..< 8 {
                guard !Task.isCancelled else { return }
                if let sample = await currentSignalSample() { samples.append(sample) }
                try? await Task.sleep(for: .milliseconds(500))
            }

            if let measured = ProximityLogic.median(samples),
               ProximityLogic.validAnchor(measured, at: index, in: bands) {
                bands[index].anchorRSSI = measured
                calibrationMessage = "\(bands[index].name) calibrated at \(Int(measured.rounded())) dBm"
                NSSound(named: NSSound.Name("Glass"))?.play()
                reevaluateBandImmediately()
            } else if samples.isEmpty {
                calibrationMessage = "No usable Bluetooth reading—try again or use the slider"
            } else {
                calibrationMessage = "That reading overlaps another level—move farther and retry"
            }

            try? await Task.sleep(for: .seconds(4))
            calibrationMessage = nil
            calibrationTask = nil
        }
    }

    func startCalibration(forID id: Int) {
        guard let index = bands.firstIndex(where: { $0.id == id }) else { return }
        startCalibration(for: index)
    }

    func cancelCalibration() {
        calibrationTask?.cancel()
        calibrationTask = nil
        calibrationMessage = nil
    }

    func resetConfiguration() {
        bands = ProximityBand.defaults
        reevaluateBandImmediately()
    }

    private func poll() async {
        pollCount += 1
        if pollCount.isMultiple(of: 6) || devices.isEmpty { refreshDevices() }

        if let output = volume.defaultOutput() {
            outputName = output.name
        } else {
            outputName = "No controllable audio output"
        }

        guard let sample = await currentSignalSample() else {
            rawRSSI = nil
            smoothedRSSI = nil
            signalHistory.removeAll()
            controlRSSI = nil
            pendingBand = nil
            pendingBandSamples = 0
            pendingControlDirection = 0
            pendingControlSamples = 0
            if selectedDeviceConnected {
                statusMessage = simulationEnabled ? "Move the test signal slider" : "Bluetooth signal strength is unavailable"
            } else {
                statusMessage = devices.isEmpty ? "Connect your AirPods" : "Select connected headphones"
            }
            return
        }

        rawRSSI = Int(sample.rounded())
        signalHistory.append(sample)
        if signalHistory.count > 3 { signalHistory.removeFirst() }
        smoothedRSSI = ProximityLogic.median(signalHistory)
        updateBand()
        updateControlSignal()

        if isEnabled {
            statusMessage = outputMatchesSelection ? "Fading is active" : "Paused—the selected headphones are not the audio output"
        } else if simulationEnabled {
            statusMessage = "Testing the proximity levels"
        } else {
            statusMessage = "Ready"
        }
    }

    private func currentSignalSample() async -> Double? {
        if simulationEnabled {
            sensorSource = "Simulated"
            return simulatedRSSI
        }
        guard !selectedDeviceID.isEmpty else { return nil }

        if let reading = await SystemProfilerRSSIReader.read(address: selectedDeviceID) {
            sensorSource = "Live"
            logger.debug("Live RSSI sample: \(reading, privacy: .public) dBm")
            return Double(reading)
        }

        if let reading = bluetooth.rawRSSI(for: selectedDeviceID) {
            sensorSource = "Cached fallback"
            logger.warning("Live RSSI unavailable; using cached fallback")
            return Double(reading)
        }

        sensorSource = "Unavailable"
        logger.error("No RSSI source is available")
        return nil
    }

    private func simulationModeChanged() {
        signalHistory.removeAll()
        controlRSSI = nil
        pendingBand = nil
        pendingBandSamples = 0
        pendingControlDirection = 0
        pendingControlSamples = 0

        if simulationEnabled {
            applySimulationImmediately()
        } else {
            rawRSSI = nil
            smoothedRSSI = nil
            activeBandIndex = nil
            sensorSource = "Waiting"
            Task { @MainActor [weak self] in await self?.poll() }
        }
    }

    private func applySimulationImmediately() {
        let sample = simulatedRSSI
        rawRSSI = Int(sample.rounded())
        smoothedRSSI = sample
        controlRSSI = sample
        signalHistory = [sample]
        sensorSource = "Simulated"
        let newBand = ProximityLogic.idealBand(for: sample, bands: bands)
        let bandChanged = activeBandIndex != newBand
        activeBandIndex = newBand
        pendingBand = nil
        pendingBandSamples = 0
        statusMessage = isEnabled ? "Testing volume levels" : "Testing proximity levels"
        if bandChanged || isEnabled { applyProximityVolume() }
    }

    private func updateBand() {
        guard let rssi = smoothedRSSI else { return }
        guard let current = activeBandIndex else {
            activeBandIndex = ProximityLogic.idealBand(for: rssi, bands: bands)
            return
        }

        let suggested = ProximityLogic.hystereticBand(
            for: rssi,
            currentBand: current,
            bands: bands,
            margin: 2.5
        )
        guard suggested != current else {
            pendingBand = nil
            pendingBandSamples = 0
            return
        }

        if pendingBand == suggested {
            pendingBandSamples += 1
        } else {
            pendingBand = suggested
            pendingBandSamples = 1
        }

        guard pendingBandSamples >= 3 else { return }
        activeBandIndex = suggested
        pendingBand = nil
        pendingBandSamples = 0
    }

    private func updateControlSignal() {
        guard !simulationEnabled, let rssi = smoothedRSSI else { return }
        guard let current = controlRSSI else {
            controlRSSI = rssi
            applyProximityVolume()
            return
        }

        let delta = rssi - current
        let deadband = 2.0
        guard abs(delta) > deadband else {
            pendingControlDirection = 0
            pendingControlSamples = 0
            return
        }

        let direction = delta > 0 ? 1 : -1
        if pendingControlDirection == direction {
            pendingControlSamples += 1
        } else {
            pendingControlDirection = direction
            pendingControlSamples = 1
        }

        // Require two consecutive post-median readings in the same direction.
        guard pendingControlSamples >= 2 else { return }
        controlRSSI = rssi
        pendingControlDirection = 0
        pendingControlSamples = 0
        applyProximityVolume()
    }

    private func reevaluateBandImmediately() {
        guard let rssi = smoothedRSSI else { return }
        activeBandIndex = ProximityLogic.idealBand(for: rssi, bands: bands)
        pendingBand = nil
        pendingBandSamples = 0
        applyProximityVolume()
    }

    private func applyProximityVolume() {
        guard isEnabled,
              outputMatchesSelection,
              let rssi = controlRSSI ?? smoothedRSSI,
              let deviceID = baselineDeviceID,
              let baselineVolume,
              volume.defaultOutput()?.id == deviceID
        else { return }

        let multiplier = ProximityLogic.volumeMultiplier(for: rssi, bands: bands)
        let target = baselineVolume * Float(multiplier)
        fade(to: target, on: deviceID)
    }

    private func restoreBaseline() {
        guard let deviceID = baselineDeviceID, let baselineVolume else {
            clearBaseline()
            return
        }
        fade(to: baselineVolume, on: deviceID, clearBaselineAfter: true)
    }

    private func clearBaseline() {
        baselineDeviceID = nil
        baselineVolume = nil
        baselinePercent = nil
    }

    private func fade(
        to target: Float,
        on deviceID: AudioDeviceID,
        duration: TimeInterval = 1.6,
        clearBaselineAfter: Bool = false
    ) {
        fadeTask?.cancel()
        guard let start = volume.readVolume(deviceID: deviceID) else {
            if clearBaselineAfter { clearBaseline() }
            return
        }

        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let steps = max(1, Int(duration / 0.05))
            for step in 1 ... steps {
                guard !Task.isCancelled else { return }
                let progress = Double(step) / Double(steps)
                let eased = progress * progress * (3 - 2 * progress)
                let next = start + Float(eased) * (target - start)
                _ = self.volume.setVolume(next, deviceID: deviceID)
                try? await Task.sleep(for: .milliseconds(50))
            }
            if clearBaselineAfter { clearBaseline() }
            fadeTask = nil
        }
    }

    private func refreshDevices() {
        devices = bluetooth.connectedDevices()
        if selectedDeviceID.isEmpty || !devices.contains(where: { $0.id == selectedDeviceID }) {
            if let airPods = devices.first(where: { $0.name.localizedCaseInsensitiveContains("AirPods") }) {
                selectedDeviceID = airPods.id
            } else if selectedDeviceID.isEmpty, let first = devices.first {
                selectedDeviceID = first.id
            }
        }
    }

    private func persistBands() {
        guard let data = try? JSONEncoder().encode(bands) else { return }
        defaults.set(data, forKey: Keys.bands)
    }

    private func normalized(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'s", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
