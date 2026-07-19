//
//  Item.swift
//  AtlasLog
//
//  Created by Amrit Rathie on 7/18/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
