import SwiftUI

struct VisualizerSettingsView: View {
    @AppStorage("visualizerPaletteMode") private var paletteMode: String = "auto"
    @AppStorage("visualizerPrimaryColor") private var primaryColorHex: String = "#FF0055"
    @AppStorage("visualizerSecondaryColor") private var secondaryColorHex: String = "#00DDFF"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Visualizer Settings")
                .font(.headline)
            
            Picker("Palette Mode", selection: $paletteMode) {
                Text("Auto (Cover Art)").tag("auto")
                Text("Custom").tag("custom")
            }
            .pickerStyle(.radioGroup)
            
            if paletteMode == "custom" {
                ColorPicker("Primary Color", selection: Binding(
                    get: { Color(hex: primaryColorHex) },
                    set: { primaryColorHex = $0.toHex() ?? "#FF0055" }
                ))
                ColorPicker("Secondary Color", selection: Binding(
                    get: { Color(hex: secondaryColorHex) },
                    set: { secondaryColorHex = $0.toHex() ?? "#00DDFF" }
                ))
            }
        }
        .padding()
        .frame(width: 250)
    }
}
