//
//  BlePeripheral.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation
import CoreBluetooth

class BlePeripheral {
    
    let peripheral: CBPeripheral
    let historyTrunksManager: BleTrunksManager
    let headersTrunksManager: BleTrunksManager
    let slicesTrunksManager: BleTrunksManager
    var historyTrunks: [Data]
    var headersTrunks: [Data]
    var isSending: Bool
    private var slices: [BleItem:BleItemSlices]
    
    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        historyTrunksManager = BleTrunksManager()
        headersTrunksManager = BleTrunksManager()
        slicesTrunksManager = BleTrunksManager()
        historyTrunks = [Data]()
        headersTrunks = [Data]()
        slices = [BleItem:BleItemSlices]()
        isSending = false
    }
    
    func createSlicesFor(item: BleItem) -> BleItemSlices? {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        if let itemSlices = slices[item] {
            return itemSlices
        }
        let itemSlices = BleItemSlices(size: item.size, sender: false)
        slices[item] = itemSlices
        return itemSlices
    }
    
    func slicesFor(item: BleItem) -> BleItemSlices? {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        return slices[item]
    }
    
    func removeSlicesFor(item: BleItem) {
        objc_sync_enter(self)
        slices.removeValue(forKey: item)
        objc_sync_exit(self)
    }
}
