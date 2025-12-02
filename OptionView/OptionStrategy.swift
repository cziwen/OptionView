//
//  OptionStrategy.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/4/25.
//

import Foundation
import SwiftData

@Model
final class OptionStrategy {
    var symbol: String // 股票代码
    @Attribute(.externalStorage) var optionType: OptionType // 期权类型
    var expirationDate: Date // 执行日
    var strikePrice: Double // 执行价
    var optionPrice: Double // 期权价格
    var averagePricePerShare: Double // 每股均价
    var contracts: Int // 合同数
    @Attribute(.externalStorage) var exerciseStatus: ExerciseStatus // 是否行权
    var marginCost: Double? // 保证金成本（仅用于 Naked Call/Put）
    var exerciseMarketPrice: Double? // 行权时的市场价格（仅用于 Naked Call/Put 被行权）
    var currentMarketPrice: Double? // 当前市场价格（用于未行权时计算未实现盈亏）
    var createdAt: Date // 创建时间
    
    init(
        symbol: String,
        optionType: OptionType,
        expirationDate: Date,
        strikePrice: Double,
        optionPrice: Double,
        averagePricePerShare: Double,
        contracts: Int,
        exerciseStatus: ExerciseStatus = .unknown,
        marginCost: Double? = nil,
        exerciseMarketPrice: Double? = nil,
        currentMarketPrice: Double? = nil
    ) {
        self.symbol = symbol.uppercased()
        self.optionType = optionType
        self.expirationDate = expirationDate
        self.strikePrice = strikePrice
        self.optionPrice = optionPrice
        self.averagePricePerShare = averagePricePerShare
        self.contracts = contracts
        self.exerciseStatus = exerciseStatus
        self.marginCost = marginCost
        self.exerciseMarketPrice = exerciseMarketPrice
        self.currentMarketPrice = currentMarketPrice
        self.createdAt = Date()
    }
    
    /// 计算或获取实际的保证金成本
    /// - Returns: 保证金成本
    func getMarginCost() -> Double {
        switch optionType {
        case .nakedCall:
            // 如果有输入 marginCost，使用输入值；否则估算为执行价的 20%
            if let margin = marginCost {
                return margin
            } else {
                return strikePrice * Double(contracts) * 100 * 0.20
            }
            
        case .nakedPut:
            // 如果有输入 marginCost，使用输入值；否则估算为执行价的 15%
            if let margin = marginCost {
                return margin
            } else {
                return strikePrice * Double(contracts) * 100 * 0.15
            }
            
        default:
            // 其他类型不使用保证金成本
            return 0
        }
    }
    
    /// 根据当前价格判断是否应该行权
    /// 判断逻辑：ITM (In-The-Money) = 行权，OTM (Out-The-Money) = 不行权
    /// - Parameter currentPrice: 当前市场价格
    /// - Returns: true表示应该行权（ITM），false表示不应该行权（OTM）
    func shouldExercise(at currentPrice: Double) -> Bool {
        switch optionType {
        case .coveredCall, .nakedCall, .buyCall:
            // Call期权：当前价格 > 执行价 = ITM = 行权
            return currentPrice > strikePrice
            
        case .cashSecuredPut, .nakedPut, .buyPut:
            // Put期权：当前价格 < 执行价 = ITM = 行权
            return currentPrice < strikePrice
        }
    }
    
    /// 根据当前价格更新行权状态和市场价格
    /// - Parameter currentPrice: 当前市场价格
    func updateExerciseStatusAndPrice(at currentPrice: Double) {
        let shouldExercise = self.shouldExercise(at: currentPrice)
        
        if shouldExercise {
            // ITM = 行权
            self.exerciseStatus = .yes
            // 清除未行权时的市场价格
            self.currentMarketPrice = nil
            // 根据策略类型决定存储位置
            switch optionType {
            case .coveredCall:
                // Covered Call 被行权时不需要存储市场价格（已使用执行价）
                self.exerciseMarketPrice = nil
            case .cashSecuredPut, .nakedCall, .nakedPut:
                // 这些策略被行权时需要存储行权时的市场价格
                self.exerciseMarketPrice = currentPrice
            case .buyCall, .buyPut:
                // Buy Call/Put 被行权时也存储行权价格
                self.exerciseMarketPrice = currentPrice
            }
        } else {
            // OTM = 不行权
            self.exerciseStatus = .no
            // 清除行权时的市场价格
            self.exerciseMarketPrice = nil
            // 未行权时存储当前市场价格用于计算未实现盈亏
            self.currentMarketPrice = currentPrice
        }
    }
}

// Option Type
enum OptionType: String, Codable, CaseIterable {
    case coveredCall = "CoveredCall"
    case nakedCall = "NakedCall"
    case cashSecuredPut = "CashSecuredPut"
    case nakedPut = "NakedPut"
    case buyCall = "BuyCall"
    case buyPut = "BuyPut"
    
    var displayName: String {
        switch self {
        case .coveredCall:
            return "Sell Covered Call"
        case .nakedCall:
            return "Sell Naked Call"
        case .cashSecuredPut:
            return "Sell Cash-Secured Put"
        case .nakedPut:
            return "Sell Naked Put"
        case .buyCall:
            return "Buy Call"
        case .buyPut:
            return "Buy Put"
        }
    }
    
    // 辅助属性：判断是 Call 还是 Put
    var isCall: Bool {
        self == .coveredCall || self == .nakedCall || self == .buyCall
    }
    
    var isPut: Bool {
        self == .cashSecuredPut || self == .nakedPut || self == .buyPut
    }
    
    // 辅助属性：判断是否有担保
    var isSecured: Bool {
        self == .coveredCall || self == .cashSecuredPut
    }
    
    var isNaked: Bool {
        self == .nakedCall || self == .nakedPut
    }
}

// Exercise Status
enum ExerciseStatus: String, Codable, CaseIterable {
    case yes = "Yes"
    case no = "No"
    case unknown = "Unknown"
    
    var displayName: String {
        self.rawValue
    }
}
