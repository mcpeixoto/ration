import Foundation
import RationKit

/// The CLI's view of the settings file.
///
/// The model itself lives in `RationKit` so `ration` and `ration-tray` read and
/// write one file rather than two that drift apart.
typealias CLIConfig = AppConfig
