import Foundation

/// Only a newly received, explicit notification reply may wait for startup.
/// Saved/uncertain replies are never replayed merely because a host reconnects.
public enum NotificationDelivery {
    public enum Decision: Equatable { case wait, send, keepSaved }
    public static func decision(for reply: PendingReply, endpoint: String?, hostIdentity: String?,
                                connected: Bool, paused: Bool, expired: Bool) -> Decision {
        guard !paused, endpoint == reply.endpoint else { return .keepSaved }
        if connected {
            return hostIdentity == reply.hostIdentity ? .send : .keepSaved
        }
        return expired ? .keepSaved : .wait
    }
}
