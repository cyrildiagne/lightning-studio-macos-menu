import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: LightningViewModel
    
    @State private var showAlert = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    
    var body: some View {
        VStack {
            if let error = viewModel.alertError {
                Text(error.message)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.bottom)
            }
            
            TabView {
                LightningStudioSettingsView(userId: $viewModel.userId, apiKey: $viewModel.apiKey, teamspaceId: viewModel.$teamspaceId)
                    .tabItem {
                        Label("Studio", systemImage: "bolt.fill")
                    }
                
                SystemSettingsView(viewModel: viewModel, notificationStatus: $notificationStatus)
                    .tabItem {
                        Label("System", systemImage: "gear")
                    }
            }
        }
        .frame(width: 400)
        .padding()
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Configuration Incomplete"),
                message: Text("Please fill in all required fields before closing the settings window."),
                dismissButton: .default(Text("OK")) {
                    openSettings()
                }
            )
        }
        .onAppear {
            checkNotificationStatus()
        }
        .onDisappear {
            if !viewModel.areSettingsOK() {
                showAlert = true
                DispatchQueue.main.async {
                    openSettings()
                }
            }
            Task {
                await viewModel.updateStatus()
            }
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }
}

struct LightningStudioSettingsView: View {
    @Binding var userId: String
    @Binding var apiKey: String
    @Binding var teamspaceId: String
    
    var body: some View {
        Form {
            Section(header: Text("Lightning API Credentials")) {
                TextField("User ID", text: $userId)
                SecureField("API Key", text: $apiKey)
                TextField("Teamspace ID", text: $teamspaceId)
            }
        }
    }
}

struct SystemSettingsView: View {
    @ObservedObject var viewModel: LightningViewModel
    @State private var tempRefreshPeriod: Double
    @Binding var notificationStatus: UNAuthorizationStatus

    init(viewModel: LightningViewModel, notificationStatus: Binding<UNAuthorizationStatus>) {
        self.viewModel = viewModel
        _tempRefreshPeriod = State(initialValue: viewModel.refreshPeriod)
        _notificationStatus = notificationStatus
    }

    var body: some View {
        Form {
            Section(header: Text("System Settings")) {
                LaunchAtLogin.Toggle()
                
                VStack(alignment: .leading) {
                    Text("Idle Refresh Period (seconds)")
                    HStack {
                        Slider(value: $tempRefreshPeriod, in: 5...300, step: 5)
                        Text("\(Int(tempRefreshPeriod))")
                    }
                }
                .onChange(of: tempRefreshPeriod) {
                    viewModel.updateRefreshPeriod(tempRefreshPeriod)
                }

                Divider()
                
                VStack(alignment: .leading) {
                    Text("Notifications")
                    HStack {
                        Text(notificationStatusText)
                        Spacer()
                        Button("Open Settings") {
                            openNotificationSettings()
                        }
                    }
                }
            }
        }
    }
    
    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized:
            return "Enabled"
        case .denied:
            return "Disabled"
        case .notDetermined:
            return "Not Determined"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }
    
    private func openNotificationSettings() {
        if let settingsUrl = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(settingsUrl)
        }
    }
}
