import Foundation
import SwiftUI
import UIKit

private struct HueLightRunSettings {
    let lightID: String
    let colors: [HueShowColor]
    let transitionStyle: HueTransitionStyle
}

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
    @Published var selectedLightIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedLightIDs).sorted(), forKey: Self.selectedLightsKey)
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
    @Published var isInfiniteDuration: Bool {
        didSet {
            UserDefaults.standard.set(isInfiniteDuration, forKey: Self.infiniteDurationKey)
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
    @Published var customLightSettings: [String: HueLightCustomSettings] {
        didSet {
            saveCustomLightSettings()
        }
    }
    @Published var statusMessage: String = "Ready."
    @Published var isBusy = false
    @Published var isRunning = false
    @Published var remainingSeconds = 0

    private let client: HueBridgeClient
    private let bundledBridgeConfig: HueBridgeConfiguration
    private var showTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private static let bridgeAddressKey = "HueLightShow.bridgeAddress"
    private static let usernameKey = "HueLightShow.username"
    private static let selectedLightKey = "HueLightShow.selectedLightID"
    private static let selectedLightsKey = "HueLightShow.selectedLightIDs"
    private static let colorsKey = "HueLightShow.colors"
    private static let durationKey = "HueLightShow.duration"
    private static let infiniteDurationKey = "HueLightShow.isInfiniteDuration"
    private static let intervalKey = "HueLightShow.interval"
    private static let transitionStyleKey = "HueLightShow.transitionStyle"
    private static let customLightSettingsKey = "HueLightShow.customLightSettings"

    init(client: HueBridgeClient = .shared) {
        let bundledConfig = HueBridgeConfiguration.loadBundled()

        self.client = client
        self.bundledBridgeConfig = bundledConfig
        self.bridgeAddress = UserDefaults.standard.string(forKey: Self.bridgeAddressKey)
            ?? HueBridgeConfiguration.cleaned(bundledConfig.bridgeAddress)
            ?? ""
        self.username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? bundledConfig.effectiveUsername
        self.selectedLightIDs = Self.loadSelectedLightIDs(from: bundledConfig)
        self.colors = Self.loadColors()
        self.customLightSettings = Self.loadCustomLightSettings()

        let savedDuration = UserDefaults.standard.double(forKey: Self.durationKey)
        self.showDuration = savedDuration > 0 ? savedDuration : 30
        self.isInfiniteDuration = UserDefaults.standard.bool(forKey: Self.infiniteDurationKey)

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

    var selectedLights: [HueLight] {
        lights.filter { selectedLightIDs.contains($0.id) }
    }

    var selectedLightCount: Int {
        selectedLightIDs.count
    }

    var selectedLightSummary: String {
        if selectedLightIDs.isEmpty {
            return "No lights selected."
        }

        let visibleNames = selectedLights.map { $0.name }
        if visibleNames.isEmpty {
            return "\(selectedLightIDs.count) configured light\(selectedLightIDs.count == 1 ? "" : "s")."
        }
        if visibleNames.count <= 2 {
            return visibleNames.joined(separator: ", ")
        }
        return "\(visibleNames[0]), \(visibleNames[1]) +\(visibleNames.count - 2)"
    }

    var canStart: Bool {
        isPaired &&
        !selectedLightIDs.isEmpty &&
        !colors.isEmpty &&
        (isInfiniteDuration || showDuration >= 1) &&
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

    func isLightSelected(_ lightID: String) -> Bool {
        selectedLightIDs.contains(lightID)
    }

    func toggleLightSelection(_ lightID: String) {
        var updatedSelection = selectedLightIDs
        if updatedSelection.contains(lightID) {
            updatedSelection.remove(lightID)
        } else {
            updatedSelection.insert(lightID)
        }
        selectedLightIDs = updatedSelection
    }

    func selectAllLights() {
        selectedLightIDs = Set(lights.map { $0.id })
    }

    func usesCustomSettings(_ lightID: String) -> Bool {
        customLightSettings[lightID] != nil
    }

    func toggleCustomSettings(for lightID: String) {
        var updated = customLightSettings
        if updated[lightID] != nil {
            updated.removeValue(forKey: lightID)
            statusMessage = "Light returned to the Global group."
        } else {
            updated[lightID] = HueLightCustomSettings(colors: colors, transitionStyle: transitionStyle)
            statusMessage = "Light now has custom settings."
        }
        customLightSettings = updated
    }

    func customColors(for lightID: String) -> [HueShowColor] {
        customLightSettings[lightID]?.colors ?? colors
    }

    func customTransitionStyle(for lightID: String) -> HueTransitionStyle {
        customLightSettings[lightID]?.transitionStyle ?? transitionStyle
    }

    func setCustomTransitionStyle(_ style: HueTransitionStyle, for lightID: String) {
        var settings = customLightSettings[lightID] ?? HueLightCustomSettings(colors: colors, transitionStyle: transitionStyle)
        settings.transitionStyle = style
        setCustomSettings(settings, for: lightID)
    }

    func addColor() {
        colors.append(nextColor(for: colors.count))
    }

    func addCustomColor(for lightID: String) {
        var settings = customLightSettings[lightID] ?? HueLightCustomSettings(colors: colors, transitionStyle: transitionStyle)
        settings.colors.append(nextColor(for: settings.colors.count))
        setCustomSettings(settings, for: lightID)
    }

    func updateColor(id: UUID, to color: Color) {
        guard let index = colors.firstIndex(where: { $0.id == id }) else {
            return
        }
        var updatedColors = colors
        updatedColors[index].update(from: color)
        colors = updatedColors
    }

    func updateCustomColor(lightID: String, colorID: UUID, to color: Color) {
        var settings = customLightSettings[lightID] ?? HueLightCustomSettings(colors: colors, transitionStyle: transitionStyle)
        guard let index = settings.colors.firstIndex(where: { $0.id == colorID }) else {
            return
        }
        settings.colors[index].update(from: color)
        setCustomSettings(settings, for: lightID)
    }

    func removeColor(id: UUID) {
        guard colors.count > 1 else {
            statusMessage = "Keep at least one global color."
            return
        }
        colors.removeAll { $0.id == id }
    }

    func removeCustomColor(lightID: String, colorID: UUID) {
        var settings = customLightSettings[lightID] ?? HueLightCustomSettings(colors: colors, transitionStyle: transitionStyle)
        guard settings.colors.count > 1 else {
            statusMessage = "Keep at least one custom color."
            return
        }
        settings.colors.removeAll { $0.id == colorID }
        setCustomSettings(settings, for: lightID)
    }

    func startShow() {
        guard canStart else {
            statusMessage = "Select a paired bridge and at least one light first."
            return
        }
        guard let username = username else {
            statusMessage = "Pair with the Hue Bridge first."
            return
        }

        let runBridgeAddress = bridgeAddress
        let runLightSettings = makeRunSettingsForSelectedLights()
        let runDuration = isInfiniteDuration ? nil : showDuration
        let runInterval = changeInterval
        let customCount = runLightSettings.filter { customLightSettings[$0.lightID] != nil }.count

        isRunning = true
        remainingSeconds = runDuration.map { Int(ceil($0)) } ?? 0
        setIdleTimerDisabled(true)
        beginBackgroundRunAllowance()
        let durationText = isInfiniteDuration ? "forever" : "\(Int(showDuration))s"
        statusMessage = "Running \(durationText) on \(runLightSettings.count) light\(runLightSettings.count == 1 ? "" : "s") (\(customCount) custom)."

        showTask = Task { [weak self] in
            guard let self = self else {
                return
            }
            await self.runShow(
                bridgeAddress: runBridgeAddress,
                username: username,
                lightSettings: runLightSettings,
                duration: runDuration,
                interval: runInterval
            )
        }
    }

    func stopShow(message: String = "Show stopped.") {
        showTask?.cancel()
        showTask = nil
        setIdleTimerDisabled(false)
        endBackgroundRunAllowance()
        if isRunning {
            statusMessage = message
        }
        isRunning = false
        remainingSeconds = 0
    }

    private func runShow(
        bridgeAddress: String,
        username: String,
        lightSettings: [HueLightRunSettings],
        duration: Double?,
        interval: Double
    ) async {
        let endDate = duration.map { Date().addingTimeInterval($0) }
        var colorIndex = 0

        do {
            while shouldContinueRunning(until: endDate) {
                try Task.checkCancellation()

                try await applyTransitionsForLightSettings(
                    bridgeAddress: bridgeAddress,
                    username: username,
                    lightSettings: lightSettings,
                    colorIndex: colorIndex,
                    interval: interval
                )

                colorIndex += 1
                let waitSeconds = lightSettings.map { $0.transitionStyle.waitSeconds(for: interval) }.max() ?? interval
                try await sleepWithProgress(maxSeconds: waitSeconds, endDate: endDate)
            }

            statusMessage = "Show complete."
        } catch is CancellationError {
            if statusMessage != "iOS ended background time." {
                statusMessage = "Show stopped."
            }
        } catch {
            statusMessage = error.localizedDescription
        }

        isRunning = false
        remainingSeconds = 0
        setIdleTimerDisabled(false)
        endBackgroundRunAllowance()
        showTask = nil
    }

    private func makeRunSettingsForSelectedLights() -> [HueLightRunSettings] {
        Array(selectedLightIDs).sorted().map { lightID in
            let customSettings = customLightSettings[lightID]
            let lightColors = customSettings?.colors ?? colors
            return HueLightRunSettings(
                lightID: lightID,
                colors: lightColors.isEmpty ? HueShowColor.presets : lightColors,
                transitionStyle: customSettings?.transitionStyle ?? transitionStyle
            )
        }
    }

    private func applyTransitionsForLightSettings(
        bridgeAddress: String,
        username: String,
        lightSettings: [HueLightRunSettings],
        colorIndex: Int,
        interval: Double
    ) async throws {
        let groupedSettings = Dictionary(grouping: lightSettings, by: { $0.transitionStyle })
        for style in HueTransitionStyle.allCases {
            guard let settingsForStyle = groupedSettings[style] else {
                continue
            }
            let lightIDs = settingsForStyle.map { $0.lightID }
            let colorsByLightID = Dictionary(uniqueKeysWithValues: settingsForStyle.map { settings in
                (settings.lightID, settings.colors[colorIndex % settings.colors.count].bridgeColor)
            })
            try await applyTransitionToLights(
                bridgeAddress: bridgeAddress,
                username: username,
                lightIDs: lightIDs,
                colorsByLightID: colorsByLightID,
                style: style,
                interval: interval
            )
        }
    }

    private func applyTransitionToLights(
        bridgeAddress: String,
        username: String,
        lightIDs: [String],
        colorsByLightID: [String: HueBridgeColor],
        style: HueTransitionStyle,
        interval: Double
    ) async throws {
        switch style {
        case .snap, .gradual, .softFade:
            for lightID in lightIDs {
                try Task.checkCancellation()
                guard let color = colorsByLightID[lightID] else {
                    continue
                }
                try await client.setLight(
                    bridgeAddress: bridgeAddress,
                    username: username,
                    lightID: lightID,
                    color: color,
                    transitionSeconds: style.commandTransitionSeconds(for: interval)
                )
            }
        case .pulse:
            let dipSeconds = min(0.45, max(0.12, interval * 0.25))
            for lightID in lightIDs {
                try Task.checkCancellation()
                guard let color = colorsByLightID[lightID] else {
                    continue
                }
                try await client.setLight(
                    bridgeAddress: bridgeAddress,
                    username: username,
                    lightID: lightID,
                    color: color.scaledBrightness(0.2),
                    transitionSeconds: dipSeconds
                )
            }
            try await Task.sleep(nanoseconds: UInt64(dipSeconds * 1_000_000_000))
            for lightID in lightIDs {
                try Task.checkCancellation()
                guard let color = colorsByLightID[lightID] else {
                    continue
                }
                try await client.setLight(
                    bridgeAddress: bridgeAddress,
                    username: username,
                    lightID: lightID,
                    color: color,
                    transitionSeconds: style.commandTransitionSeconds(for: interval)
                )
            }
        case .blink:
            for lightID in lightIDs {
                try Task.checkCancellation()
                try await client.setLightPower(
                    bridgeAddress: bridgeAddress,
                    username: username,
                    lightID: lightID,
                    isOn: false,
                    transitionSeconds: 0.0
                )
            }
            try await Task.sleep(nanoseconds: 120_000_000)
            for lightID in lightIDs {
                try Task.checkCancellation()
                guard let color = colorsByLightID[lightID] else {
                    continue
                }
                try await client.setLight(
                    bridgeAddress: bridgeAddress,
                    username: username,
                    lightID: lightID,
                    color: color,
                    transitionSeconds: 0.0
                )
            }
        }
    }

    private func shouldContinueRunning(until endDate: Date?) -> Bool {
        guard let endDate = endDate else {
            return true
        }
        return Date() < endDate
    }

    private func sleepWithProgress(maxSeconds: Double, endDate: Date?) async throws {
        let nextWake: Date
        if let endDate = endDate {
            nextWake = min(Date().addingTimeInterval(maxSeconds), endDate)
        } else {
            nextWake = Date().addingTimeInterval(maxSeconds)
        }

        while Date() < nextWake {
            try Task.checkCancellation()
            if let endDate = endDate {
                remainingSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
            } else {
                remainingSeconds = 0
            }
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

        let fetchedIDs = Set(fetchedLights.map { $0.id })
        let stillAvailable = selectedLightIDs.intersection(fetchedIDs)
        if !stillAvailable.isEmpty {
            selectedLightIDs = stillAvailable
        } else if !bundledBridgeConfig.effectiveSelectedLightNames.isEmpty {
            let configuredNames = Set(bundledBridgeConfig.effectiveSelectedLightNames.map { $0.lowercased() })
            let configuredLights = fetchedLights.filter { configuredNames.contains($0.name.lowercased()) }
            selectedLightIDs = Set(configuredLights.map { $0.id })
        } else {
            selectedLightIDs = Set(fetchedLights.prefix(1).map { $0.id })
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

    private func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    private func beginBackgroundRunAllowance() {
        endBackgroundRunAllowance()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "HueLightShow") { [weak self] in
            Task { @MainActor in
                self?.stopShow(message: "iOS ended background time.")
            }
        }
    }

    private func endBackgroundRunAllowance() {
        guard backgroundTaskID != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func setCustomSettings(_ settings: HueLightCustomSettings, for lightID: String) {
        var updated = customLightSettings
        updated[lightID] = settings
        customLightSettings = updated
    }

    private func nextColor(for count: Int) -> HueShowColor {
        switch count % 5 {
        case 0:
            return HueShowColor(red: 1.0, green: 0.3, blue: 0.78)
        case 1:
            return HueShowColor(red: 0.44, green: 0.9, blue: 1.0)
        case 2:
            return HueShowColor(red: 0.98, green: 0.9, blue: 0.26)
        case 3:
            return HueShowColor(red: 0.25, green: 0.92, blue: 0.53)
        default:
            return HueShowColor(red: 1.0, green: 0.46, blue: 0.18)
        }
    }

    private func saveColors() {
        if let data = try? JSONEncoder().encode(colors) {
            UserDefaults.standard.set(data, forKey: Self.colorsKey)
        }
    }

    private func saveCustomLightSettings() {
        if let data = try? JSONEncoder().encode(customLightSettings) {
            UserDefaults.standard.set(data, forKey: Self.customLightSettingsKey)
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

    private static func loadCustomLightSettings() -> [String: HueLightCustomSettings] {
        guard
            let data = UserDefaults.standard.data(forKey: customLightSettingsKey),
            let saved = try? JSONDecoder().decode([String: HueLightCustomSettings].self, from: data)
        else {
            return [:]
        }
        return saved
    }

    private static func loadSelectedLightIDs(from config: HueBridgeConfiguration) -> Set<String> {
        let savedIDs = UserDefaults.standard.stringArray(forKey: selectedLightsKey)?.compactMap(HueBridgeConfiguration.cleaned) ?? []
        if !savedIDs.isEmpty {
            return Set(savedIDs)
        }

        if let legacyID = HueBridgeConfiguration.cleaned(UserDefaults.standard.string(forKey: selectedLightKey)) {
            return [legacyID]
        }

        return Set(config.effectiveSelectedLightIDs)
    }
}
