//
//  BleItemHeaderMessage.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation

class BleItemHeaderMessage {
    private(set) var item: BleItem
    
    var message: Data! {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        if innerMessage == nil {
            BleLogger.trace("BleItemHeaderMessage - message - item: \(String(reflecting: item))")
            var content = Data(count: MemoryLayout<BleTerminalId>.size + MemoryLayout<BleItemIndex>.size + MemoryLayout<UInt32>.size)
            item.terminalId.toBytes(data: &content, offset: 0)
            item.itemIndex.toBytes(data: &content, offset: MemoryLayout<BleTerminalId>.size)
            item.size.toBytes(data: &content, offset: MemoryLayout<BleTerminalId>.size + MemoryLayout<BleItemIndex>.size)
            innerMessage = content
            BleLogger.trace("BleItemHeaderMessage - message - message: \(innerMessage!.hexString)")
        }
        return innerMessage!
    }
    
    private var innerMessage: Data?
    
    init(item: BleItem) {
        self.item = item
    }
    
    init(message: Data) {
        BleLogger.trace("BleItemHeaderMessage - init - message: \(message.hexString)")
        innerMessage = message
        let terminalId = BleTerminalId(data: message, offset: 0)
        let itemIndex = BleItemIndex(data: message, offset: MemoryLayout<BleTerminalId>.size)
        let size = UInt32(data: message, offset: MemoryLayout<BleTerminalId>.size  + MemoryLayout<BleItemIndex>.size)
        item = BleItem(terminalId: terminalId, itemIndex: itemIndex, size: size)
        BleLogger.trace("BleItemHeaderMessage - init - extracted item: \(String(reflecting: item))")
    }
}
