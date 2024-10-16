import SwiftUI
import UserNotifications

@main
struct LightningStudioApp: App {
    @StateObject private var viewModel = LightningViewModel()
    @Environment(\.openSettings) private var openSettings
    
    init() {
        requestNotificationPermissions()
    }
    
    var body: some Scene {
        MenuBarExtra {
            LightningMenu(viewModel: viewModel)
            .onAppear {
                if (viewModel.userId.isEmpty || viewModel.apiKey.isEmpty || viewModel.teamspaceId.isEmpty || viewModel.studioName.isEmpty) {
                    openSettingsAndFocus()
                }
            }
        } label: {
            viewModel.menuBarImage
        }
        
        Settings {
            SettingsView(viewModel: viewModel)
        }
        .onChange(of: viewModel.alertError) {
            if viewModel.alertError != nil {
                openSettingsAndFocus()
            }
        }
    }
    
    private func openSettingsAndFocus() {
        openSettings()
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first(where: { $0.title == "Settings" }) {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if granted {
                        print("Notification permission granted")
                    } else if let error = error {
                        print("Error requesting notification permission: \(error)")
                    }
                }
            case .denied:
                print("Notification permission denied. Please enable it in Settings.")
                // Optionally, you can show an alert to the user explaining how to enable notifications
            case .authorized, .provisional, .ephemeral:
                print("Notification permission already granted")
            @unknown default:
                print("Unknown notification authorization status")
            }
        }
    }
}

struct LightningMenu: View {
    @ObservedObject var viewModel: LightningViewModel
    
    var body: some View {
        VStack {
            Menu(viewModel.selectedStudio.isEmpty ? "Select Studio" : viewModel.selectedStudio) {
                ForEach(viewModel.studios, id: \.self) { studio in
                    Button(action: {
                        viewModel.selectStudio(studio["name"] ?? "")
                    }) {
                        HStack {
                            Text(studio["name"] ?? "")
                            Spacer()
                            Text(studio["status"] ?? "")
                            if studio["name"] == viewModel.selectedStudio {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                Divider()
                
                Button("Refresh Studios") {
                    viewModel.fetchStudios()
                }
            }
            
            if viewModel.currentStatus != "RUNNING" && viewModel.currentStatus != "STOPPED" {
                Text(viewModel.currentStatus)
            }
            
            if viewModel.currentStatus != "STOPPED" {
                Menu("Switch Machine") {
                    Button("CPU-4") {
                        viewModel.switchMachine(machineType: "cpu-4")
                    }
                    .disabled(viewModel.currentMachine.lowercased().contains("cpu-4") || viewModel.currentStatus != "RUNNING")
                    
                    Button("L4") {
                        viewModel.switchMachine(machineType: "g6.4xlarge")
                    }
                    .disabled(viewModel.currentMachine.lowercased().contains("g6.4xlarge") || viewModel.currentStatus != "RUNNING")
                    
                    Button("L40S") {
                        viewModel.switchMachine(machineType: "g6e.4xlarge")
                    }
                    .disabled(viewModel.currentMachine.lowercased().contains("g6e.4xlarge") || viewModel.currentStatus != "RUNNING")
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
