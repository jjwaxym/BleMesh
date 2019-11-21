//
//  BleItem.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation

public typealias BleTerminalId = UInt64
public typealias BleItemIndex = UInt32

@objc public class BleItem : NSObject {
    
    @objc public var terminalId: BleTerminalId
    @objc public var itemIndex: BleItemIndex
    @objc public var previousIndexes: [BleItemIndex]
    @objc public var size: UInt32
    @objc public var headerData: Data?
    
    @objc public init(terminalId: BleTerminalId, itemIndex: BleItemIndex, previousIndexes: [BleItemIndex]? = nil, size: UInt32, headerData: Data? = nil) {
        self.terminalId = terminalId
        self.itemIndex = itemIndex
        self.previousIndexes = previousIndexes ?? []
        self.size = size
        self.headerData = headerData
    }

    override public var hash: Int {
        var hash = 0
        for byte in terminalId.bytes + itemIndex.bytes {
            hash = 31 &* hash &+ Int(byte)
        }
        return hash
    }
    
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? BleItem else {
            return false
        }
        return other.terminalId == terminalId && other.itemIndex == itemIndex
    }
    
    @objc public override var debugDescription: String {
        return "BleItem(terminalId: \(terminalId), itemIndex: \(itemIndex), previousIndexes: \(previousIndexes), size: \(size), data: \(headerData?.hexString ?? "nil"))"
    }
}

extension UnsignedInteger {
    var bytes: [UInt8] {
        var value = self
        return withUnsafeBytes(of: &value) {
            Array($0)
        }
    }
}
