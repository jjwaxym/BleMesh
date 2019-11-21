//
//  BlePeripheralManager.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation
import CoreBluetooth

protocol BlePeripheralManagerDelegate {
    var sessionId: UInt64 { get }
    var advertisementName: String { get }
    var terminalId: BleTerminalId { get }
    var items: [BleItem] { get }
    
    func itemFor(terminalId: BleTerminalId, itemIndex: BleItemIndex) -> BleItem?
    func itemSliceFor(terminalId: BleTerminalId, itemIndex: BleItemIndex, sliceIndex: UInt16) -> Data?
    func isSending(item: BleItem, progress: UInt32)
    func coreBluetoothDidUbdateState(rawValue: Int)
}

fileprivate enum BleMessageType {
    case history, header, slice
}

class BlePeripheralManager : NSObject {
    
    private let delegate: BlePeripheralManagerDelegate
    private let queue: DispatchQueue
    private var peripheralManager: CBPeripheralManager!
    private var advertPending: Bool
    private var advertStopped: Bool
    private var serviceAdded: Bool
    private var serviceUUID: CBUUID!
    private var historyCharacteristic: CBMutableCharacteristic
    private var headersCharacteristic: CBMutableCharacteristic
    private var slicesCharacteristic: CBMutableCharacteristic
    private var peers: [String : BleCentral]
    private var slices: [BleItem : BleItemSlices]
    private var slicesSent: [BleItem]
    
    init(delegate: BlePeripheralManagerDelegate) {
        self.delegate = delegate
        peers = [String : BleCentral]()
        slices = [BleItem : BleItemSlices]()
        slicesSent = [BleItem]()
        queue = DispatchQueue(label: "com.airfrance.afble.pmqueue")
        advertPending = false
        advertStopped = true
        serviceAdded = false
        historyCharacteristic = CBMutableCharacteristic(type: BleServices.historyUUID(), properties: [.notify, .write], value: nil, permissions: [.readable, .writeable])
        headersCharacteristic = CBMutableCharacteristic(type: BleServices.headersUUID(), properties: [.notify, .write], value: nil, permissions: [.readable, .writeable])
        slicesCharacteristic = CBMutableCharacteristic(type: BleServices.slicesUUID(), properties: [.notify], value: nil, permissions: [.readable])
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self,
                                                queue: DispatchQueue(label: "com.airfrance.afble.com.airfrance.cabble.cbperipheralmanager"),
                                                options: [CBPeripheralManagerOptionShowPowerAlertKey:true])
    }
    
    func start() {
        advertStopped = false
        if peripheralManager.isAdvertising {
            BleLogger.debug("Already advertising")
            advertPending = false
        } else if peripheralManager.state == .poweredOn {
            advertPending = false
            if !serviceAdded {
                serviceUUID = BleServices.serviceUUID(session: delegate.sessionId)
                let service = CBMutableService(type: serviceUUID, primary: true)
                service.characteristics = [historyCharacteristic, headersCharacteristic, slicesCharacteristic]
                peripheralManager.add(service)
            }
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey:[serviceUUID], CBAdvertisementDataLocalNameKey:delegate.advertisementName])
            BleLogger.debug("Starts advertising: \(serviceUUID.uuidString)")
        } else {
            advertPending = true
            BleLogger.debug("Peripheral Manager not powered on state \(peripheralManager.state)")
        }
    }
    
    func stop() {
        advertStopped = true
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        serviceAdded = false
        peers.removeAll()
    }
    
    func broadcast(item: BleItem) {
        let message = BleItemHeaderMessage(item: item).message!
        for peer in peers.values {
            send(message: message, type: .header, to: peer)
        }
    }
    
    private func send(message: Data, type: BleMessageType, to peer: BleCentral) {
        var nextTrunk = false
        let trunks: [Data]
        switch type {
        case .history: trunks = peer.historyTrunksManager.split(message: message)
        case .header: trunks = peer.headersTrunksManager.split(message: message)
        case .slice: trunks = peer.slicesTrunksManager.split(message: message)
        }
        objc_sync_enter(peer)
        switch type {
        case .history: peer.historyTrunks.append(contentsOf: trunks)
        case .header: peer.headersTrunks.append(contentsOf: trunks)
        case .slice: peer.slicesTrunks.append(contentsOf: trunks)
        }
        if !peer.isSending {
            peer.isSending = true
            nextTrunk = true
        }
        objc_sync_exit(peer)
        if nextTrunk {
            sendTrunk(type: type, to: peer)
        }
    }
    
    private func sendTrunk(type: BleMessageType, to peer: BleCentral) {
        queue.async { [weak self] in
            let trunk: Data?
            switch type {
            case .history: trunk = peer.historyTrunks.first
            case .header: trunk = peer.headersTrunks.first
            case .slice: trunk = peer.slicesTrunks.first
            }
            if let manager = self, let trunk = trunk {
                let characteristic: CBMutableCharacteristic
                switch type {
                case .history: characteristic = manager.historyCharacteristic
                case .header: characteristic = manager.headersCharacteristic
                case .slice: characteristic = manager.slicesCharacteristic
                }
                if manager.peripheralManager.updateValue(trunk, for: characteristic, onSubscribedCentrals: [peer.central]) {
                    var nextTrunk = true
                    var nextType = BleMessageType.slice
                    objc_sync_enter(peer)
                    switch type {
                    case .history:  peer.historyTrunks.removeFirst()
                    case .header: peer.headersTrunks.removeFirst()
                    case .slice: peer.slicesTrunks.removeFirst()
                    }
                    if peer.historyTrunks.isEmpty && peer.headersTrunks.isEmpty && peer.slicesTrunks.isEmpty {
                        peer.isSending = false
                        nextTrunk = false
                    } else {
                        nextType = peer.historyTrunks.isEmpty ? (peer.headersTrunks.isEmpty ? .slice : .header) : .history
                    }
                    objc_sync_exit(peer)
                    if nextTrunk {
                        manager.sendTrunk(type: nextType, to: peer)
                    }
                } else {
                    objc_sync_enter(peer)
                    peer.isSending = false
                    objc_sync_exit(peer)
                }
            }
        }
    }
}

