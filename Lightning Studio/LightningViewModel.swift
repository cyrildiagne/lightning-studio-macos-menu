import SwiftUI

struct AlertError: Identifiable, Equatable {
    let id = UUID()
    let message: String
    
    static func == (lhs: AlertError, rhs: AlertError) -> Bool {
        lhs.id == rhs.id && lhs.message == rhs.message
    }
}

class LightningViewModel: ObservableObject {
    @Published var currentStatus = "UNKNOWN"
    @Published var currentMachine = "UNKNOWN"
    @Published var alertError: AlertError?
    
    @AppStorage("LIGHTNING_USER_ID") public var userId = ""
    @AppStorage("LIGHTNING_API_KEY") public var apiKey = ""
    @AppStorage("LIGHTNING_TEAMSPACE_ID") public var teamspaceId = ""
    @AppStorage("LIGHTNING_STUDIO_NAME") public var studioName = ""
    @AppStorage("LIGHTNING_REFRESH_PERIOD") public var refreshPeriod: Double = 30
    
    private var lightningSDK: LightningSDK!
    private var statusUpdateTimer: Timer?
    
    init() {
        setupSDK()
        setupStatusUpdateTimer()
        Task {
            await updateStatus()
        }
    }
    
    public func areSettingsOK() -> Bool {
        return !userId.isEmpty && !apiKey.isEmpty && !teamspaceId.isEmpty && !studioName.isEmpty
    }
    
    private func loadStudioName() {
        studioName = UserDefaults.standard.string(forKey: "LIGHTNING_STUDIO_NAME") ?? "Unknown Studio"
    }
    
    func saveStudioName(_ name: String) {
        studioName = name
        UserDefaults.standard.set(name, forKey: "LIGHTNING_STUDIO_NAME")
    }
    
    private func setupSDK() {
        self.lightningSDK = LightningSDK(userId: userId, apiKey: apiKey, teamspaceId: teamspaceId)
    }
    
    var menuBarImage: Image {
        switch currentStatus {
        case "STOPPED":
            return Image(systemName: "bolt.slash.fill")
        case "PENDING", "STOPPING":
            return Image(systemName: "bolt.badge.clock.fill")
        case "RUNNING":
            if currentMachine.lowercased() == "unknown" {
                return Image(systemName: "questionmark.circle")
            }
            return currentMachine.lowercased().contains("cpu") ?
                Image(systemName: "bolt.fill") :
                Image(systemName: "cpu")
        default:
            return Image(systemName: "questionmark.circle")
        }
    }
    
    func setupStatusUpdateTimer() {
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: refreshPeriod, repeats: true) { [weak self] _ in
            Task { await self?.updateStatus() }
        }
    }
    
    @MainActor
    func updateStatus() async {
        do {
            currentStatus = try await lightningSDK.getStatus(name: studioName)
            print("Current status: \(currentStatus)")
            currentMachine = try await lightningSDK.getMachine(name: studioName)
            alertError = nil
        } catch {
            alertError = AlertError(message: error.localizedDescription)
            print("Failed to get status: \(error)")
        }
    }
    
    func startStudio(machineType: String) {
        Task {
            do {
                try await lightningSDK.startStudio(name: studioName, machineType: machineType)
                await updateStatus()
            } catch {
                await MainActor.run {
                    alertError = AlertError(message: "Failed to start studio: \(error.localizedDescription)")
                }
                print("Failed to start studio: \(error)")
            }
        }
    }
    
    func stopStudio() {
        Task {
            do {
                try await lightningSDK.stopStudio(name: studioName)
                await updateStatus()
            } catch {
                await MainActor.run {
                    alertError = AlertError(message: "Failed to stop studio: \(error.localizedDescription)")
                }
                print("Failed to stop studio: \(error)")
            }
        }
    }
    
    func updateRefreshPeriod(_ newPeriod: Double) {
        refreshPeriod = newPeriod
        setupStatusUpdateTimer()
    }
}
