import Foundation
import SwiftUI

@MainActor
final class HueShowController: ObservableObject {
    @Published var bridges: [HueBridge] = []
    @Published var bridgeAddress: String {
        didSet {
            UserDefaults.standard.set(bridgeAddress, forKey: Self.bridgeAddressKey)
        }
    }
    @Published var username: String? {
        didSet {
            if let username = username {
                UserDefaults.standard.set(username, forKey: Self.usernameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.usernameKey)
            }
        }
    }
    @Published var lights: [HueLight] = []
    @Published var selectedLightID: String? {
        didSet {
            if let selectedLightID = selectedLightID {
                UserDefaults.standard.set(selectedLightID, forKey: Self.selectedLightKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedLightKey)
            }
        }
    }
    @Published var colors: [HueShowColor] {
        didSet {
            saveColors()
        }
    }
    @Published var showDuration: Double {
        didSet {
            UserDefaults.standard.set(showDuration, forKey: Self.durationKey)
        }
    }
    @Published var changeInterval: Double {
        didSet {
            UserDefaults.standard.set(changeInterval, forKey: Self.intervalKey)
        }
    }
    @Published var transitionStyle: HueTransitionStyle {
        didSet {
            UserDefaults.standard.set(transitionStyle.rawValue, forKey: Self.transitionStyleKey)
        }
    }
    @Published var statusMessage: String = "Ready."
    @Published var isBusy = false
    @Published var isRunning = false
    @Published var remainingSeconds = 0

    private let client: HueBridgeClient
    private let bundledBridgeConfig: HueBridgeConfiguration
    private var showTask: Task<Void, Never>?

    private static let bridgeAddressKey = "HueLightShow.bridgeAddress"
    private static let usernameKey = "HueLightShow.username"
    private static let selectedLightKey = "HueLightShow.selectedLightID"
    private static let colorsKey = "HueLightShow.colors"
    private static let durationKey = "HueLightShow.duration"
    private static let intervalKey = "HueLightShow.interval"
    private static let transitionStyleKey = "HueLightShow.transitionStyle"

    init(client: HueBridgeClient = .shared) {
        let bundledConfig = HueBridgeConfiguration.loadBundled()

        self.client = client
        self.bundledBridgeConfig = bundledConfig
        self.bridgeAddress = UserDefaults.standard.string(forKey: Self.bridgeAddressKey)
            ?? HueBridgeConfiguration.cleaned(bundledConfig.bridgeAddress)
            ?? ""
        self.username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? bundledConfig.effectiveUsername
        self.selectedLightID = UserDefaults.standard.string(forKey: Self.selectedLightKey)
            ?? HueBridgeConfiguration.cleaned(bundledConfig.selectedLightID)
        self.colors = Self.loadColors()

        let savedDuration = UserDefaults.standard.double(forKey: Self.durationKey)
        self.showDuration = savedDuration > 0 ? savedDuration : 30

        let savedInterval = UserDefaults.standard.double(forKey: Self.intervalKey)
        self.changeInterval = savedInterval > 0 ? savedInterval : 1.2

        let savedTransition = UserDefaults.standard.string(forKey: Self.transitionStyleKey)
        self.transitionStyle = savedTransition.flatMap(HueTransitionStyle.init(rawValue:)) ?? .gradual

        if bundledConfig.hasConnectionDefaults {
            self.statusMessage = "Loaded BridgeConfig.plist."
        }
    }

    var isPaired: Bool {
        username?.isEmpty == false
    }

    var selectedLight: HueLight? {
        guard let selectedLightID = selectedLightID else {
            return nil
        }
        return lights.first { $0.id == selectedLightID }
    }

    var canStart: Bool {
        isPaired &&
        selectedLightID != nil &&
        !colors.isEmpty &&
        showDuration >= 1 &&
        changeInterval >= 0.2 &&
        !isBusy &&
        !isRunning
    }

    func selectBridge(_ bridge: HueBridge) {
        bridgeAddress = bridge.displayName
        statusMessage = "Selected \(bridge.displayName)."
    }

    func discoverBridges() async {
        await runBusyTask {
            let discovered = try await client.discoverBridges()
            bridges = discovered

            if bridgeAddress.isEmpty, let firstBridge = discovered.first {
                bridgeAddress = firstBridge.displayName
            }

            statusMessage = discovered.isEmpty ? "No Hue Bridges found." : "Found \(discovered.count) bridge\(discovered.count == 1 ? "" : "s")."
        }
    }

    func pairBridge() async {
        await runBusyTask {
            let newUsername = try await client.createUser(bridgeAddress: bridgeAddress)
            username = newUsername
            statusMessage = "Bridge paired."
            try await refreshLightsAfterPairing()
        }
    }

    func refreshLights() async {
        await runBusyTask {
            try await refreshLightsAfterPairing()
        }
    }

    func addColor() {
        let nextColor: HueShowColor
        switch colors.count % 5 {
        case 0:
            nextColor = HueShowColor(red: 1.0, green: 0.3, blue: 0.78)
        case 1:
            nextColor = HueShowColor(red: 0.44, green: 0.9, blue: 1.0)
        case 2:
            nextColor = HueShowColor(red: 0.98, green: 0.9, blue: 0.26)
        case 3:
            nextColor = HueShowColor(red: 0.25, green: 0.92, blue: 0.53)
        default:
            nextColor = HueShowColor(red: 1.0, green: 0.46, blue: 0.18)
        }
        colors.append(nextColor)
    }

    func updateColor(id: UUID, to color: Color) {
        guard let index = colors.firstIndex(where: { $0.id == id }) else {
            return
        }
        var updatedColors = colors
        updatedColors[index].update(from: color)
        colors = updatedColors
    }

