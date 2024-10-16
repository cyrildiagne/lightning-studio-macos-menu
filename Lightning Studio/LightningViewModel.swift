import SwiftUI
import UserNotifications

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
    @Published var studios: [[String: String]] = []
    @Published var selectedStudio: String = ""
    
    @AppStorage("LIGHTNING_USER_ID") public var userId = ""
    @AppStorage("LIGHTNING_API_KEY") public var apiKey = ""
    @AppStorage("LIGHTNING_TEAMSPACE_ID") public var teamspaceId = ""
    @AppStorage("LIGHTNING_STUDIO_NAME") public var studioName = ""
    @AppStorage("LIGHTNING_REFRESH_PERIOD") public var refreshPeriod: Double = 30
    @AppStorage("LIGHTNING_FAST_REFRESH_PERIOD") public var fastRefreshPeriod: Double = 5
    
    private var lightningSDK: LightningSDK!
    private var regularStatusUpdateTimer: Timer?
    private var fastStatusUpdateTimer: Timer?
    private var previousStatus: String = "UNKNOWN"
    
    init() {
        setupSDK()
        setupStatusUpdateTimers()
        fetchStudios()
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
            return Image(systemName: "bolt.badge.clock")
        case "INITIALIZING":
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
    
    func setupStatusUpdateTimers() {
        regularStatusUpdateTimer?.invalidate()
        fastStatusUpdateTimer?.invalidate()
        
        regularStatusUpdateTimer = Timer.scheduledTimer(withTimeInterval: refreshPeriod, repeats: true) { [weak self] _ in
            Task { await self?.updateStatus() }
        }
        
        if currentStatus != "STOPPED" && currentStatus != "RUNNING" {
            startFastStatusUpdateTimer()
        }
    }
    
    private func startFastStatusUpdateTimer() {
        print("Starting fast status update timer with interval: \(fastRefreshPeriod)")
        fastStatusUpdateTimer?.invalidate()
        fastStatusUpdateTimer = Timer.scheduledTimer(withTimeInterval: fastRefreshPeriod, repeats: true) { [weak self] _ in
            Task { await self?.updateStatusAndCheckTransition() }
        }
    }
    
    @MainActor
    func updateStatusAndCheckTransition() async {
        await updateStatus()
        
        if currentStatus == "STOPPED" || currentStatus == "RUNNING" {
            print("Stopping fast status update timer")
            fastStatusUpdateTimer?.invalidate()
            fastStatusUpdateTimer = nil
        }
    }
    
    @MainActor
    func updateStatus() async {
        guard !selectedStudio.isEmpty else { return }
        
        do {
            let newStatus = try await lightningSDK.getStatus(name: selectedStudio)
            print("Current status: \(newStatus)")
            currentMachine = try await lightningSDK.getMachine(name: selectedStudio)
            
            // Check if we need to start or stop the fast timer
            if (newStatus != "STOPPED" && newStatus != "RUNNING") && fastStatusUpdateTimer == nil {
                startFastStatusUpdateTimer()
            } else if (newStatus == "STOPPED" || newStatus == "RUNNING") && fastStatusUpdateTimer != nil {
                fastStatusUpdateTimer?.invalidate()
                fastStatusUpdateTimer = nil
            }
            
            // Check if status has changed to STOPPED or RUNNING
            if (newStatus == "STOPPED" || newStatus == "RUNNING") && newStatus != previousStatus {
                triggerNotification(for: newStatus)
            }
            
            currentStatus = newStatus
            previousStatus = newStatus
            alertError = nil
            
            // Update the status in the studios array
            if let index = studios.firstIndex(where: { $0["name"] == selectedStudio }) {
                studios[index]["status"] = newStatus
            }
        } catch {
            alertError = AlertError(message: error.localizedDescription)
            print("Failed to get status: \(error)")
        }
    }
    
    private func triggerNotification(for status: String) {
        let content = UNMutableNotificationContent()
        content.title = selectedStudio
        
        if status == "STOPPED" {
            content.body = "Studio is stopped."
        } else if status == "RUNNING" {
            content.body = "Studio is running on \(currentMachine)."
        }
        
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending notification: \(error)")
            }
        }
    }
    
    func switchMachine(machineType: String) {
        Task {
            do {
                try await lightningSDK.switchMachine(name: selectedStudio, machineType: machineType)
                await updateStatus()
            } catch {
                await MainActor.run {
                    alertError = AlertError(message: "Failed to switch machine: \(error.localizedDescription)")
                }
                print("Failed to switch machine: \(error)")
            }
        }
    }
    
    func startStudio(machineType: String) {
        Task {
            do {
                try await lightningSDK.startStudio(name: selectedStudio, machineType: machineType)
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
                try await lightningSDK.stopStudio(name: selectedStudio)
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
        setupStatusUpdateTimers()
    }
    
    func updateFastRefreshPeriod(_ newPeriod: Double) {
        fastRefreshPeriod = newPeriod
        if fastStatusUpdateTimer != nil {
            startFastStatusUpdateTimer()
        }
    }
    
    func fetchStudios() {
        Task {
            do {
                let fetchedStudios = try await lightningSDK.listStudios()
                await MainActor.run {
                    self.studios = fetchedStudios
                    if self.selectedStudio.isEmpty && !fetchedStudios.isEmpty {
                        self.selectedStudio = fetchedStudios[0]["name"] ?? ""
                    }
                }
            } catch {
                await MainActor.run {
                    self.alertError = AlertError(message: "Failed to fetch studios: \(error.localizedDescription)")
                }
                print("Failed to fetch studios: \(error)")
            }
        }
    }
    
    func selectStudio(_ studioName: String) {
        selectedStudio = studioName
        Task {
            await updateStatus()
        }
    }
}
