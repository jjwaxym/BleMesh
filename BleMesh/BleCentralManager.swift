//
//  BleCentralManager.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation
import CoreBluetooth

protocol BleCentralManagerDelegate {
    var sessionId: UInt64 { get }
    var terminalId: BleTerminalId { get }
    var items: [BleItem] { get }
    
    func isKnown(item: BleItem) -> Bool
    func setKnown(item: BleItem)
    func setDetailsFor(item: BleItem)
    func didConnect(peripheral peripheralIdentifier: String)
    func didDisconnect(peripheral peripheralIdentifier: String)
    func didReceive(item: BleItem, data: Data, from peripheralIdentifier: String)
    func didResolveIdentifier(terminal:BleTerminalId, peripheralIdentifier: String)
    func isReceiving(item: BleItem, progress: UInt32)
    func coreBluetoothDidUbdateState(rawValue: Int)
}

class BleCentralManager : NSObject {
    
    private let delegate: BleCentralManagerDelegate
    private let queue: DispatchQueue
    private var centralManager: CBCentralManager!
    private var scanPending: Bool
    private var scanStopped: Bool
    private var serviceUUID: CBUUID!
    private var peers: [String : BlePeripheral]
    
    init(delegate: BleCentralManagerDelegate) {
        self.delegate = delegate
        peers = [String : BlePeripheral]()
        queue = DispatchQueue(label: "com.airfrance.afble.cmqueue")
        scanPending = false
        scanStopped = true
        super.init()
        centralManager = CBCentralManager(delegate: self,
                                          queue: DispatchQueue(label: "com.airfrance.afble.com.airfrance.cabble.cbcentralmanager"),
                                          options: [CBCentralManagerOptionShowPowerAlertKey:true])
    }
    
    func start() {
        scanStopped = false
        if centralManager.isScanning {
            BleLogger.debug("Already scanning")
            scanPending = false
        } else if centralManager.state == .poweredOn {
            scanPending = false
            serviceUUID = BleServices.serviceUUID(session: delegate.sessionId)
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
            BleLogger.debug("Starts scanning")
        } else {
            scanPending = true
            BleLogger.debug("Central Manager not powered on state \(centralManager.state)")
        }
    }
    
    func stop() {
        scanStopped = true
        centralManager.stopScan()
        for peer in peers.values {
            let peripheral = peer.peripheral
            if peripheral.state == .connected, let services = peripheral.services {
                for service in services {
                    if service.uuid.isEqual(serviceUUID), let characteristics = service.characteristics {
                        for characteristic in characteristics {
                            if characteristic.uuid.isEqual(BleServices.historyUUID()) ||
                                characteristic.uuid.isEqual(BleServices.headersUUID()) ||
                                characteristic.uuid.isEqual(BleServices.slicesUUID()) {
                                peripheral.setNotifyValue(false, for: characteristic)
                            }
                        }
                        break;
                    }
                }
                centralManager.cancelPeripheralConnection(peripheral)
            }
        }
        peers.removeAll()
    }
    
    private func requestNextSliceFrom(slices: BleItemSlices?, item: BleItem, peer: BlePeripheral) {
        guard let index = slices?.requestNext() else {
            return
        }
        let message = BleItemSliceMessage.sliceRequestMessageFor(terminalId: item.terminalId, itemIndex: item.itemIndex, sliceIndex: UInt16(index))
        send(message: message, history: false, to: peer)
    }
    
    private func send(message: Data, history: Bool, to peer: BlePeripheral) {
        var nextTrunk = false
        let trunks = history ? peer.historyTrunksManager.split(message: message) : peer.headersTrunksManager.split(message: message)
        objc_sync_enter(peer)
        if history {
            peer.historyTrunks.append(contentsOf: trunks)
        } else {
            peer.headersTrunks.append(contentsOf: trunks)
        }
        if (!peer.isSending) {
            peer.isSending = true
            nextTrunk = true
        }
        objc_sync_exit(peer)
        if nextTrunk {
            sendTrunk(history: history, to: peer)
        }
    }
    
    private func sendTrunk(history: Bool, to peer: BlePeripheral) {
        queue.async { [weak self] in
            if let manager = self, let services = peer.peripheral.services, let trunk = (history ? peer.historyTrunks.first : peer.headersTrunks.first) {
                for service in services {
                    if service.uuid.isEqual(manager.serviceUUID), let characteristics = service.characteristics {
                        let searchedCharacteristic = history ? BleServices.historyUUID() : BleServices.headersUUID()
                        for characteristic in characteristics {
                            if characteristic.uuid.isEqual(searchedCharacteristic) {
                                peer.peripheral.writeValue(trunk, for: characteristic, type: .withResponse)
                                return
                            }
                        }
                    }
                }
            }
        }
    }
}

