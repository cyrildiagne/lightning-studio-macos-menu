import SwiftUI

@main
struct LightningStudioApp: App {
    @StateObject private var viewModel = LightningViewModel()
    @Environment(\.openSettings) private var openSettings
    
    var body: some Scene {
        MenuBarExtra {
            LightningMenu(viewModel: viewModel)
            .onAppear {
                if (viewModel.userId.isEmpty || viewModel.apiKey.isEmpty || viewModel.teamspaceId.isEmpty || viewModel.studioName.isEmpty) {
                    openSettings()
                }
            }
        } label: {
            viewModel.menuBarImage
        }
        
        Settings {
            SettingsView(viewModel: viewModel)
        }
        .onChange(of: viewModel.alertError) { error in
            if error != nil {
                openSettings()
            }
        }
    }
}

struct LightningMenu: View {
    @ObservedObject var viewModel: LightningViewModel
    
    var body: some View {
        VStack {
            Text(viewModel.studioName)
                //.font(.headline)
                .padding(.bottom, 5)

            if viewModel.currentStatus != "RUNNING" && viewModel.currentStatus != "STOPPED" {
                Text(viewModel.currentStatus)
            }
            
            if viewModel.currentStatus != "STOPPED" {
                Menu("Switch Machine") {
                    Button("CPU-4") {
                        viewModel.startStudio(machineType: "cpu-4")
                    }
                    .disabled(viewModel.currentMachine.lowercased().contains("cpu-4"))
                    
                    Button("L4") {
                        viewModel.startStudio(machineType: "l4")
                    }
                    .disabled(viewModel.currentMachine.lowercased().contains("l4"))
                    
                    Button("L40S") {
                        viewModel.startStudio(machineType: "l40s")
                    }
                    .disabled(viewModel.currentMachine.lowercased().contains("l40s"))
                }
            } else {
                Menu("Start") {
                    Button("CPU-4") { viewModel.startStudio(machineType: "cpu-4") }
                    Button("L4") { viewModel.startStudio(machineType: "l4") }
                    Button("L40S") { viewModel.startStudio(machineType: "l40s") }
                }
            }
            
            Button("Stop") {
                viewModel.stopStudio()
            }
            .disabled(viewModel.currentStatus != "RUNNING")
            
            Divider()
            
            SettingsLink()
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
