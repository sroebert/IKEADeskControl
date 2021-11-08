import Foundation
import ArgumentParser

struct RunCommand: ParsableCommand {
    
    // MARK: - Error
    
    private enum CommandError: Error, CustomStringConvertible {
        case invalidUUID
        case invalidMQTTURL
        
        var description: String {
            switch self {
            case .invalidUUID:
                return "The provided peripheral UUID is invalid."
            case .invalidMQTTURL:
                return "The provider MQTT url is invalid."
            }
        }
    }
    
    // MARK: - Properties
    
    static var configuration: CommandConfiguration {
        return CommandConfiguration(
            commandName: "IKEADeskControl",
            abstract: "Control an IKEA Idasen desk over MQTT.",
            version: "1.0"
        )
    }
    
    @Option(help: "The uuid of the beacon. If nil, the app will scan for a desk instead (MQTT will not work when scanning) (default: nil)", transform: {
        guard let uuid = UUID(uuidString: $0) else {
            throw CommandError.invalidUUID
        }
        return uuid
    })
    var uuid: UUID?
    
    @Option(help: "The url to use for connecting to the MQTT broker.", transform: {
        guard let url = URL(string: $0) else {
            throw CommandError.invalidMQTTURL
        }
        return url
    })
    var mqttURL: URL?
    
    @Option(help: "The username to use when connecting to the MQTT broker.")
    var mqttUsername: String?
    
    @Option(help: "The password to use when connecting to the MQTT broker.")
    var mqttPassword: String?
    
    // MARK: - ParsableCommand
    
    mutating func run() throws {
        App.run(
            peripheralUUID: uuid,
            mqttURL: mqttURL,
            mqttUsername: mqttUsername,
            mqttPassword: mqttPassword
        )
    }
}