extension BleCentralManager : CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        BleLogger.debug("Central Manager did update state: \(central.state)")
        delegate.coreBluetoothDidUbdateState(rawValue: central.state.rawValue)
        if central.state == .poweredOn {
            if scanPending {
                start()
            }
        } else {
            let wasStopped = scanStopped
            stop()
            if !wasStopped {
                start()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peers[peripheral.identifier.uuidString] == nil {
            BleLogger.debug("Central Manager did discover peripheral: \(peripheral.identifier.uuidString)")
            peers[peripheral.identifier.uuidString] = BlePeripheral(peripheral: peripheral)
        }
        if peripheral.state != .connecting && peripheral.state != .connected {
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        BleLogger.debug("Central Manager did connect peripheral: \(peripheral.identifier.uuidString)")
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        delegate.didConnect(peripheral: peripheral.identifier.uuidString)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        BleLogger.debug("Central Manager did fail to connect peripheral: \(peripheral.identifier.uuidString)")
        peers.removeValue(forKey: peripheral.identifier.uuidString)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        BleLogger.debug("Central Manager did disconnect peripheral: \(peripheral.identifier.uuidString)")
        peers.removeValue(forKey: peripheral.identifier.uuidString)
        delegate.didDisconnect(peripheral: peripheral.identifier.uuidString)
    }
}

extension BleCentralManager : CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            BleLogger.debug("Peripheral \(peripheral.identifier.uuidString) did fail to discover services: \(error!)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        guard let services = peripheral.services else {
            BleLogger.debug("Peripheral \(peripheral.identifier.uuidString) did fail to discover services: Empty services list")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        for service in services {
            if service.uuid.isEqual(serviceUUID) {
                BleLogger.debug("Peripheral \(peripheral.identifier.uuidString) did discover service")
                peripheral.discoverCharacteristics([BleServices.historyUUID(), BleServices.headersUUID(), BleServices.slicesUUID()], for: service)
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            BleLogger.debug("Peripheral \(peripheral.identifier.uuidString) did fail to discover characteristics: \(error!)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        guard let characteristics = service.characteristics else {
            BleLogger.debug("Peripheral \(peripheral.identifier.uuidString) did fail to discover characteristics: Empty characteristics list")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        for characteristic in characteristics {
            if characteristic.uuid.isEqual(BleServices.historyUUID()) {
                BleLogger.debug("Peripheral \(peripheral.identifier.uuidString) did discover history characteristic")
            } else if characteristic.uuid.isEqual(BleServices.headersUUID()) {
                BleLogger.debug("Peripheral \(peripheral.identifier.uuidString) did discover headers characteristic")
            } else if characteristic.uuid.isEqual(BleServices.slicesUUID()) {
                BleLogger.debug("Peripheral \(peripheral.identifier.uuidString) did discover slices characteristic")
            } else {
                continue
            }
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        BleLogger.debug("Peripheral \(peripheral.identifier.uuidString) did modify services")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil || !characteristic.isNotifying {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            BleLogger.debug("Peripheral \(peripheral.identifier.uuidString) did fail to update value: \(error!)")
            return
        }
        guard let peer = peers[peripheral.identifier.uuidString], let value = characteristic.value else {
            return
        }
        if characteristic.uuid.isEqual(BleServices.historyUUID()) {
            if let message = peer.historyTrunksManager.append(trunk: value) {
                let peerHistory = BleHistoryMessage(message: message)
                let mtu = peerHistory.mtu
                peer.historyTrunksManager.mtu = mtu
                peer.slicesTrunksManager.mtu = mtu
                let localHistory = BleHistoryMessage(items: delegate.items, terminalId: delegate.terminalId, mtu: mtu, includePreviousIndexes: true)
                if let missingHistory = peerHistory.substract(other: localHistory) {
                    send(message: missingHistory.message, history: true, to: peer)
                }
                delegate.didResolveIdentifier(terminal: peerHistory.terminalId, peripheralIdentifier: peripheral.identifier.uuidString)
            }
        } else if characteristic.uuid.isEqual(BleServices.headersUUID()) {
            if let message = peer.headersTrunksManager.append(trunk: value) {
                let item = BleItemHeaderMessage(message: message).item
                var slices = peer.slicesFor(item: item)
                if slices == nil {
                    guard !delegate.isKnown(item: item) else {
                        return
                    }
                    delegate.setKnown(item: item)
                    slices = peer.createSlicesFor(item: item)
                }
                requestNextSliceFrom(slices: slices, item: item, peer: peer)
            }
        } else if characteristic.uuid.isEqual(BleServices.slicesUUID()) {
            if let message = peer.slicesTrunksManager.append(trunk: value) {
                let sliceMessage = BleItemSliceMessage(message: message)
                guard let slices = peer.slicesFor(item: sliceMessage.item) else {
                    return
                }
                if sliceMessage.sliceIndex == 0 {
                    delegate.setDetailsFor(item: sliceMessage.item)
                    sliceMessage.item.size = slices.totalSize
                    delegate.isReceiving(item: sliceMessage.item, progress: 0)
                }
                if let itemData = slices.set(slice: sliceMessage.slice, atIndex: Int(sliceMessage.sliceIndex)) {
                    peer.removeSlicesFor(item: sliceMessage.item)
                    delegate.didReceive(item: sliceMessage.item, data: itemData, from: peripheral.identifier.uuidString)
                } else {
                    delegate.isReceiving(item: sliceMessage.item, progress: slices.progress)
                    requestNextSliceFrom(slices: slices, item: sliceMessage.item, peer: peer)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let peer = peers[peripheral.identifier.uuidString] else {
            return
        }
        var history = characteristic.uuid.isEqual(BleServices.historyUUID())
        guard error == nil else {
            BleLogger.debug("Peripheral \(peripheral.identifier.uuidString) did fail to send \(history ? "history" : "headers") trunk: \(error!)")
            queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.sendTrunk(history: history, to: peer)
            }
            return
        }
        var nextTrunk = true
        objc_sync_enter(peer)
        if history {
            peer.historyTrunks.removeFirst()
        } else {
            peer.headersTrunks.removeFirst()
        }
        if !peer.historyTrunks.isEmpty {
            history = true
        } else if !peer.headersTrunks.isEmpty {
            history = false
        } else {
            nextTrunk = false
            peer.isSending = false
        }
        objc_sync_exit(peer)
        if nextTrunk {
            sendTrunk(history: history, to: peer)
        }
    }
}




