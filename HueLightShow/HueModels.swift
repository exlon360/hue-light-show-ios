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
}
