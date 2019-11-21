//
//  BleManager.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation

@objc public enum BleManagerBluetoothState: Int {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

@objc public protocol BleCryptoHandler : NSObjectProtocol {
    @objc func encrypt(message: Data) -> Data?
    @objc func decrypt(message: Data) -> Data?
}

@objc public protocol BleManagerDelegate : NSObjectProtocol {
    @objc var bleItems: [BleItem] { get }
    
    @objc func bleManagerItemSliceFor(terminalId: BleTerminalId, index: BleItemIndex, offset: UInt32, length: UInt32) -> Data?
    
    @objc optional func bleManagerDidStart()
    @objc optional func bleManagerDidStop()
    @objc optional func bleManagerDidConnect(peripheral peripheralIdentifier: String)
    @objc optional func bleManagerDidDisconnect(peripheral peripheralIdentifier: String)
    @objc optional func bleManagerDidReceive(item: BleItem, data: Data)
    @objc optional func bleManagerDidUpdateBluetoothState(_ state: BleManagerBluetoothState)
    @objc optional func bleManagerDidResolveIdentifier(terminal: BleTerminalId, peripheralIdentifier: String)
    @objc optional func bleManagerIsReceiving(item: BleItem, totalSizeReceived: UInt32)
    @objc optional func bleManagerIsSending(item: BleItem, totalSizeSent: UInt32)
}

@objc public class BleManager : NSObject {
    
    @objc public static let shared = BleManager()
    
    @objc public var advertisementName: String
    @objc public var delegate: BleManagerDelegate?
    @objc public private(set) var bluetoothState: BleManagerBluetoothState
    
    private var terminal: BleTerminalId?
    private var session: UInt64?
    private var knownItems: [BleTerminalId:[BleItemIndex]]
    private var innerItems: [BleItem]
    private var peripheralManager: BlePeripheralManager!
    private var centralManager: BleCentralManager!
    private var startPending: Bool
    private var started: Bool
    private let queue: DispatchQueue
    
    private override init() {
        advertisementName = ""
        queue = DispatchQueue(label: "com.airfrance.afble.managerqueue")
        started = false
        startPending = false
        knownItems = [BleTerminalId:[BleItemIndex]]()
        innerItems = []
        bluetoothState = .unknown
        super.init()
        peripheralManager = BlePeripheralManager(delegate: self)
        centralManager = BleCentralManager(delegate: self)
    }
    
    @objc public func start(session newSession: UInt64, terminal newTerminal: BleTerminalId, cryptoHandler newCryptoHandler: BleCryptoHandler? = nil) {
        if session == nil || terminal == nil || session != newSession || terminal != newTerminal || BleTrunksManager.cryptoHandler !== newCryptoHandler {
            session = newSession
            terminal = newTerminal
            if startPending {
                BleTrunksManager.cryptoHandler = newCryptoHandler
                _ = start()
            } else {
                stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    BleTrunksManager.cryptoHandler = newCryptoHandler
                    _ = self?.start()
                }
            }
        } else if startPending {
            _ = start()
        }
    }
    
    @objc public func start() -> Bool {
        guard terminal != nil && session != nil else {
            BleLogger.debug("BleManager failed to start with terminalId: \(String(describing: terminal)) and session:\(String(describing: session))")
            startPending = true
            return false
        }
        guard started == false else {
            BleLogger.debug("BleManager already started")
            return false
        }
        BleLogger.debug("BleManager starting with terminalId: \(terminal!) and session:\(session!)")
        startPending = false
        centralManager.start()
        peripheralManager.start()
        started = true
        queue.async { [weak self] in
            self?.delegate?.bleManagerDidStart?()
        }
        return true
    }
    
    @objc public func stop() {
        started = false;
        centralManager.stop()
        peripheralManager.stop()
        queue.async { [weak self] in
            self?.delegate?.bleManagerDidStop?()
        }
    }
    
    @objc public func broadcast(item: BleItem) {
        setKnown(item: item)
        peripheralManager.broadcast(item: item)
    }
    
