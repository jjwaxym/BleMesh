//
//  BleItemSlices.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation

class BleItemSlices {
    static let SLICE_LENGTH = UInt32(16384)
    
    let totalSize: UInt32
    
    private(set) var progress: UInt32
    private var receiverState: [(requested: Bool, slice: Data?)]!
    private var senderState: [Bool]!
    
    init(size: UInt32, sender: Bool) {
        totalSize = size
        progress = 0
        let count = Int((size + BleItemSlices.SLICE_LENGTH - 1) / BleItemSlices.SLICE_LENGTH)
        if sender {
            senderState = Array(repeating: false, count: count)
        } else {
            receiverState = Array(repeating: (false, nil), count: count)
        }
    }
    
    func requestNext() -> Int? {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        for (index, state) in receiverState.enumerated() {
            if !state.requested {
                receiverState[index] = (true, nil)
                return index
            }
        }
        return nil
    }
    
    func set(slice: Data, atIndex index: Int) -> Data? {
        objc_sync_enter(self)
        guard index < receiverState.count && receiverState[index].slice == nil else {
            objc_sync_exit(self)
            return nil
        }
        receiverState[index] = (true, slice)
        progress += UInt32(slice.count)
        let reassemble = progress == totalSize
        objc_sync_exit(self)
        return reassemble ? Data(receiverState.map{$0.slice!}.joined()) : nil
    }
    
    func sentSlice(atIndex index: Int) -> UInt32? {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        guard index < senderState.count && !senderState[index] else {
            return nil
        }
        if index == senderState.count - 1 {
            progress += (totalSize - UInt32(index) * BleItemSlices.SLICE_LENGTH)
        } else {
            progress += BleItemSlices.SLICE_LENGTH
        }
        return progress
    }
}
