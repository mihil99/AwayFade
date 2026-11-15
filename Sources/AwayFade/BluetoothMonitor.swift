@preconcurrency import IOBluetooth
import Foundation

struct BluetoothDeviceInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

@MainActor
final class BluetoothMonitor {
    func connectedDevices() -> [BluetoothDeviceInfo] {
        pairedDevices()
            .filter { $0.isConnected() }
            .compactMap { device in
                guard let address = device.addressString, !address.isEmpty else { return nil }
                let name = device.name ?? device.nameOrAddress ?? "Bluetooth device"
                return BluetoothDeviceInfo(id: address, name: name)
            }
            .sorted { lhs, rhs in
                let lhsAirPods = lhs.name.localizedCaseInsensitiveContains("AirPods")
                let rhsAirPods = rhs.name.localizedCaseInsensitiveContains("AirPods")
                if lhsAirPods != rhsAirPods { return lhsAirPods }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func rawRSSI(for address: String) -> Int? {
        guard let device = pairedDevices().first(where: { $0.addressString == address }),
              device.isConnected()
        else { return nil }

        let value = Int(device.rawRSSI())
        return value == 127 ? nil : value
    }

    private func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    }
}