    private func isKnown(item: BleItem, addIfUnknown add: Bool) -> Bool {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        var knownIndexes = knownItems[item.terminalId] ?? [BleItemIndex]()
        if knownIndexes.contains(item.itemIndex) {
            setDetailsFor(item: item)
            return true
        }
        if add {
            innerItems.append(item)
            knownIndexes.append(item.itemIndex)
            knownItems[item.terminalId] = knownIndexes
        }
        return false
    }
}

extension BleManager : BlePeripheralManagerDelegate, BleCentralManagerDelegate {
    var sessionId: UInt64 {
        return session ?? 0
    }
    var terminalId: BleTerminalId {
        return terminal ?? 0
    }
    var items: [BleItem] {
        var result = [BleItem]()
        let group = DispatchGroup()
        group.enter()
        queue.async { [weak self] in
            result = self?.delegate?.bleItems ?? []
            group.leave()
        }
        group.wait()
        for item in result {
            setKnown(item: item)
        }
        return result
    }
    
    func isKnown(item: BleItem) -> Bool {
        return isKnown(item: item, addIfUnknown: false)
    }
    
    func setKnown(item: BleItem) {
        _ = isKnown(item: item, addIfUnknown: true)
    }
    
    func setDetailsFor(item: BleItem) {
        if item.headerData != nil || item.size > 0, let innerItem = itemFor(terminalId: item.terminalId, itemIndex: item.itemIndex) {
            innerItem.headerData = item.headerData ?? innerItem.headerData
            innerItem.size = max(item.size, innerItem.size)
            if(innerItem.previousIndexes.isEmpty && !item.previousIndexes.isEmpty) {
                innerItem.previousIndexes = item.previousIndexes
            }
        }
    }
    
    func itemFor(terminalId: BleTerminalId, itemIndex: BleItemIndex) -> BleItem? {
        guard let index = innerItems.firstIndex(where: { $0.terminalId == terminalId && $0.itemIndex == itemIndex }) else {
            return nil
        }
        return innerItems[index]
    }
    
    func itemSliceFor(terminalId: BleTerminalId, itemIndex: BleItemIndex, sliceIndex: UInt16) -> Data? {
        let offset = UInt32(sliceIndex) * BleItemSlices.SLICE_LENGTH
        var result: Data? = nil
        let group = DispatchGroup()
        group.enter()
        queue.async { [weak self] in
            result = self?.delegate?.bleManagerItemSliceFor(terminalId: terminalId, index: itemIndex, offset: offset, length: BleItemSlices.SLICE_LENGTH)
            group.leave()
        }
        group.wait()
        return result
    }
    
    func coreBluetoothDidUbdateState(rawValue: Int) {
        guard let newState = BleManagerBluetoothState(rawValue: rawValue), newState != bluetoothState else {
            return
        }
        bluetoothState = newState
        queue.async { [weak self] in
            self?.delegate?.bleManagerDidUpdateBluetoothState?(newState)
        }
    }
    
    func didConnect(peripheral peripheralIdentifier: String) {
        queue.async { [weak self] in
            self?.delegate?.bleManagerDidConnect?(peripheral: peripheralIdentifier)
        }
    }
    
    func didDisconnect(peripheral peripheralIdentifier: String) {
        queue.async { [weak self] in
            self?.delegate?.bleManagerDidDisconnect?(peripheral: peripheralIdentifier)
        }
    }
    
    func didReceive(item: BleItem, data: Data, from peripheralIdentifier: String) {
        let innerItem = itemFor(terminalId: item.terminalId, itemIndex: item.itemIndex) ?? item
        queue.async { [weak self] in
            self?.broadcast(item: innerItem)
            self?.delegate?.bleManagerDidReceive?(item: innerItem, data: data)
        }
    }
    
    func didResolveIdentifier(terminal: BleTerminalId, peripheralIdentifier: String) {
        queue.async { [weak self] in
            self?.delegate?.bleManagerDidResolveIdentifier?(terminal: terminal, peripheralIdentifier: peripheralIdentifier)
        }
    }
    
    func isReceiving(item: BleItem, progress: UInt32) {
        queue.async { [weak self] in
            self?.delegate?.bleManagerIsReceiving?(item: item, totalSizeReceived: progress)
        }
    }
    
    func isSending(item: BleItem, progress: UInt32) {
        queue.async { [weak self] in
            self?.delegate?.bleManagerIsSending?(item: item, totalSizeSent: progress)
        }
    }
}



