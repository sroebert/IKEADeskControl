import Foundation
import Logging
import MQTTNIO

struct App {
    
    // MARK: - Private Vars
    
    private static var deskController: DeskController!
    private static var mqttController: MQTTController!
    
    // MARK: - Main
    
    static func run(
        peripheralUUID: UUID?,
        mqttURL: URL?,
        mqttUsername: String?,
        mqttPassword: String?
    ) {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            
            #if DEBUG
            handler.logLevel = .debug
            #else
            handler.logLevel = .info
            #endif
            
            return handler
        }
        
        Task {
            deskController = await DeskController(
                peripheralUUID: peripheralUUID
            )
            
            let credentials: MQTTConfiguration.Credentials?
            if let username = mqttUsername, let password = mqttPassword {
                credentials = .init(username: username, password: password)
            } else {
                credentials = nil
            }
            
            guard let peripheralUUID = peripheralUUID, let mqttURL = mqttURL else {
                await deskController.start()
                return
            }
            
            mqttController = await MQTTController(
                peripheralUUID: peripheralUUID,
                url: mqttURL,
                credentials: credentials
            )
            
            await deskController.onConnected {
                await mqttController.deskDidConnect(deskState: $0)
            }
            
            await deskController.onDisconnected {
                await mqttController.deskDidDisconnect()
            }
            
            await deskController.onDeskState {
                await mqttController.didReceiveDeskState($0)
            }
            
            await mqttController.onCommand { command in
                switch command {
                case .stop:
                    try? await deskController.stop()
                    
                case .moveTo(let position):
                    try? await deskController.move(toPosition: position)
                    
                case .open:
                    try? await deskController.move(toPosition: DeskController.maximumDeskPosition)
                    
                case .close:
                    try? await deskController.move(toPosition: DeskController.minimumDeskPosition)
                }
            }
            
            await mqttController.start()
            await deskController.start()
        }
        
        RunLoop.main.run()
    }
}
