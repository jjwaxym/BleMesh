//
//  BleServices.swift
//  BleMesh
//
//  Created by Jean-Jacques Wacksman.
//  Copyright © 2019 Air France - KLM. All rights reserved.
//

import Foundation
import CoreBluetooth

class BleServices {
    
    static func serviceUUID(session: UInt64) -> CBUUID {
        return uuid(session)
    }
    
    static func historyUUID() -> CBUUID {
        return uuid(1)
    }
    
    static func headersUUID() -> CBUUID {
        return uuid(2)
    }
    
    static func slicesUUID() -> CBUUID {
        return uuid(3)
    }
    
    private static func uuid(_ suffix: UInt64) -> CBUUID {
        var hex = String(format: "%016llX", suffix)
        let index = hex.index(hex.startIndex, offsetBy: 4)
        hex.insert("-", at: index)
        return CBUUID(string: "CA32E4F6-28EA-419D-\(hex)")
    }
}
