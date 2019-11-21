//
//  BleHistoryMessage.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation

class BleHistoryMessage {
    
    let mtu: Int
    let terminalId: BleTerminalId
    
    fileprivate var flagsLength: BleFlagsLength
    fileprivate var itemsIndexes: [BleTerminalId: BleIndexesFlags]
    
    var message: Data {
        let length = MemoryLayout<UInt16>.size + MemoryLayout<BleTerminalId>.size + MemoryLayout<BleFlagsLength>.size + itemsIndexes.count * (MemoryLayout<BleTerminalId>.size + Int(flagsLength))
        var result = Data(count: length)
        UInt16(mtu).toBytes(data: &result, offset: 0)
        terminalId.toBytes(data: &result, offset: MemoryLayout<UInt16>.size)
        flagsLength.toBytes(data: &result, offset: MemoryLayout<UInt16>.size + MemoryLayout<BleTerminalId>.size)
        BleLogger.trace("BleHistoryMessage - message - mtu: \(mtu)")
        BleLogger.trace("BleHistoryMessage - message - terminalId: \(terminalId)")
        BleLogger.trace("BleHistoryMessage - message - flagsLength: \(flagsLength)")
        BleLogger.trace("BleHistoryMessage - message - \(itemsIndexes.count) itemsIndexes:")
        var offset = MemoryLayout<UInt16>.size + MemoryLayout<BleTerminalId>.size + MemoryLayout<BleFlagsLength>.size
        for entry in itemsIndexes {
            entry.key.toBytes(data: &result, offset: offset)
            offset += MemoryLayout<BleTerminalId>.size
            entry.value.toBytes(data: &result, offset: offset, length: Int(flagsLength))
            offset += Int(flagsLength)
            BleLogger.trace("BleHistoryMessage - message - itemsIndexes[\(entry.key)]: \(String(reflecting: entry.value))")
        }
        BleLogger.trace("BleHistoryMessage - message - message: \(result)")
        return result
    }
    
    var items: [BleItem] {
        var result = [BleItem]()
        for entry in itemsIndexes {
            result.append(contentsOf: entry.value.items(terminalId: entry.key))
        }
        return result
    }
    
    init(items: [BleItem], terminalId: BleTerminalId, mtu: Int, includePreviousIndexes: Bool) {
        self.mtu = mtu
        self.terminalId = terminalId
        flagsLength = 0
        itemsIndexes = [BleTerminalId: BleIndexesFlags]()
        for item in items {
            let indexes = itemsIndexes[item.terminalId] ?? BleIndexesFlags()
            flagsLength = max(flagsLength, indexes.add(itemIndex: item.itemIndex))
            for previousIndex in item.previousIndexes {
                if includePreviousIndexes {
                    flagsLength = max(flagsLength, indexes.add(itemIndex: previousIndex))
                } else {
                    indexes.remove(itemIndex: previousIndex)
                }
            }
            itemsIndexes[item.terminalId] = indexes
        }
    }
    
    init(message: Data) {
        BleLogger.trace("BleHistoryMessage - init - message: \(message)")
        mtu = Int(UInt16(data: message, offset: 0))
        terminalId = BleTerminalId(data: message, offset: MemoryLayout<UInt16>.size)
        flagsLength = BleFlagsLength(data: message, offset: MemoryLayout<UInt16>.size + MemoryLayout<BleTerminalId>.size)
        itemsIndexes = [BleTerminalId: BleIndexesFlags]()
        BleLogger.trace("BleHistoryMessage - init - mtu: \(mtu)")
        BleLogger.trace("BleHistoryMessage - init - terminalId: \(terminalId)")
        BleLogger.trace("BleHistoryMessage - init - flagsLength: \(flagsLength)")
        var offset = MemoryLayout<UInt16>.size + MemoryLayout<BleTerminalId>.size + MemoryLayout<BleFlagsLength>.size
        while offset < message.count {
            let key = BleTerminalId(data: message, offset: offset)
            offset += MemoryLayout<BleTerminalId>.size
            itemsIndexes[key] = BleIndexesFlags(data: message, offset: offset, length: Int(flagsLength))
            offset += Int(flagsLength)
            BleLogger.trace("BleHistoryMessage - init - itemsIndexes[\(key)]: \(String(reflecting: itemsIndexes[key]!))")
        }
    }
    
