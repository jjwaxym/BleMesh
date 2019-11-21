//
//  BleTrunksManager.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation

class BleTrunksManager {
    
    static var cryptoHandler: BleCryptoHandler?
    
    var mtu: Int
    
    private var nextMessageId: UInt8
    fileprivate var allTrunks: [UInt8: BleTrunks]
    
    init() {
        mtu = 20
        nextMessageId = 0
        allTrunks = [UInt8: BleTrunks]()
    }
    
    func split(message: Data) -> [Data] {
        objc_sync_enter(self)
        let messageId = nextMessageId
        nextMessageId = nextMessageId &+ 1
        objc_sync_exit(self)
        BleLogger.trace("BleTrunksManager - split \(messageId) - message: \(message.hexString)")
        guard let encrypted = BleTrunksManager.cryptoHandler == nil ? message : BleTrunksManager.cryptoHandler!.encrypt(message: message) else {
            BleLogger.error("Failed to encrypt message!")
            return []
        }
        BleLogger.trace("BleTrunksManager - split \(messageId) - \(BleTrunksManager.cryptoHandler == nil ? "no encryption" : "encrypted: \(encrypted.hexString)")")
        let headerLength = 3
        let trunkMaxLength: Int = mtu - headerLength
        let count = (encrypted.count + trunkMaxLength - 1) / trunkMaxLength
        var header = Data(count: headerLength)
        header[0] = messageId
        header[1] = UInt8(count)
        var offset = 0
        var nextOffset = 0
        var trunks = [Data]()
        for i in 0..<count {
            header[2] = UInt8(i)
            nextOffset = min(encrypted.count, offset + trunkMaxLength)
            var trunk = Data()
            trunk.append(header)
            trunk.append(encrypted[offset..<nextOffset])
            trunks.append(trunk)
            offset = nextOffset
            BleLogger.trace("BleTrunksManager - split \(messageId) - trunk[\(i)/\(count)]: \(trunk.hexString)")
        }
        return trunks
    }
    
    func append(trunk: Data) -> Data? {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        let messageId = trunk[0]
        var trunks: BleTrunks! = allTrunks[messageId]
        if trunks == nil {
            trunks = BleTrunks(trunk: trunk)
            allTrunks[messageId] = trunks
        } else {
            trunks.append(trunk: trunk)
        }
        guard var message = trunks.message else {
            return nil
        }
        allTrunks.removeValue(forKey: messageId)
        if BleTrunksManager.cryptoHandler != nil {
            BleLogger.trace("BleTrunksManager - append \(messageId) - encrypted message: \(message.hexString)")
            guard let decrypted = BleTrunksManager.cryptoHandler!.decrypt(message: message) else {
                BleLogger.error("Failed to decrypt message!")
                return nil
            }
            message = decrypted
        }
        BleLogger.trace("BleTrunksManager - append \(messageId) - message: \(message.hexString)")
        return message
    }
}

fileprivate class BleTrunks {
    private var totalCount: Int
    private var currentCount: Int
    private var trunks: [Data?]
    
    private var startTime: TimeInterval?
    private var endTime: TimeInterval?
    
    var message: Data? {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        guard currentCount == totalCount else {
            return nil
        }
        var result = Data()
        for t in trunks {
            guard let trunk = t else {
                return nil
            }
            result.append(trunk)
        }
        BleLogger.debug("\(totalCount) trunks (size = \(result.count)) within \(endTime! - startTime!) seconds")
        return result
    }
    
    init(trunk: Data) {
        totalCount = 0
        currentCount = 0
        trunks = []
        append(trunk: trunk)
    }
    
    func append(trunk newTrunk: Data) {
        let length = 3
        let header = newTrunk[0..<length]
        let count = Int(header[1])
        let index = Int(header[2])
        BleLogger.trace("BleTrunksManager - append \(header[0]) - trunk[\(index)/\(count)]: \(newTrunk.hexString)")
        if count != totalCount {
            totalCount = count
            currentCount = 0
            trunks = [Data?](repeating: nil, count: count)
        }
        if index < count {
            if trunks[index] == nil {
                currentCount += 1
                if currentCount == 1 {
                    startTime = Date().timeIntervalSince1970
                }
                if (currentCount == totalCount) {
                    endTime = Date().timeIntervalSince1970
                }
            }
            trunks[index] = newTrunk.subdata(in: length..<newTrunk.count)
        }
    }
}


extension UnsignedInteger {
    init(data: Data, offset: Int) {
        let count = MemoryLayout<Self>.size
        precondition((count + offset) <= data.count)
        var value = UInt64(0)
        for i in 0..<count {
            value <<= 8
            value |= UInt64(data[i + offset])
        }
        self.init(value)
    }
    
    func toBytes(data: inout Data, offset: Int) {
        let count = MemoryLayout<Self>.size
        precondition((count + offset) <= data.count)
        var value = UInt64(self)
        for i in (0..<count).reversed() {
            data[i + offset] = UInt8(value & 0x0FF)
            value >>= 8
        }
    }
}


