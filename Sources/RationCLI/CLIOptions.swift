import Foundation

struct CLIOptions {
    let providerID: String?
    let interval: TimeInterval?
    let json: Bool
    let days: Int?
    let metric: String?
    let notify: Bool
    let args: [String]

    init(args: [String]) {
        var providerID: String?
        var interval: TimeInterval?
        var json = false
        var days: Int?
        var metric: String?
        var notify = false
        var index = 0
        while index < args.count {
            switch args[index] {
            case "--provider", "-p":
                index += 1
                if index < args.count { providerID = args[index] }
            case "--interval", "-i":
                index += 1
                if index < args.count { interval = TimeInterval(args[index]) }
            case "--days", "-d":
                index += 1
                if index < args.count { days = Int(args[index]) }
            case "--metric", "-m":
                index += 1
                if index < args.count { metric = args[index] }
            case "--json":
                json = true
            case "--notify":
                notify = true
            default:
                break
            }
            index += 1
        }
        self.providerID = providerID
        self.interval = interval
        self.json = json
        self.days = days
        self.metric = metric
        self.notify = notify
        self.args = args
    }

    var rangeDays: Int {
        let value = days ?? 30
        return [7, 30, 90].contains(value) ? value : 30
    }
}