extension BlePeripheralManager : CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        BleLogger.debug("Peripheral Manager did update state: \(peripheral.state)")
        delegate.coreBluetoothDidUbdateState(rawValue: peripheral.state.rawValue)
        if peripheral.state == .poweredOn {
            if advertPending {
                start()
            }
        } else {
            let wasStopped = advertStopped
            stop()
            if !wasStopped {
                start()
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            BleLogger.debug("Peripheral Manager did fail to add service: \(error!)")
            return
        }
        serviceAdded = true
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard error == nil else {
            BleLogger.debug("Peripheral Manager did fail to start advertising: \(error!)")
            advertPending = true
            start()
            return
        }
        BleLogger.debug("Peripheral Manager did start advertising")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        var peer: BleCentral! = peers[central.identifier.uuidString]
        if peer == nil {
            peer = BleCentral(central: central)
            peers[central.identifier.uuidString] = peer
        }
        if characteristic.isEqual(historyCharacteristic) {
            let mtu = central.maximumUpdateValueLength
            peer.historyTrunksManager.mtu = mtu
            peer.headersTrunksManager.mtu = mtu
            peer.slicesTrunksManager.mtu = mtu
            let history = BleHistoryMessage(items: delegate.items, terminalId: delegate.terminalId, mtu: mtu, includePreviousIndexes: false)
            send(message: history.message, type: .history, to: peer)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        peers.removeValue(forKey: central.identifier.uuidString)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        var requestedSlices = [(BleCentral,Data)]()
        var requestedHeaders = [(BleCentral,Data)]()
        var result = CBATTError.requestNotSupported
        for request in requests {
            if let peer = peers[request.central.identifier.uuidString], request.value != nil {
                if request.characteristic.isEqual(historyCharacteristic) {
                    result = CBATTError.success
                    if let message = peer.historyTrunksManager.append(trunk: request.value!) {
                        requestedHeaders.append((peer, message))
                    }
                } else if request.characteristic.isEqual(headersCharacteristic) {
                    result = CBATTError.success
                    if let message = peer.headersTrunksManager.append(trunk: request.value!) {
                        requestedSlices.append((peer, message))
                    }
                }
            }
        }
        peripheralManager.respond(to: requests[0], withResult: result)
        for (peer, message) in requestedHeaders {
            let history = BleHistoryMessage(message: message)
            for historyItem in history.items {
                if let item = delegate.itemFor(terminalId: historyItem.terminalId, itemIndex: historyItem.itemIndex) {
                    send(message: BleItemHeaderMessage(item: item).message, type: .header, to: peer)
                } else {
                    BleLogger.debug("Failed to find item \(historyItem.terminalId)(\(historyItem.itemIndex)) requested by central \(peer.central.identifier.uuidString)")
                }
            }
        }
        for (peer, message) in requestedSlices {
            let (terminalId, itemIndex, sliceIndex) = BleItemSliceMessage.sliceInformationFor(sliceRequestMessage: message)
            let item = sliceIndex == 0 ? delegate.itemFor(terminalId: terminalId, itemIndex: itemIndex) : BleItem(terminalId: terminalId, itemIndex: itemIndex, size: 0)
            if let item = item, let slice = delegate.itemSliceFor(terminalId: terminalId, itemIndex: itemIndex, sliceIndex: sliceIndex) {
                let sliceMessage = BleItemSliceMessage(item: item, slice: slice, sliceIndex: sliceIndex)
                send(message: sliceMessage.message, type: .slice, to: peer)
                var progress: UInt32? = nil
                objc_sync_enter(self)
                if !slicesSent.contains(item) {
                    let newItem = BleItem(terminalId: item.terminalId, itemIndex: item.itemIndex, size: item.size)
                    var itemSlices = slices[item]
                    if itemSlices == nil {
                        itemSlices = BleItemSlices(size: item.size, sender: true)
                        slices[newItem] = itemSlices
                    }
                    progress = itemSlices!.sentSlice(atIndex: Int(sliceIndex))
                    if progress != nil {
                        if progress! == itemSlices!.totalSize {
                            slicesSent.append(newItem)
                            slices.removeValue(forKey: newItem)
                        }
                    }
                }
                objc_sync_exit(self)
                if progress != nil {
                    delegate.isSending(item: item, progress: progress!)
                }
            } else {
                BleLogger.debug("Failed to find slice \(sliceIndex) for item \(terminalId)(\(itemIndex)) requested by central \(peer.central.identifier.uuidString)")
            }
        }
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        for peer in peers.values {
            var nextTrunk = false
            var type = BleMessageType.slice
            objc_sync_enter(peer)
            if !peer.isSending {
                if !peer.historyTrunks.isEmpty {
                    peer.isSending = true
                    nextTrunk = true
                    type = .history
                } else if !peer.headersTrunks.isEmpty {
                    peer.isSending = true
                    nextTrunk = true
                    type = .header
                } else if !peer.slicesTrunks.isEmpty {
                    peer.isSending = true
                    nextTrunk = true
                    type = .slice
                }
            }
            objc_sync_exit(peer)
            if nextTrunk {
                sendTrunk(type: type, to: peer)
            }
        }
    }
}





