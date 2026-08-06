import Foundation
import Observation
import RationUI
import Sparkle

/// Wraps Sparkle so the rest of the app can stay unaware of it.
///
/// Updates are downloaded from GitHub Releases and verified against an EdDSA
/// public key baked into the app bundle. An update that is not signed by the
/// matching private key is refused — a compromised download host cannot ship
/// you a modified Ration.
@MainActor
@Observable
final class UpdateController: UpdateControlling {

    private let controller: SPUStandardUpdaterController?

    init() {
        // Sparkle needs a real bundle with a feed URL. `swift run` produces a
        // bare executable, so skip rather than trap at launch.
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var canCheck: Bool { controller != nil }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    func checkNow() {
        controller?.checkForUpdates(nil)
    }
}
