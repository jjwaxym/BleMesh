//
//  BleCentral.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation
import CoreBluetooth

class BleCentral {
    
    let central: CBCentral
    let historyTrunksManager: BleTrunksManager
    let headersTrunksManager: BleTrunksManager
    let slicesTrunksManager: BleTrunksManager
    var historyTrunks: [Data]
    var headersTrunks: [Data]
    var slicesTrunks: [Data]
    var isSending: Bool
    
    init(central: CBCentral) {
        self.central = central
        historyTrunksManager = BleTrunksManager()
        headersTrunksManager = BleTrunksManager()
        slicesTrunksManager = BleTrunksManager()
        historyTrunks = [Data]()
        headersTrunks = [Data]()
        slicesTrunks = [Data]()
        isSending = false
    }
}
