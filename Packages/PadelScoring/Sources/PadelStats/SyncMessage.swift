/// Keys and message types of the watch ↔ iPhone transfer (WatchConnectivity dictionaries).
public enum SyncMessage {
    public static let typeKey = "type"
    public static let matchesKey = "matches"
    public static let idsKey = "ids"

    /// Payload: `matchesKey` → JSON `[MatchSummary]` (see `MatchSummary.encodeList`).
    public static let upsert = "upsert"
    /// Payload: `idsKey` → `[String]` (UUIDs).
    public static let delete = "delete"
    /// iPhone → watch: please send the whole history.
    public static let requestAll = "requestAll"
}
