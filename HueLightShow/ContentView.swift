import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var show = HueShowController()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    bridgePanel
                    lightPanel
                    timingPanel
                    colorsPanel
                    startPanel
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Hue Light Show")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await show.refreshLights()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(show.isBusy || show.isPaired == false)
                }
            }
            .task {
                if show.bridgeAddress.isEmpty {
                    await show.discoverBridges()
                } else if show.isPaired {
                    await show.refreshLights()
                }
            }
        }
        .tint(.teal)
    }

    private var bridgePanel: some View {
        ControlPanel(title: "Bridge", symbolName: "dot.radiowaves.left.and.right") {
            VStack(spacing: 12) {
                TextField("Bridge IP or host", text: $show.bridgeAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                if show.bridges.isEmpty == false {
                    Picker("Found", selection: bridgeSelection) {
                        ForEach(show.bridges) { bridge in
                            Text(bridge.displayName).tag(bridge.displayName)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack(spacing: 10) {
                    ActionButton(title: "Find", symbolName: "magnifyingglass", tint: .teal) {
                        Task {
                            await show.discoverBridges()
                        }
                    }
                    .disabled(show.isBusy)

                    ActionButton(title: "Pair", symbolName: "link", tint: .green) {
                        Task {
                            await show.pairBridge()
                        }
                    }
                    .disabled(show.bridgeAddress.isEmpty || show.isBusy)
                }

                StatusStrip(message: show.statusMessage, isBusy: show.isBusy, isPaired: show.isPaired)
            }
        }
    }

    private var lightPanel: some View {
        ControlPanel(title: "Lights", symbolName: "lightbulb.led.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(show.selectedLightCount) selected")
                            .font(.subheadline.weight(.black))
                        Text(show.selectedLightSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button {
                        show.selectAllLights()
                    } label: {
                        Label("All", systemImage: "checklist.checked")
                            .font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(show.lights.isEmpty)
                }

                if show.lights.isEmpty {
                    Text(show.isPaired ? "No lights loaded." : "Pair a bridge to load lights.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(show.lights) { light in
                            LightSelectionRow(
                                light: light,
                                isSelected: show.isLightSelected(light.id)
                            ) {
                                show.toggleLightSelection(light.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var timingPanel: some View {
        ControlPanel(title: "Timing", symbolName: "timer") {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Show", systemImage: "clock")
                        Spacer()
                        Text("\(Int(show.showDuration))s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.semibold))

                    Slider(value: $show.showDuration, in: 5...600, step: 5)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Change", systemImage: "speedometer")
                        Spacer()
                        Text(String(format: "%.1fs", show.changeInterval))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.semibold))

                    Slider(value: $show.changeInterval, in: 0.2...10, step: 0.1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Transition", systemImage: show.transitionStyle.symbolName)
                        Spacer()
                        Picker("Transition", selection: $show.transitionStyle) {
                            ForEach(HueTransitionStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .font(.subheadline.weight(.semibold))

                    Text(show.transitionStyle.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var colorsPanel: some View {
        ControlPanel(title: "Colors", symbolName: "paintpalette.fill") {
            VStack(spacing: 10) {
                ForEach(show.colors) { swatch in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(swatch.color)
                            .frame(width: 42, height: 42)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            }

                        ColorPicker("Color", selection: colorBinding(for: swatch.id), supportsOpacity: false)
                            .labelsHidden()

                        Spacer()

                        Button {
                            show.removeColor(id: swatch.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3.weight(.bold))
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(show.colors.count > 1 ? .red : .secondary)
                        .disabled(show.colors.count <= 1)
                    }
                    .frame(minHeight: 46)
                }

                Button {
                    show.addColor()
                } label: {
                    Label("Add Color", systemImage: "plus.circle.fill")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.teal)
            }
        }
    }

    private var startPanel: some View {
        VStack(spacing: 10) {
            if show.isRunning {
                ProgressView(value: Double(max(0, show.remainingSeconds)), total: max(1, show.showDuration))
                    .tint(.green)
                Text("\(show.remainingSeconds)s")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Button {
                if show.isRunning {
                    show.stopShow()
                } else {
                    show.startShow()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: show.isRunning ? "stop.fill" : "play.fill")
                    Text(show.isRunning ? "STOP" : "START")
                }
                .font(.title2.weight(.black))
                .frame(maxWidth: .infinity, minHeight: 66)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .tint(show.isRunning ? .red : .green)
            .disabled(show.canStart == false && show.isRunning == false)
        }
    }

    private var bridgeSelection: Binding<String> {
        Binding {
            show.bridgeAddress
        } set: { newValue in
            if let bridge = show.bridges.first(where: { $0.displayName == newValue }) {
                show.selectBridge(bridge)
            } else {
                show.bridgeAddress = newValue
            }
        }
    }

    private func colorBinding(for id: UUID) -> Binding<Color> {
        Binding {
            show.colors.first(where: { $0.id == id })?.color ?? .white
        } set: { newColor in
            show.updateColor(id: id, to: newColor)
        }
    }
}

private struct ControlPanel<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbolName)
                .font(.headline.weight(.black))
                .foregroundStyle(.primary)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ActionButton: View {
    let title: String
    let symbolName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }
}

private struct LightSelectionRow: View {
    let light: HueLight
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isSelected ? .teal : .secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(light.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Label(light.isReachable ? "Reachable" : "Offline", systemImage: light.isReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(light.isReachable ? .green : .orange)

                        Text(light.isColorCapable ? "Color" : light.type)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(isSelected ? Color.teal.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.teal.opacity(0.35) : Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct StatusStrip: View {
    let message: String
    let isBusy: Bool
    let isPaired: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: isPaired ? "checkmark.seal.fill" : "info.circle.fill")
                    .foregroundStyle(isPaired ? .green : .secondary)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
