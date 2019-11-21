//
//  BleItemSliceMessage.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation

class BleItemSliceMessage {
    private(set) var sliceIndex: UInt16
    private(set) var item: BleItem
    private(set) var slice: Data
    
    var message: Data! {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        if innerMessage == nil {
            BleLogger.trace("BleItemSliceMessage - message - item: \(String(reflecting: item))")
            BleLogger.trace("BleItemSliceMessage - message - slice[\(sliceIndex)]: \(slice.hexString)")
            innerMessage = Data()
            var length = MemoryLayout<UInt16>.size + MemoryLayout<BleTerminalId>.size + MemoryLayout<BleItemIndex>.size
            var content = Data(count: length)
            sliceIndex.toBytes(data: &content, offset: 0)
            item.terminalId.toBytes(data: &content, offset: MemoryLayout<UInt16>.size)
            item.itemIndex.toBytes(data: &content, offset: MemoryLayout<UInt16>.size + MemoryLayout<BleTerminalId>.size)
            innerMessage!.append(content)
            if sliceIndex == 0 {
                length = 2 * MemoryLayout<UInt8>.size + item.previousIndexes.count * MemoryLayout<BleItemIndex>.size
                content = Data(count: length)
                UInt8(item.previousIndexes.count).toBytes(data: &content, offset: 0)
                var offset = MemoryLayout<UInt8>.size
                for index in item.previousIndexes {
                    index.toBytes(data: &content, offset: offset)
                    offset += MemoryLayout<BleItemIndex>.size
                }
                let headerDataCount = min(255, item.headerData?.count ?? 0)
                UInt8(headerDataCount).toBytes(data: &content, offset: offset)
                innerMessage!.append(content)
                if let headerData = item.headerData {
                    innerMessage!.append(headerData[0..<headerDataCount])
                }
            }
            innerMessage!.append(slice)
            BleLogger.trace("BleItemSliceMessage - message - message: \(innerMessage!.hexString)")
        }
        return innerMessage!
    }
    
    private var innerMessage: Data?
    
    init(item: BleItem, slice: Data, sliceIndex: UInt16) {
        self.item = item
        self.slice = slice
        self.sliceIndex = sliceIndex
    }
    
    init(message: Data) {
        BleLogger.trace("BleItemSliceMessage - init - message: \(message.hexString)")
        innerMessage = message
        sliceIndex = UInt16(data: message, offset: 0)
        var offset = MemoryLayout<UInt16>.size
        let terminalId = BleTerminalId(data: message, offset: offset)
        let itemIndex = BleItemIndex(data: message, offset: offset + MemoryLayout<BleTerminalId>.size)
        offset += MemoryLayout<BleTerminalId>.size + MemoryLayout<BleItemIndex>.size
        if sliceIndex == 0 {
            var indexes: [BleItemIndex]?
            var count = Int(UInt8(data: message, offset: offset))
            offset += MemoryLayout<UInt8>.size
            if count > 0 {
                indexes = [BleItemIndex]()
                for _ in 0..<count {
                    indexes!.append(BleItemIndex(data: message, offset: offset))
                    offset += MemoryLayout<BleItemIndex>.size
                }
            }
            var headerData: Data? = nil
            count = Int(UInt8(data: message, offset: offset))
            offset += MemoryLayout<UInt8>.size
            if count > 0 {
                headerData = message.subdata(in: offset..<(offset + count))
                offset += count
            }
            item = BleItem(terminalId: terminalId, itemIndex: itemIndex, previousIndexes: indexes, size: 0, headerData: headerData)
        } else {
            item = BleItem(terminalId: terminalId, itemIndex: itemIndex, size: 0)
        }
        slice = message.subdata(in: offset..<message.count)
        BleLogger.trace("BleItemSliceMessage - init - extracted item: \(String(reflecting: item))")
        BleLogger.trace("BleItemSliceMessage - init - extracted slice[\(sliceIndex)]: \(slice.hexString)")
    }
    
    static func sliceRequestMessageFor(terminalId: BleTerminalId, itemIndex: BleItemIndex, sliceIndex: UInt16) -> Data {
        var message = Data(count: MemoryLayout<BleTerminalId>.size + MemoryLayout<BleItemIndex>.size + MemoryLayout<UInt16>.size)
        terminalId.toBytes(data: &message, offset: 0)
        itemIndex.toBytes(data: &message, offset: MemoryLayout<BleTerminalId>.size)
        sliceIndex.toBytes(data: &message, offset: MemoryLayout<BleTerminalId>.size + MemoryLayout<BleItemIndex>.size)
        return message
    }
    
    static func sliceInformationFor(sliceRequestMessage message: Data) -> (terminalId: BleTerminalId, itemIndex: BleItemIndex, sliceIndex: UInt16) {
        let terminalId = BleTerminalId(data: message, offset: 0)
        let itemIndex = BleItemIndex(data: message, offset: MemoryLayout<BleTerminalId>.size)
        let sliceIndex = UInt16(data: message, offset: MemoryLayout<BleTerminalId>.size + MemoryLayout<BleItemIndex>.size)
        return (terminalId, itemIndex, sliceIndex)
    }
}