    fileprivate init(itemsIndexes: [BleTerminalId: BleIndexesFlags], flagsLength: BleFlagsLength, terminalId: BleTerminalId, mtu: Int) {
        self.itemsIndexes = itemsIndexes
        self.flagsLength = flagsLength
        self.terminalId = terminalId
        self.mtu = mtu
    }
    
    func substract(other: BleHistoryMessage) -> BleHistoryMessage? {
        var substractFlagsLength = BleFlagsLength(0)
        var substractIndexes = [BleTerminalId: BleIndexesFlags]()
        for entry in itemsIndexes {
            if let indexes = entry.value.substracting(other: other.itemsIndexes[entry.key]) {
                substractIndexes[entry.key] = indexes
                substractFlagsLength = max(substractFlagsLength, indexes.flagsLength)
            }
        }
        guard substractIndexes.count > 0 else {
            return nil
        }
        return BleHistoryMessage(itemsIndexes: substractIndexes, flagsLength: substractFlagsLength, terminalId: terminalId, mtu: mtu)
    }
}

fileprivate typealias BleFlagsLength = UInt16

fileprivate class BleIndexesFlags : CustomDebugStringConvertible {
    var flagsLength: BleFlagsLength {
        return BleFlagsLength(indexes.count)
    }
    
    private var indexes: Data
    
    init() {
        indexes = Data(count: 1)
    }
    
    init(data: Data, offset: Int, length: Int) {
        var indexes = data.subdata(in: offset..<(offset + length))
        while indexes.count > 1 && indexes.last! == 0 {
            indexes.removeLast()
        }
        self.indexes = indexes
    }
    
    private init (indexes: Data) {
        self.indexes = indexes
    }
    
    func add(itemIndex: BleItemIndex) -> BleFlagsLength {
        let pos = Int(itemIndex / 8)
        if pos >= indexes.count {
            for _ in indexes.count...pos {
                indexes.append(0)
            }
        }
        let flag = UInt8(1) << (Int(itemIndex) - 8 * pos)
        indexes[pos] |= flag
        return BleFlagsLength(indexes.count)
    }
    
    func remove(itemIndex: BleItemIndex) {
        let pos = Int(itemIndex / 8)
        if indexes.count > pos {
            let flag = UInt8(1) << (Int(itemIndex) - 8 * pos)
            indexes[pos] &= ~flag
        }
    }
    
    func toBytes(data: inout Data, offset: Int, length: Int) {
        for i in 0..<min(length, indexes.count) {
            data[offset + i] = indexes[i]
        }
    }
    
    func substracting(other: BleIndexesFlags?) -> BleIndexesFlags? {
        guard let other = other else {
            return self
        }
        var substractFlagsLength = 0
        var substractIndexes = Data()
        for (i, flags) in indexes.enumerated() {
            let substractFlags = flags - (other.indexes.count > i ? other.indexes[i] & flags : 0x00)
            substractIndexes.append(substractFlags)
            if substractFlags > 0 {
                substractFlagsLength = i + 1
            }
        }
        guard substractFlagsLength > 0 else {
            return nil
        }
        if substractFlagsLength < substractIndexes.count {
            substractIndexes.removeLast(substractIndexes.count - substractFlagsLength)
        }
        return BleIndexesFlags(indexes: substractIndexes)
    }
    
    func items(terminalId: BleTerminalId) -> [BleItem] {
        var nextIndex = BleItemIndex(0)
        var items = [BleItem]()
        for var flags in indexes {
            for _ in 1...8 {
                if (flags & 0x01) > 0 {
                    items.append(BleItem(terminalId: terminalId, itemIndex: nextIndex, size: 0))
                }
                flags >>= 1
                nextIndex += 1
            }
        }
        return items
    }
    
    var debugDescription: String {
        var indexes = [BleItemIndex]()
        var nextIndex = BleItemIndex(0)
        for var flags in indexes {
            for _ in 1...8 {
                if (flags & 0x01) > 0 {
                    indexes.append(nextIndex)
                }
                flags >>= 1
                nextIndex += 1
            }
        }
        return String(reflecting: indexes)
    }
}


