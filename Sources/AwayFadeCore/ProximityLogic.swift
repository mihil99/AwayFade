import Foundation

public struct ProximityBand: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public var name: String
    public var anchorRSSI: Double
    public var volumeMultiplier: Double

    public init(id: Int, name: String, anchorRSSI: Double, volumeMultiplier: Double) {
        self.id = id
        self.name = name
        self.anchorRSSI = anchorRSSI
        self.volumeMultiplier = volumeMultiplier
    }

    public static let defaults: [ProximityBand] = [
        ProximityBand(id: 0, name: "Near", anchorRSSI: -42, volumeMultiplier: 1.00),
        ProximityBand(id: 1, name: "Room", anchorRSSI: -56, volumeMultiplier: 0.82),
        ProximityBand(id: 2, name: "Outside", anchorRSSI: -70, volumeMultiplier: 0.62),
        ProximityBand(id: 3, name: "Far", anchorRSSI: -84, volumeMultiplier: 0.42)
    ]
}

public enum ProximityLogic {
    /// Converts RSSI (-30 near … -95 far) to a left-to-right Near … Far slider value.
    public static func simulationSliderValue(forRSSI rssi: Double) -> Double {
        -rssi
    }

    public static func rssi(forSimulationSliderValue value: Double) -> Double {
        -value
    }

    public static func boundaries(for bands: [ProximityBand]) -> [Double] {
        guard bands.count > 1 else { return [] }
        return zip(bands, bands.dropFirst()).map { ($0.anchorRSSI + $1.anchorRSSI) / 2 }
    }

    public static func idealBand(for rssi: Double, bands: [ProximityBand]) -> Int {
        let thresholds = boundaries(for: bands)
        for (index, threshold) in thresholds.enumerated() where rssi >= threshold {
            return index
        }
        return max(0, bands.count - 1)
    }

    /// Treats each level as a point on a continuous curve. Smoothstep interpolation
    /// keeps the result continuous while easing into and out of every control point.
    public static func volumeMultiplier(for rssi: Double, bands: [ProximityBand]) -> Double {
        guard let first = bands.first, let last = bands.last else { return 1 }
        if rssi >= first.anchorRSSI { return first.volumeMultiplier }
        if rssi <= last.anchorRSSI { return last.volumeMultiplier }

        for index in 0 ..< bands.count - 1 {
            let near = bands[index]
            let far = bands[index + 1]
            guard rssi <= near.anchorRSSI, rssi >= far.anchorRSSI else { continue }

            let span = near.anchorRSSI - far.anchorRSSI
            guard span > 0 else { return near.volumeMultiplier }
            let progress = min(max((near.anchorRSSI - rssi) / span, 0), 1)
            let eased = progress * progress * (3 - 2 * progress)
            return near.volumeMultiplier
                + (far.volumeMultiplier - near.volumeMultiplier) * eased
        }

        return last.volumeMultiplier
    }

    public static func removingPoint(
        id: Int,
        from bands: [ProximityBand],
        minimumCount: Int = 2
    ) -> [ProximityBand]? {
        guard bands.count > minimumCount,
              let index = bands.firstIndex(where: { $0.id == id })
        else { return nil }

        var updated = bands
        updated.remove(at: index)
        return updated
    }

    /// Returns the band suggested after adding a dead zone around the current band.
    public static func hystereticBand(
        for rssi: Double,
        currentBand: Int,
        bands: [ProximityBand],
        margin: Double
    ) -> Int {
        guard bands.indices.contains(currentBand) else {
            return idealBand(for: rssi, bands: bands)
        }

        let thresholds = boundaries(for: bands)
        let ideal = idealBand(for: rssi, bands: bands)

        if ideal > currentBand,
           thresholds.indices.contains(currentBand),
           rssi < thresholds[currentBand] - margin {
            return ideal
        }

        if ideal < currentBand,
           currentBand > 0,
           thresholds.indices.contains(currentBand - 1),
           rssi > thresholds[currentBand - 1] + margin {
            return ideal
        }

        return currentBand
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    public static func validAnchor(
        _ value: Double,
        at index: Int,
        in bands: [ProximityBand],
        minimumSeparation: Double = 4
    ) -> Bool {
        guard bands.indices.contains(index), (-100 ... -20).contains(value) else { return false }
        if index > 0, value > bands[index - 1].anchorRSSI - minimumSeparation { return false }
        if index < bands.count - 1, value < bands[index + 1].anchorRSSI + minimumSeparation { return false }
        return true
    }
}
