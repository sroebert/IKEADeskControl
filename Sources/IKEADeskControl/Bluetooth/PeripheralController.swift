import Foundation
import CoreBluetooth

actor PeripheralController {
    
    // MARK: - Types
    
    enum ControllerError: Error {
        case bluetoothNotPoweredOn
        case cancelled
        case failedToConnect
        case disconnected
        case notConnectedToPeripheral
    }
    
    // MARK: - Public Vars
    
    let serviceUUID: CBUUID
    var peripheralUUID: UUID?
    
    // MARK: - Private Vars
    
    private var peripheral: CBPeripheral?
    
    private var onState: ((CBManagerState) async -> Void)?
    private var onDiscover: ((CBPeripheral) async -> Void)?
    private var onDisconnect: (() async -> Void)?
    private var onCharacteristicUpdate: ((CBCharacteristic) async -> Void)?
    
    private let manager: CBCentralManager
    private let delegate: Delegate
    
    private var isConnected = false
    
    private var activeTask: Task<Void, Error>?
    private var activeContinuation: CheckedContinuation<Void, Error>?
    
    private var readTask: Task<Void, Error>?
    private var readContinuation: CheckedContinuation<Void, Error>?
    private var readCharacteristic: CBCharacteristic?
    
    // MARK: - Lifecycle
    
    init(serviceUUID: CBUUID, peripheralUUID: UUID?) async {
        self.serviceUUID = serviceUUID
        self.peripheralUUID = peripheralUUID
        
        delegate = Delegate()
        manager = CBCentralManager(
            delegate: delegate,
            queue: nil
        )
        
        setupDelegate()
    }
    
    deinit {
        if manager.isScanning {
            manager.stopScan()
        }
        
        if isConnected, let peripheral = peripheral {
            manager.cancelPeripheralConnection(peripheral)
        }
    }
    
    private func setupDelegate() {
        delegate.onStateUpdate = { [weak self] in
            await self?.onStateUpdate($0)
        }
        
        delegate.onDiscover = { [weak self] peripheral, _, _ in
            await self?.onDiscover(peripheral)
        }
        
        delegate.onConnect = { [weak self] in
            await self?.onConnect()
        }
        
        delegate.onDisconnect = { [weak self] in
            await self?.onDisconnect(error: $0)
        }
        
        delegate.onFailedToConnect = { [weak self] in
            await self?.onFailToConnect(error: $0)
        }
        
        delegate.onTaskResult = { [weak self] in
            await self?.handleTaskResult(error: $0)
        }
        
        delegate.onCharacteristicUpdate = { [weak self] in
            await self?.onCharacteristicUpdate($0, error: $1)
        }
    }
    
    // MARK: - Actions
    
    func findPeripheral() async throws {
        guard manager.state == .poweredOn, !manager.isScanning else {
            throw ControllerError.bluetoothNotPoweredOn
        }
        
        if let peripheralUUID = peripheralUUID, let peripheral = manager.retrievePeripherals(withIdentifiers: [peripheralUUID]).first {
            await onDiscover(peripheral)
            return
        }
        
        manager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
    
    func connect() async throws {
        guard !isConnected, let peripheral = peripheral else {
            return
        }
        
        guard manager.state == .poweredOn else {
            throw ControllerError.bluetoothNotPoweredOn
        }
        
        try await performTask {
            Task {
                await MainActor.run {
                    self.manager.connect(peripheral, options: [
                        CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
                    ])
                }
            }
        }
        
        isConnected = true
    }
    
    func discoverServices(_ services: [CBUUID]?) async throws {
        failTask(with: ControllerError.cancelled)
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        try await performTask {
            peripheral.discoverServices(services)
        }
    }
    
    func discoverCharacteristics(_ characteristics: [CBUUID]?, for service: CBService) async throws {
        failTask(with: ControllerError.cancelled)
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        try await performTask {
            peripheral.discoverCharacteristics(characteristics, for: service)
        }
    }
    
    func discoverDescriptors(for characteristic: CBCharacteristic) async throws {
        failTask(with: ControllerError.cancelled)
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        try await performTask {
            peripheral.discoverDescriptors(for: characteristic)
        }
    }
    
    func readValue(for characteristic: CBCharacteristic) async throws {
        readContinuation?.resume(throwing: ControllerError.cancelled)
        readContinuation = nil
        readCharacteristic = nil
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        if let task = readTask {
            return try await task.value
        }
        
        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                readContinuation = continuation
                peripheral.readValue(for: characteristic)
            }
        }
        
        readTask = task
        readCharacteristic = characteristic
        defer {
            readTask = nil
            readCharacteristic = nil
        }
        
        try await task.value
    }
    
    func writeValue(_ data: Data, for characteristic: CBCharacteristic) async throws {
        failTask(with: ControllerError.cancelled)
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        try await performTask {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }
    
    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) async throws {
        failTask(with: ControllerError.cancelled)
        
        guard let peripheral = peripheral, isConnected else {
            throw ControllerError.notConnectedToPeripheral
        }
        
        try await performTask {
            peripheral.setNotifyValue(enabled, for: characteristic)
        }
    }
    
    // MARK: - Register Events
    
    func onState(_ onState: @escaping (CBManagerState) async -> Void) {
        self.onState = onState
    }
    
    func onDiscover(_ onDiscover: @escaping (CBPeripheral) async -> Void) {
        self.onDiscover = onDiscover
    }
    
    func onDisconnect(_ onDisconnect: @escaping () async -> Void) {
        self.onDisconnect = onDisconnect
    }
    
    func onCharacteristicUpdate(_ onCharacteristicUpdate: @escaping (CBCharacteristic) async -> Void) {
        self.onCharacteristicUpdate = onCharacteristicUpdate
    }
    
    // MARK: - Events
    
    private func onStateUpdate(_ state: CBManagerState) async {
        await onState?(state)
    }
    
    private func onDiscover(_ peripheral: CBPeripheral) async {
        guard self.peripheral == nil else {
            return
        }
        
        self.peripheral = peripheral
        peripheral.delegate = delegate
        
        manager.stopScan()
        
        await onDiscover?(peripheral)
    }
    
    private func onConnect() {
        completeTask()
    }
    
    private func onDisconnect(error: Error?) async {
        failTask(with: error ?? ControllerError.disconnected)
        
        guard isConnected else {
            return
        }
        
        isConnected = false
        await onDisconnect?()
    }
    
    private func onFailToConnect(error: Error?) async {
        failTask(with: error ?? ControllerError.failedToConnect)
    }
    
    private func handleTaskResult(error: Error?) {
        if let error = error {
            failTask(with: error)
        } else {
            completeTask()
        }
    }
    
    private func onCharacteristicUpdate(_ characteristic: CBCharacteristic, error: Error?) async {
        if let error = error {
            failTask(with: error)
        } else {
            if readCharacteristic == characteristic {
                readContinuation?.resume()
                readContinuation = nil
            }
            
            await onCharacteristicUpdate?(characteristic)
        }
    }
    
    // MARK: - Utils
    
    private func performTask(_ action: @escaping () -> Void) async throws {
        if let task = activeTask {
            return try await task.value
        }
        
        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                activeContinuation = continuation
                action()
            }
        }
        
        activeTask = task
        defer {
            activeTask = nil
        }
        
        try await task.value
    }
    
    private func completeTask() {
        activeContinuation?.resume()
        activeContinuation = nil
    }
    
    private func failTask(with error: Error) {
        activeContinuation?.resume(throwing: error)
        activeContinuation = nil
    }
    
    // MARK: - Delegate
    
    private final class Delegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
        // MARK: - Public Vars
        
        var onStateUpdate: ((CBManagerState) async -> Void)?
        
        var onDiscover: ((CBPeripheral, [String: Any], NSNumber) async -> Void)?
        
        var onConnect: (() async -> Void)?
        var onDisconnect: ((Error?) async -> Void)?
        var onFailedToConnect: ((Error?) async -> Void)?
        
        var onTaskResult: ((Error?) async -> Void)?
        
        var onCharacteristicUpdate: ((CBCharacteristic, Error?) async -> Void)?
        
        // MARK: - Utils
        
        private func handleTaskResult(error: Error?) {
            Task {
                await onTaskResult?(error)
            }
        }
        
        // MARK: - CBCentralManagerDelegate
        
        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            let state = central.state
            Task {
                await onStateUpdate?(state)
            }
        }
        
        func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
            Task {
                await onDiscover?(peripheral, advertisementData, RSSI)
            }
        }
        
        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            Task {
                await onConnect?()
            }
        }
        
        func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            Task {
                await onFailedToConnect?(error)
            }
        }
        
        func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
            Task {
                await onDisconnect?(error)
            }
        }
        
        // MARK: - CBPeripheralDelegate
        
        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            handleTaskResult(error: error)
        }
        
        func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
            handleTaskResult(error: error)
        }
        
        func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
            handleTaskResult(error: error)
        }
        
        func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
            Task {
                await onCharacteristicUpdate?(characteristic, error)
            }
        }
        
        func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
            handleTaskResult(error: error)
        }
        
        func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
            handleTaskResult(error: error)
        }
    }
}
