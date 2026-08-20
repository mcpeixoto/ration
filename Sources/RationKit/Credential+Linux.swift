#if os(Linux)

/// The credential store Ration uses on Linux.
///
/// Claude Code writes the OAuth blob to `~/.claude/.credentials.json`
/// (mode 0600), or under `CLAUDE_CONFIG_DIR` /
/// `CLAUDE_SECURESTORAGE_CONFIG_DIR` when those are set. There is no
/// keychain on this platform.
public typealias DefaultCredentialStore = FileCredentialStore

#endif
