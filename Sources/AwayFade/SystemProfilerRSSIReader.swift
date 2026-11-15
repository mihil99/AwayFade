import Foundation

enum SystemProfilerRSSIReader {
    /// `IOBluetoothDevice.rawRSSI()` is frequently a cached value. System Profiler asks the
    /// controller for a fresh sample, so use its connected-device report as the live source.
    static func read(address: String) async -> Int? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["-detailLevel", "basic", "SPBluetoothDataType", "-json"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return nil
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return parse(data: data, matchingAddress: address)
        }.value
    }

    private static func parse(data: Data, matchingAddress address: String) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reports = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }

        for report in reports {
            guard let connectedDevices = report["device_connected"] as? [[String: Any]] else { continue }
            for namedDevice in connectedDevices {
                for rawDetails in namedDevice.values {
                    guard let details = rawDetails as? [String: Any],
                          let foundAddress = details["device_address"] as? String,
                          normalizedAddress(foundAddress) == normalizedAddress(address)
                    else { continue }

                    if let rssi = details["device_rssi"] as? String { return Int(rssi) }
                    if let rssi = details["device_rssi"] as? NSNumber { return rssi.intValue }
                }
            }
        }
        return nil
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.uppercased().filter(\.isHexDigit)
    }
}
