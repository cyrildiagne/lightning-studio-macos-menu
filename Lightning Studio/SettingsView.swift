import SwiftUI

struct SettingsView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: LightningViewModel
    
    @State private var showAlert = false
    
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
                LightningStudioSettingsView(userId: $viewModel.userId, apiKey: $viewModel.apiKey, teamspaceId: viewModel.$teamspaceId, studioName: $viewModel.studioName)
                    .tabItem {
                        Label("Lightning Studio", systemImage: "bolt.fill")
                    }
                
                SystemSettingsView(viewModel: viewModel)
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
}

struct LightningStudioSettingsView: View {
    @Binding var userId: String
    @Binding var apiKey: String
    @Binding var teamspaceId: String
    @Binding var studioName: String
    
    var body: some View {
        Form {
            Section(header: Text("Lightning API Credentials")) {
                TextField("User ID", text: $userId)
                SecureField("API Key", text: $apiKey)
            }
            
            Spacer().frame(height: 20)
            
            Section(header: Text("Studio Configuration")) {
                TextField("Teamspace ID", text: $teamspaceId)
                TextField("Studio Name", text: $studioName)
            }
        }
    }
}

struct SystemSettingsView: View {
    @ObservedObject var viewModel: LightningViewModel
    @State private var tempRefreshPeriod: Double

    init(viewModel: LightningViewModel) {
        self.viewModel = viewModel
        _tempRefreshPeriod = State(initialValue: viewModel.refreshPeriod)
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
                .onChange(of: tempRefreshPeriod) { newValue in
                    viewModel.updateRefreshPeriod(newValue)
                }
            }
        }
    }
}
