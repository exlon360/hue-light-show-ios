import Foundation
import SwiftUI
import UIKit

struct HueBridge: Decodable, Equatable, Identifiable {
    let id: String
    let internalipaddress: String
    let port: Int?

    var displayName: String {
        if let port = port {
            return "\(internalipaddress):\(port)"
        }
        return internalipaddress
    }
}

struct HueLight: Equatable, Identifiable {
    let id: String
    let name: String
    let type: String
    let state: HueLightState

    var isReachable: Bool {
        state.reachable ?? true
    }

    var isColorCapable: Bool {
        state.hue != nil && state.sat != nil
    }
}

struct HueLightState: Decodable, Equatable {
    let on: Bool?
    let hue: Int?
    let sat: Int?
    let bri: Int?
    let reachable: Bool?
}

struct HueShowColor: Codable, Equatable, Identifiable {
    var id: UUID
    var red: Double
    var green: Double
    var blue: Double

    init(id: UUID = UUID(), red: Double, green: Double, blue: Double) {
        self.id = id
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(color: Color) {
        self.init(red: 1.0, green: 1.0, blue: 1.0)
        update(from: color)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var bridgeColor: HueBridgeColor {
        let uiColor = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return HueBridgeColor(
            hue: Int((Double(hue) * 65535.0).rounded()),
            saturation: Int((Double(saturation) * 254.0).rounded()),
            brightness: max(1, Int((Double(brightness) * 254.0).rounded()))
        )
    }

    mutating func update(from color: Color) {
        let uiColor = UIColor(color)
        var redComponent: CGFloat = 0
        var greenComponent: CGFloat = 0
        var blueComponent: CGFloat = 0
        var alphaComponent: CGFloat = 0

        if uiColor.getRed(&redComponent, green: &greenComponent, blue: &blueComponent, alpha: &alphaComponent) {
            red = Double(redComponent)
            green = Double(greenComponent)
            blue = Double(blueComponent)
            return
        }

        var white: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alphaComponent) {
            red = Double(white)
            green = Double(white)
            blue = Double(white)
        }
    }

    static let presets: [HueShowColor] = [
        HueShowColor(red: 1.0, green: 0.17, blue: 0.18),
        HueShowColor(red: 0.05, green: 0.72, blue: 1.0),
        HueShowColor(red: 0.2, green: 0.95, blue: 0.42),
        HueShowColor(red: 1.0, green: 0.78, blue: 0.18)
    ]
}

struct HueBridgeColor: Equatable {
    let hue: Int
    let saturation: Int
    let brightness: Int

    func scaledBrightness(_ multiplier: Double) -> HueBridgeColor {
        HueBridgeColor(
            hue: hue,
            saturation: saturation,
            brightness: max(1, min(254, Int((Double(brightness) * multiplier).rounded())))
        )
    }
}

struct HueLightCustomSettings: Codable, Equatable {
    var colors: [HueShowColor]
    var transitionStyle: HueTransitionStyle

    init(colors: [HueShowColor], transitionStyle: HueTransitionStyle) {
        self.colors = colors.isEmpty ? HueShowColor.presets : colors
        self.transitionStyle = transitionStyle
    }
}

struct HueBridgeConfiguration: Decodable {
    let bridgeAddress: String?
    let username: String?
    let applicationKey: String?
    let selectedLightID: String?
    let selectedLightIDs: [String]?
    let selectedLightName: String?
    let selectedLightNames: [String]?
    let autoRefreshLights: Bool?

    var effectiveUsername: String? {
        Self.cleaned(username) ?? Self.cleaned(applicationKey)
    }

    var effectiveSelectedLightIDs: [String] {
        var ids = Self.cleanedArray(selectedLightIDs)
        if let legacyID = Self.cleaned(selectedLightID) {
            ids.append(legacyID)
        }
        return ids
    }

    var effectiveSelectedLightNames: [String] {
        var names = Self.cleanedArray(selectedLightNames)
        if let legacyName = Self.cleaned(selectedLightName) {
            names.append(legacyName)
        }
        return names
    }

    var hasConnectionDefaults: Bool {
        Self.cleaned(bridgeAddress) != nil && effectiveUsername != nil
    }

    static func loadBundled() -> HueBridgeConfiguration {
        guard
            let url = Bundle.main.url(forResource: "BridgeConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let config = try? PropertyListDecoder().decode(HueBridgeConfiguration.self, from: data)
        else {
            return HueBridgeConfiguration(
                bridgeAddress: nil,
                username: nil,
                applicationKey: nil,
                selectedLightID: nil,
                selectedLightIDs: nil,
                selectedLightName: nil,
                selectedLightNames: nil,
                autoRefreshLights: true
            )
        }

        return config
    }

    static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func cleanedArray(_ values: [String]?) -> [String] {
        values?.compactMap(cleaned) ?? []
    }
}

enum HueTransitionStyle: String, CaseIterable, Codable, Identifiable {
    case snap
    case gradual
    case softFade
    case pulse
    case blink

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .snap:
            return "Snap"
        case .gradual:
            return "Gradual"
        case .softFade:
            return "Soft Fade"
        case .pulse:
            return "Pulse"
        case .blink:
            return "Blink"
        }
    }

    var subtitle: String {
        switch self {
        case .snap:
            return "Instantly jumps to each color."
        case .gradual:
            return "Slowly crossfades to the next color."
        case .softFade:
            return "Uses a longer, smoother fade."
        case .pulse:
            return "Dips dim, then blooms into the next color."
        case .blink:
            return "Briefly cuts out before the next color."
        }
    }

    var symbolName: String {
        switch self {
        case .snap:
            return "bolt.fill"
        case .gradual:
            return "dial.medium.fill"
        case .softFade:
            return "sparkles"
        case .pulse:
            return "circle.dotted"
        case .blink:
            return "lightbulb.max.fill"
        }
    }

    func commandTransitionSeconds(for changeInterval: Double) -> Double {
        switch self {
        case .snap, .blink:
            return 0.0
        case .gradual:
            return max(0.2, changeInterval)
        case .softFade:
            return max(0.4, changeInterval * 1.6)
        case .pulse:
            return max(0.2, changeInterval * 0.55)
        }
    }

    func waitSeconds(for changeInterval: Double) -> Double {
        switch self {
        case .snap, .gradual, .pulse, .blink:
            return changeInterval
        case .softFade:
            return max(changeInterval, changeInterval * 1.25)
        }
    }
}

enum HueGlobalPattern: String, CaseIterable, Codable, Identifiable {
    case together
    case fairyLights

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .together:
            return "Together"
        case .fairyLights:
            return "Fairy Lights"
        }
    }

    var symbolName: String {
        switch self {
        case .together:
            return "circle.grid.2x2.fill"
        case .fairyLights:
            return "lightspectrum.horizontal"
        }
    }
}
