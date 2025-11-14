//
//  StringExtensions.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/5/25.
//

import Foundation

// MARK: - String Extension for Input Validation
extension String {
    /// 验证字符串是否为有效的数字（允许小数）
    var isValidNumeric: Bool {
        guard !self.isEmpty else { return false }
        
        // 使用正则表达式验证：可选的数字，可选的一个小数点，后面跟数字
        let pattern = "^\\d+(\\.\\d*)?$|^\\.\\d+$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex?.firstMatch(in: self, range: range) != nil
    }
    
    /// 验证字符串是否为有效的正整数
    var isValidInteger: Bool {
        guard !self.isEmpty else { return false }
        return Int(self) != nil && !self.hasPrefix("-")
    }
    
    /// 验证字符串是否为有效的正数（大于0）
    var isValidPositiveNumber: Bool {
        guard isValidNumeric else { return false }
        guard let value = Double(self) else { return false }
        return value > 0
    }
    
    /// 验证字符串是否为有效的正整数（大于0）
    var isValidPositiveInteger: Bool {
        guard isValidInteger else { return false }
        guard let value = Int(self) else { return false }
        return value > 0
    }
}
