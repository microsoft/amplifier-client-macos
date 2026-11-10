import Foundation

@MainActor public final class ServiceConnection {
    public var registration: RegisteredService
    public private(set) var client: HostClient?
    public var latest: CompanionSnapshot?
    public private(set) var connected = false
    public private(set) var connecting = false
    public var status = "Not connected"
    public var previews: [String: String] = [:]
    public var workLabels: [String: WorkPreview] = [:]
    public var previewAttempts = Set<String>()
    public var detailRequests = Set<String>()
    public var nextWorkDetail = 0
    private var poll: Task<Void, Never>?
    private var generation = UUID()
    public var onSnapshot: ((ServiceConnection, CompanionSnapshot, HostClient) -> Void)?
    public var onChange: (() -> Void)?
    public init(_ registration: RegisteredService) { self.registration = registration }
    public func owns(_ client: HostClient) -> Bool { self.client === client }
    public func stop() {
        generation = UUID(); poll?.cancel(); poll = nil; client?.cancelRequests(); client = nil
        connected = false; connecting = false
        // Preserve last observations while unavailable, but never count them as current.
        detailRequests = []; previews = [:]; previewAttempts = []; workLabels = [:]
        status = registration.paused ? "Disconnected" : "Not connected"
        onChange?()
    }
    public func start(clientID: String, token: @escaping (String) async throws -> String?,
                      makeClient: @escaping (Endpoint, String, String) -> HostClient = { HostClient(endpoint: $0, token: $1, clientID: $2) }) {
        stop()
        guard !registration.paused else { return }
        connecting = true; status = "Connecting…"; onChange?()
        let ticket = generation, address = registration.address
        poll = Task { [weak self] in
            do {
                guard let credential = try await token(address), !credential.isEmpty else { throw CompanionError.rejected(401) }
                guard let self, !Task.isCancelled, self.generation == ticket else { return }
                let client = makeClient(self.registration.endpoint, credential, clientID)
                self.client = client
                var delay: UInt64 = 2
                while !Task.isCancelled && self.generation == ticket {
                    do {
                        try await client.attach()
                        while !Task.isCancelled && self.generation == ticket {
                            let value = try await client.snapshot()
                            guard !Task.isCancelled, self.generation == ticket else { return }
                            if let expected = self.registration.hostIdentity, expected != value.hostIdentity { throw CompanionError.changedService }
                            self.connected = true; self.connecting = false; self.latest = value
                            self.status = value.workingCount > 0 ? "\(value.workingCount) working" : "Ready"
                            self.onSnapshot?(self, value, client); self.onChange?(); delay = 2
                            try await Task.sleep(nanoseconds: 5_000_000_000)
                        }
                    } catch {
                        guard !Task.isCancelled, self.generation == ticket else { return }
                        self.connected = false; self.connecting = false; self.status = error.localizedDescription; self.onChange?()
                        try? await Task.sleep(nanoseconds: delay * 1_000_000_000); delay = min(delay * 2, 60)
                    }
                }
            } catch {
                guard let self, !Task.isCancelled, self.generation == ticket else { return }
                self.connecting = false; self.status = error.localizedDescription; self.onChange?()
            }
        }
    }
}

