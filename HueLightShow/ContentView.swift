import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var show = HueShowController()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerPanel
                    startPanel
                    showPanel
                    lightPanel
                    bridgePanel
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Hue Light Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
        .tint(.blue)
    }

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hue Light Show")
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(show.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: show.isPaired ? "checkmark.seal.fill" : "link.badge.plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(show.isPaired ? .green : .secondary)
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 8) {
                InfoPill(title: "\(show.selectedLightCount)", subtitle: "Lights", symbolName: "lightbulb.led.fill")
                InfoPill(title: show.isInfiniteDuration ? "Inf" : "\(Int(show.showDuration))s", subtitle: "Duration", symbolName: show.isInfiniteDuration ? "infinity" : "timer")
                InfoPill(title: String(format: "%.1fs", show.changeInterval), subtitle: "Speed", symbolName: "speedometer")
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var startPanel: some View {
        VStack(spacing: 10) {
            if show.isRunning {
                HStack {
                    Label("Running", systemImage: "waveform.path.ecg")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.green)

                    Spacer()

                    Text(show.isInfiniteDuration ? "Infinite" : "\(show.remainingSeconds)s")
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                }

                if show.isInfiniteDuration == false {
                    ProgressView(value: Double(max(0, show.remainingSeconds)), total: max(1, show.showDuration))
                        .tint(.green)
                }
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

    private var showPanel: some View {
        ControlPanel(title: "Show", symbolName: "slider.horizontal.3") {
            VStack(spacing: 16) {
                Toggle(isOn: $show.isInfiniteDuration) {
                    Label("Infinite", systemImage: "infinity")
                        .font(.subheadline.weight(.semibold))
                }
                .toggleStyle(.switch)

                if show.isInfiniteDuration == false {
                    SliderRow(
                        title: "Duration",
                        symbolName: "timer",
                        valueText: "\(Int(show.showDuration))s",
                        value: $show.showDuration,
                        range: 5...3600,
                        step: 5
                    )
                }

                SliderRow(
                    title: "Change speed",
                    symbolName: "speedometer",
                    valueText: String(format: "%.1fs", show.changeInterval),
                    value: $show.changeInterval,
                    range: 0.2...10,
                    step: 0.1
                )

                HStack(spacing: 10) {
                    Label("Global transition", systemImage: show.transitionStyle.symbolName)
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Picker("Global transition", selection: $show.transitionStyle) {
                        ForEach(HueTransitionStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Global group", systemImage: "paintpalette.fill")
                        .font(.subheadline.weight(.black))

                    ColorPaletteEditor(
                        colors: show.colors,
                        addTitle: "Add Color",
                        colorBinding: { colorID in colorBinding(for: colorID) },
                        onAdd: { show.addColor() },
                        onRemove: { colorID in show.removeColor(id: colorID) }
                    )
                }
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
                            VStack(spacing: 8) {
                                LightSelectionRow(
                                    light: light,
                                    isSelected: show.isLightSelected(light.id),
                                    isCustom: show.usesCustomSettings(light.id)
                                ) {
                                    show.toggleLightSelection(light.id)
                                }

                                if show.isLightSelected(light.id) {
                                    PerLightSettingsView(
                                        isCustom: show.usesCustomSettings(light.id),
                                        transitionStyle: customTransitionBinding(for: light.id),
                                        colors: show.customColors(for: light.id),
                                        onToggleCustom: { show.toggleCustomSettings(for: light.id) },
                                        onAddColor: { show.addCustomColor(for: light.id) },
                                        colorBinding: { colorID in customColorBinding(for: light.id, colorID: colorID) },
                                        onRemoveColor: { colorID in show.removeCustomColor(lightID: light.id, colorID: colorID) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
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
                    Picker("Found bridges", selection: bridgeSelection) {
                        ForEach(show.bridges) { bridge in
                            Text(bridge.displayName).tag(bridge.displayName)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    ActionButton(title: "Find", symbolName: "magnifyingglass", tint: .blue) {
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
            }
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

    private func customTransitionBinding(for lightID: String) -> Binding<HueTransitionStyle> {
        Binding {
            show.customTransitionStyle(for: lightID)
        } set: { newStyle in
            show.setCustomTransitionStyle(newStyle, for: lightID)
        }
    }

    private func customColorBinding(for lightID: String, colorID: UUID) -> Binding<Color> {
        Binding {
            show.customColors(for: lightID).first(where: { $0.id == colorID })?.color ?? .white
        } set: { newColor in
            show.updateCustomColor(lightID: lightID, colorID: colorID, to: newColor)
        }
    }
}

private struct ControlPanel<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbolName)
                .font(.headline.weight(.black))
                .foregroundStyle(.primary)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct InfoPill: View {
    let title: String
    let subtitle: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.caption.weight(.black))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.monospacedDigit().weight(.black))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SliderRow: View {
    let title: String
    let symbolName: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbolName)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(valueText)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range, step: step)
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
    let isCustom: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(light.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(light.isReachable ? "Reachable" : "Offline")
                            .foregroundStyle(light.isReachable ? .green : .orange)

                        Text(light.isColorCapable ? "Color" : light.type)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Text(isCustom ? "Custom" : "Global")
                        .font(.caption.weight(.black))
                        .foregroundStyle(isCustom ? .blue : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color(.systemBackground), in: Capsule())
                }
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.10) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.blue.opacity(0.28) : Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PerLightSettingsView: View {
    let isCustom: Bool
    let transitionStyle: Binding<HueTransitionStyle>
    let colors: [HueShowColor]
    let onToggleCustom: () -> Void
    let onAddColor: () -> Void
    let colorBinding: (UUID) -> Binding<Color>
    let onRemoveColor: (UUID) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Label(isCustom ? "Custom" : "Global group", systemImage: isCustom ? "slider.horizontal.3" : "person.2.fill")
                    .font(.caption.weight(.black))

                Spacer()

                Button {
                    onToggleCustom()
                } label: {
                    Label(isCustom ? "Global" : "Custom", systemImage: isCustom ? "person.2.fill" : "slider.horizontal.3")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isCustom {
                HStack {
                    Label("Transition", systemImage: transitionStyle.wrappedValue.symbolName)
                        .font(.caption.weight(.bold))

                    Spacer()

                    Picker("Transition", selection: transitionStyle) {
                        ForEach(HueTransitionStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }

                ColorPaletteEditor(
                    colors: colors,
                    addTitle: "Add Custom Color",
                    colorBinding: colorBinding,
                    onAdd: onAddColor,
                    onRemove: onRemoveColor
                )
            }
        }
        .padding(.leading, 40)
        .padding(.trailing, 4)
    }
}

private struct ColorPaletteEditor: View {
    let colors: [HueShowColor]
    let addTitle: String
    let colorBinding: (UUID) -> Binding<Color>
    let onAdd: () -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(colors) { swatch in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(swatch.color)
                        .frame(width: 38, height: 38)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        }

                    ColorPicker("Color", selection: colorBinding(swatch.id), supportsOpacity: false)
                        .labelsHidden()

                    Spacer(minLength: 0)

                    Button {
                        onRemove(swatch.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3.weight(.bold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.count > 1 ? .secondary : Color(.tertiaryLabel))
                    .disabled(colors.count <= 1)
                    .accessibilityLabel("Remove color")
                }
                .frame(minHeight: 42)
            }

            Button(action: onAdd) {
                Label(addTitle, systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