    func removeColor(id: UUID) {
        guard colors.count > 1 else {
            return
        }
        colors.removeAll { $0.id == id }
    }

    func startShow() {
        guard canStart else {
            statusMessage = "Select a paired bridge and light first."
            return
        }
        guard let username = username, let selectedLightID = selectedLightID else {
            statusMessage = "Pair with the Hue Bridge first."
            return
        }

        let runBridgeAddress = bridgeAddress
        let runColors = colors
        let runDuration = showDuration
        let runInterval = changeInterval
        let runTransitionStyle = transitionStyle

        isRunning = true
        remainingSeconds = Int(ceil(runDuration))
        statusMessage = "Show running with \(runTransitionStyle.title)."

        showTask = Task { [weak self] in
            guard let self = self else {
                return
            }
            await self.runShow(
                bridgeAddress: runBridgeAddress,
                username: username,
                lightID: selectedLightID,
                colors: runColors,
                duration: runDuration,
                interval: runInterval,
                transitionStyle: runTransitionStyle
            )
        }
    }

    func stopShow() {
        showTask?.cancel()
        showTask = nil
        if isRunning {
            statusMessage = "Show stopped."
        }
        isRunning = false
        remainingSeconds = 0
    }

    private func runShow(
        bridgeAddress: String,
        username: String,
        lightID: String,
        colors: [HueShowColor],
        duration: Double,
        interval: Double,
        transitionStyle: HueTransitionStyle
    ) async {
        let endDate = Date().addingTimeInterval(duration)
        var colorIndex = 0

        do {
            while Date() < endDate {
                try Task.checkCancellation()

                let showColor = colors[colorIndex % colors.count].bridgeColor
                try await applyTransition(
                    bridgeAddress: bridgeAddress,
                    username: username,
                    lightID: lightID,
                    color: showColor,
                    style: transitionStyle,
                    interval: interval
                )

                colorIndex += 1
                try await sleepWithProgress(maxSeconds: transitionStyle.waitSeconds(for: interval), endDate: endDate)
            }

            statusMessage = "Show complete."
        } catch is CancellationError {
            statusMessage = "Show stopped."
        } catch {
            statusMessage = error.localizedDescription
        }

        isRunning = false
        remainingSeconds = 0
        showTask = nil
    }

    private func applyTransition(
        bridgeAddress: String,
        username: String,
        lightID: String,
        color: HueBridgeColor,
        style: HueTransitionStyle,
        interval: Double
    ) async throws {
        switch style {
        case .snap, .gradual, .softFade:
            try await client.setLight(
                bridgeAddress: bridgeAddress,
                username: username,
                lightID: lightID,
                color: color,
                transitionSeconds: style.commandTransitionSeconds(for: interval)
            )
        case .pulse:
            let dipSeconds = min(0.45, max(0.12, interval * 0.25))
            try await client.setLight(
                bridgeAddress: bridgeAddress,
                username: username,
                lightID: lightID,
                color: color.scaledBrightness(0.2),
                transitionSeconds: dipSeconds
            )
            try await Task.sleep(nanoseconds: UInt64(dipSeconds * 1_000_000_000))
            try await client.setLight(
                bridgeAddress: bridgeAddress,
                username: username,
                lightID: lightID,
                color: color,
                transitionSeconds: style.commandTransitionSeconds(for: interval)
            )
        case .blink:
            try await client.setLightPower(
                bridgeAddress: bridgeAddress,
                username: username,
                lightID: lightID,
                isOn: false,
                transitionSeconds: 0.0
            )
            try await Task.sleep(nanoseconds: 120_000_000)
            try await client.setLight(
                bridgeAddress: bridgeAddress,
                username: username,
                lightID: lightID,
                color: color,
                transitionSeconds: 0.0
            )
        }
    }

    private func sleepWithProgress(maxSeconds: Double, endDate: Date) async throws {
        let nextWake = min(Date().addingTimeInterval(maxSeconds), endDate)

        while Date() < nextWake {
            try Task.checkCancellation()
            remainingSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
            let slice = min(0.2, max(0.05, nextWake.timeIntervalSinceNow))
            try await Task.sleep(nanoseconds: UInt64(slice * 1_000_000_000))
        }
    }

    private func refreshLightsAfterPairing() async throws {
        guard let username = username else {
            throw HueBridgeError.bridgeNotPaired
        }

        let fetchedLights = try await client.fetchLights(bridgeAddress: bridgeAddress, username: username)
        lights = fetchedLights

        if let currentSelection = selectedLightID, fetchedLights.contains(where: { $0.id == currentSelection }) {
            selectedLightID = currentSelection
        } else if let configuredLightName = HueBridgeConfiguration.cleaned(bundledBridgeConfig.selectedLightName),
                  let configuredLight = fetchedLights.first(where: { $0.name.localizedCaseInsensitiveCompare(configuredLightName) == .orderedSame }) {
            selectedLightID = configuredLight.id
        } else {
            selectedLightID = fetchedLights.first?.id
        }

        statusMessage = "Loaded \(fetchedLights.count) light\(fetchedLights.count == 1 ? "" : "s")."
    }

    private func runBusyTask(_ operation: () async throws -> Void) async {
        guard !isBusy else {
            return
        }

        isBusy = true
        defer {
            isBusy = false
        }

        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func saveColors() {
        if let data = try? JSONEncoder().encode(colors) {
            UserDefaults.standard.set(data, forKey: Self.colorsKey)
        }
    }

    private static func loadColors() -> [HueShowColor] {
        guard
            let data = UserDefaults.standard.data(forKey: colorsKey),
            let saved = try? JSONDecoder().decode([HueShowColor].self, from: data),
            !saved.isEmpty
        else {
            return HueShowColor.presets
        }
        return saved
    }
}
