import Foundation

class LightningSDK {
    private let baseURL = "https://lightning.ai/v1"
    private let userId: String
    private let apiKey: String
    private let teamspaceId: String
    
    init(userId: String, apiKey: String, teamspaceId: String) {
        self.userId = userId
        self.apiKey = apiKey
        self.teamspaceId = teamspaceId
    }
    
    private func getAuthHeader() -> String {
        let credentials = "\(userId):\(apiKey)"
        let encodedCredentials = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encodedCredentials)"
    }
    
    private func makeRequest(method: String, path: String, params: [String: String]? = nil, body: [String: Any]? = nil) async throws -> (Data, URLResponse) {
        guard !userId.isEmpty, !apiKey.isEmpty, !teamspaceId.isEmpty else {
            throw NSError(domain: "LightningSDK", code: 401, userInfo: [NSLocalizedDescriptionKey: "Lightning API credentials are not set. Please check the Settings."])
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)\(path)")!
        if let params = params {
            urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = method
        request.addValue(getAuthHeader(), forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let jsonResult = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let errorMessage = jsonResult["message"] as? String {
                throw NSError(domain: "LightningSDK", code: (response as? HTTPURLResponse)?.statusCode ?? 500,
                              userInfo: [NSLocalizedDescriptionKey: errorMessage])
            } else {
                throw NSError(domain: "LightningSDK", code: (response as? HTTPURLResponse)?.statusCode ?? 500,
                              userInfo: [NSLocalizedDescriptionKey: "An error occurred with the request"])
            }
        }
        
        // // Print debug information
        // print("> \(method) \(path)")
        // if let jsonResult = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
        //     print(jsonResult)
        // } else {
        //     print("\(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        // }
        // print("----------------------")

        return (data, response)
    }
    
    func getStudioInfo(name: String) async throws -> [String: Any] {
        let (data, _) = try await makeRequest(method: "GET", path: "/projects/\(teamspaceId)/cloudspaces", params: ["name": name])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let cloudspaces = json["cloudspaces"] as! [[String: Any]]
        guard let studioInfo = cloudspaces.first else {
            throw NSError(domain: "LightningSDK", code: 404, userInfo: [NSLocalizedDescriptionKey: "Studio not found"])
        }
        return studioInfo
    }
    
    func getStatus(name: String) async throws -> String {
        let studioInfo = try await getStudioInfo(name: name)
        let studioId = studioInfo["id"] as! String
        let (data, _) = try await makeRequest(method: "GET", path: "/projects/\(teamspaceId)/cloudspaces/\(studioId)/codestatus")
        let status = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return getSimplifiedStatus(status: status)
    }
    
    func getMachine(name: String) async throws -> String {
        let studioInfo = try await getStudioInfo(name: name)
        let studioId = studioInfo["id"] as! String
        let (data, _) = try await makeRequest(method: "GET", path: "/projects/\(teamspaceId)/cloudspaces/\(studioId)/codeconfig")
        let config = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard let computeConfig = config["computeConfig"] as? [String: Any] else {
            throw NSError(domain: "LightningSDK", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to retrieve compute configuration"])
        }
        return computeConfig["name"] as! String
    }
    
    func switchMachine(name: String, machineType: String) async throws {
        let studioInfo = try await getStudioInfo(name: name)
        let studioId = studioInfo["id"] as! String
        let body: [String: Any] = [
            "computeConfig": [
                "name": machineType,
                "spot": false
            ]
        ]
        let (_, _) = try await makeRequest(method: "PUT", path: "/projects/\(teamspaceId)/cloudspaces/\(studioId)/codeconfig", body: body)
    }
    
    func startStudio(name: String, machineType: String) async throws {
        let studioInfo = try await getStudioInfo(name: name)
        let studioId = studioInfo["id"] as! String
        let body: [String: Any] = [
            "computeConfig": [
                "name": machineType,
                "spot": false
            ]
        ]
        let (_, _) = try await makeRequest(method: "POST", path: "/projects/\(teamspaceId)/cloudspaces/\(studioId)/start", body: body)
    }
    
    func stopStudio(name: String) async throws {
        let studioInfo = try await getStudioInfo(name: name)
        let studioId = studioInfo["id"] as! String
        let (_, _) = try await makeRequest(method: "POST", path: "/projects/\(teamspaceId)/cloudspaces/\(studioId)/stop", body: [:])
    }
    
    private func getSimplifiedStatus(status: [String: Any]) -> String {
        if let requested = status["requested"] as? [String: Any], !requested.isEmpty {
            return "PENDING"
        }
        
        guard let inUse = status["inUse"] as? [String: Any] else {
            return "STOPPED"
        }
        
        let phase = inUse["phase"] as! String
        
        switch phase {
        case "CLOUD_SPACE_INSTANCE_STATE_PENDING":
            return "PENDING"
        case "CLOUD_SPACE_INSTANCE_STATE_RUNNING":
            guard let startupStatus = inUse["startupStatus"] as? [String: Any] else {
                return "UNKNOWN"
            }
            return (startupStatus["topUpRestoreFinished"] as! Bool) ? "RUNNING" : "INITIALIZING"
        case "CLOUD_SPACE_INSTANCE_STATE_STOPPING":
            return "STOPPING"
        case "CLOUD_SPACE_INSTANCE_STATE_FAILED":
            return "FAILED"
        default:
            return "UNKNOWN"
        }
    }
}
