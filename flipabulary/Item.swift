//
//  Item.swift
//  flipabulary
//
//  Created by andreas maier on 06.11.2026.
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
