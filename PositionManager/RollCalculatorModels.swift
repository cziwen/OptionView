//
//  RollCalculatorModels.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/8/25.
//

import Foundation

// MARK: - 旧仓结局模式
enum OldLegEndMode: String, CaseIterable, Identifiable {
    case exercised = "Exercised"
    case closed = "Closed"
    case expired = "Expired"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .exercised:
            return "Exercised"
        case .closed:
            return "Closed (Buy Back)"
        case .expired:
            return "Expired Worthless"
        }
    }
    
    var description: String {
        switch self {
        case .exercised:
            return "Option was exercised, stock was assigned"
        case .closed:
            return "Option was bought back before expiration"
        case .expired:
            return "Option expired worthless, kept full premium"
        }
    }
    
    var icon: String {
        switch self {
        case .exercised:
            return "arrow.left.arrow.right.circle.fill"
        case .closed:
            return "arrow.counterclockwise.circle.fill"
        case .expired:
            return "checkmark.circle.fill"
        }
    }
}

// MARK: - 旧仓假设
struct OldLegAssumption {
    let endMode: OldLegEndMode
    
    /// 若 endMode == .closed，用户输入的期权平仓价（每股价格）
    let closePrice: Double?
    
    /// 若 endMode == .exercised 且是 Naked Call/Put，需要输入行权时的市场价
    let marketPriceAtExercise: Double?
    
    /// 若 endMode == .expired，可选输入到期时的股价（用于计算未实现损益）
    let stockPriceAtExpiration: Double?
    
    init(endMode: OldLegEndMode, closePrice: Double? = nil, marketPriceAtExercise: Double? = nil, stockPriceAtExpiration: Double? = nil) {
        self.endMode = endMode
        self.closePrice = closePrice
        self.marketPriceAtExercise = marketPriceAtExercise
        self.stockPriceAtExpiration = stockPriceAtExpiration
    }
}

// MARK: - 新仓输入
struct NewPositionInput {
    let strikeNew: Double          // 新合约 strike
    let premiumNew: Double         // 新合约开仓收/付的权利金（收 = 正，付 = 负）
    let quantityNew: Int?          // 默认可以用旧仓数量
    
    /// 可选：用户预期的到期时市场价（用于计算 Naked Call 被行权等情景）
    let expectedMarketPriceAtExpiration: Double?
    
    init(strikeNew: Double, premiumNew: Double, quantityNew: Int? = nil, expectedMarketPriceAtExpiration: Double? = nil) {
        self.strikeNew = strikeNew
        self.premiumNew = premiumNew
        self.quantityNew = quantityNew
        self.expectedMarketPriceAtExpiration = expectedMarketPriceAtExpiration
    }
}

// MARK: - Roll 计算结果
struct RollResult {
    // 旧仓从开仓到结束的已实现 P/L（已确定）
    let oldLegPnL: Double
    
    // 新仓开仓时收到的权利金（已确定）
    let newLegPremiumReceived: Double
    
    // === 情景 1: 新仓被行权 ===
    let ifNewExercised: ScenarioResult
    
    // === 情景 2: 新仓不被行权（到期作废或平仓）===
    let ifNewNotExercised: ScenarioResult
    
    // 辅助信息
    let breakdown: String // 计算过程说明
}

// MARK: - 单个情景的结果
struct ScenarioResult {
    // 新仓这一腿的 P/L（包括权利金和可能的股票交割）
    let newLegPnL: Double
    
    // 总 P/L = 旧仓 P/L + 新仓 P/L
    let totalPnL: Double
    
    // 成本基础和收益率
    let costBasis: Double?
    let returnPercent: Double?
    
    // 最终股票持仓
    let finalStockQuantity: Int?
    let finalStockCostBasis: Double?
    
    // 情景说明
    let description: String
    
    // 是否计算成功（如果缺少必要的 S_T，则为 false）
    let isCalculated: Bool
    let missingDataWarning: String?
}

// MARK: - Roll 计算器（核心逻辑）
struct RollCalculatorEngine {
    // 每张合约的股数
    private static let contractSize = 100
    
    /// 主计算函数
    static func calculateRollResult(
        oldStrategy: OptionStrategy,
        assumption: OldLegAssumption,
        newInput: NewPositionInput
    ) -> RollResult {
        
        // 1. 计算旧 leg 的已实现 P/L 和股票状态（这是已确定的）
        let (oldLegPnL, stockAfterOldLeg, stockCostAfterOldLeg) = calcOldLegPnLAndStockState(
            strategy: oldStrategy,
            assumption: assumption
        )
        
        // 2. 计算新 leg 开仓收到的权利金（这是已确定的）
        let newPremiumReceived = calcNewLegPremiumReceived(
            oldStrategy: oldStrategy,
            newInput: newInput
        )
        
        // 3. 计算两种情景：新仓被行权 vs 新仓不被行权
        let exercisedScenario = calcNewLegExercisedScenario(
            oldStrategy: oldStrategy,
            oldLegPnL: oldLegPnL,
            stockAfterOldLeg: stockAfterOldLeg,
            stockCostAfterOldLeg: stockCostAfterOldLeg,
            newInput: newInput,
            newPremiumReceived: newPremiumReceived
        )
        
        let notExercisedScenario = calcNewLegNotExercisedScenario(
            oldStrategy: oldStrategy,
            oldLegPnL: oldLegPnL,
            stockAfterOldLeg: stockAfterOldLeg,
            stockCostAfterOldLeg: stockCostAfterOldLeg,
            newInput: newInput,
            newPremiumReceived: newPremiumReceived
        )
        
        // 4. 生成计算说明
        let breakdown = generateBreakdown(
            oldStrategy: oldStrategy,
            assumption: assumption,
            newInput: newInput,
            oldLegPnL: oldLegPnL,
            newPremiumReceived: newPremiumReceived,
            exercisedScenario: exercisedScenario,
            notExercisedScenario: notExercisedScenario
        )
        
        return RollResult(
            oldLegPnL: oldLegPnL,
            newLegPremiumReceived: newPremiumReceived,
            ifNewExercised: exercisedScenario,
            ifNewNotExercised: notExercisedScenario,
            breakdown: breakdown
        )
    }
    
    // MARK: - 计算旧 leg 的 P/L 和股票状态
    static func calcOldLegPnLAndStockState(
        strategy: OptionStrategy,
        assumption: OldLegAssumption
    ) -> (oldLegPnL: Double, finalStockQuantity: Int?, finalStockCostBasis: Double?) {
        
        let contracts = strategy.contracts
        let totalShares = contracts * contractSize
        let premiumReceived = strategy.optionPrice * Double(totalShares)
        let strike = strategy.strikePrice
        let avgCost = strategy.averagePricePerShare
        
        switch strategy.optionType {
        case .coveredCall:
            return calcCoveredCallOldLeg(
                endMode: assumption.endMode,
                closePrice: assumption.closePrice,
                strike: strike,
                premium: premiumReceived,
                shares: totalShares,
                avgCost: avgCost
            )
            
        case .nakedCall:
            return calcNakedCallOldLeg(
                endMode: assumption.endMode,
                closePrice: assumption.closePrice,
                strike: strike,
                premium: premiumReceived,
                shares: totalShares,
                marketPriceAtExercise: assumption.marketPriceAtExercise
            )
            
        case .cashSecuredPut:
            return calcCashSecuredPutOldLeg(
                endMode: assumption.endMode,
                closePrice: assumption.closePrice,
                strike: strike,
                premium: premiumReceived,
                shares: totalShares
            )
            
        case .nakedPut:
            return calcNakedPutOldLeg(
                endMode: assumption.endMode,
                closePrice: assumption.closePrice,
                strike: strike,
                premium: premiumReceived,
                shares: totalShares,
                marketPriceAtExercise: assumption.marketPriceAtExercise
            )
        }
    }
    
    // MARK: - Covered Call 旧 leg 计算
    private static func calcCoveredCallOldLeg(
        endMode: OldLegEndMode,
        closePrice: Double?,
        strike: Double,
        premium: Double,
        shares: Int,
        avgCost: Double
    ) -> (Double, Int?, Double?) {
        
        switch endMode {
        case .expired:
            // 到期作废：收全部权利金，股票继续持有
            let pnl = premium
            return (pnl, shares, avgCost)
            
        case .closed:
            // 平仓：买回期权
            guard let close = closePrice else {
                return (premium, shares, avgCost)
            }
            let closeCost = close * Double(shares)
            let pnl = premium - closeCost
            return (pnl, shares, avgCost)
            
        case .exercised:
            // 被行权：股票在 strike 被卖出
            let stockPnL = (strike - avgCost) * Double(shares)
            let totalPnL = stockPnL + premium
            return (totalPnL, 0, nil) // 股票被卖出，持仓归零
        }
    }
    
    // MARK: - Naked Call 旧 leg 计算
    private static func calcNakedCallOldLeg(
        endMode: OldLegEndMode,
        closePrice: Double?,
        strike: Double,
        premium: Double,
        shares: Int,
        marketPriceAtExercise: Double?
    ) -> (Double, Int?, Double?) {
        
        switch endMode {
        case .expired:
            // 到期作废：收全部权利金
            return (premium, nil, nil)
            
        case .closed:
            // 平仓：买回期权
            guard let close = closePrice else {
                return (premium, nil, nil)
            }
            let closeCost = close * Double(shares)
            let pnl = premium - closeCost
            return (pnl, nil, nil)
            
        case .exercised:
            // 被行权：需要在市场价买入，在 strike 卖出
            if let marketPrice = marketPriceAtExercise {
                // 损失 = (市场价 - strike) × shares
                let assignmentLoss = (marketPrice - strike) * Double(shares)
                let pnl = premium - assignmentLoss
                return (pnl, nil, nil)
            } else {
                // 没有提供市场价，无法准确计算，只返回权利金
                return (premium, nil, nil)
            }
        }
    }
    
    // MARK: - Cash-Secured Put 旧 leg 计算
    private static func calcCashSecuredPutOldLeg(
        endMode: OldLegEndMode,
        closePrice: Double?,
        strike: Double,
        premium: Double,
        shares: Int
    ) -> (Double, Int?, Double?) {
        
        switch endMode {
        case .expired:
            // 到期作废：收全部权利金，不产生股票
            return (premium, nil, nil)
            
        case .closed:
            // 平仓：买回期权
            guard let close = closePrice else {
                return (premium, nil, nil)
            }
            let closeCost = close * Double(shares)
            let pnl = premium - closeCost
            return (pnl, nil, nil)
            
        case .exercised:
            // 被行权：在 strike 买入股票
            // P/L = 收的权利金（买股票本身不算 P/L，只是现金变股票）
            // 股票成本基础 = (strike * shares - premium) / shares
            let netCostPerShare = strike - (premium / Double(shares))
            return (0, shares, netCostPerShare) // 行权本身不产生 P/L，只是换仓
        }
    }
    
    // MARK: - Naked Put 旧 leg 计算
    private static func calcNakedPutOldLeg(
        endMode: OldLegEndMode,
        closePrice: Double?,
        strike: Double,
        premium: Double,
        shares: Int,
        marketPriceAtExercise: Double?
    ) -> (Double, Int?, Double?) {
        
        // Naked Put 的逻辑与 CSP 基本类似，但被行权时可能需要市场价
        // （虽然实际中很少发生，因为 Put 被行权意味着你在 strike 买入，这是确定的）
        return calcCashSecuredPutOldLeg(
            endMode: endMode,
            closePrice: closePrice,
            strike: strike,
            premium: premium,
            shares: shares
        )
    }
    
    // MARK: - 计算新 leg 开仓收到的权利金
    private static func calcNewLegPremiumReceived(
        oldStrategy: OptionStrategy,
        newInput: NewPositionInput
    ) -> Double {
        let quantity = newInput.quantityNew ?? oldStrategy.contracts
        let totalShares = quantity * contractSize
        
        // 新仓开仓收到的权利金（卖方收钱为正）
        return newInput.premiumNew * Double(totalShares)
    }
    
    // MARK: - 计算新仓被行权的情景
    private static func calcNewLegExercisedScenario(
        oldStrategy: OptionStrategy,
        oldLegPnL: Double,
        stockAfterOldLeg: Int?,
        stockCostAfterOldLeg: Double?,
        newInput: NewPositionInput,
        newPremiumReceived: Double
    ) -> ScenarioResult {
        
        let quantity = newInput.quantityNew ?? oldStrategy.contracts
        let totalShares = quantity * contractSize
        let newStrike = newInput.strikeNew
        let expectedMarketPrice = newInput.expectedMarketPriceAtExpiration
        
        var newLegPnL: Double
        var finalStockQty: Int? = stockAfterOldLeg
        var finalStockCost: Double? = stockCostAfterOldLeg
        var costBasis: Double?
        var description: String
        var isCalculated = true
        var missingDataWarning: String? = nil
        
        switch oldStrategy.optionType {
        case .coveredCall:
            // 继续 roll covered call
            // 新仓被行权：stock sold at new strike
            if let currentStockQty = stockAfterOldLeg,
               let currentStockCost = stockCostAfterOldLeg,
               currentStockQty > 0 {
                // 卖出股票的损益
                let stockSalePnL = (newStrike - currentStockCost) * Double(totalShares)
                newLegPnL = stockSalePnL + newPremiumReceived
                finalStockQty = 0
                finalStockCost = nil
                costBasis = currentStockCost * Double(totalShares)
                description = "New Call exercised: Stock sold at $\(String(format: "%.2f", newStrike))"
            } else {
                // 没有股票（旧仓已被行权）
                newLegPnL = newPremiumReceived
                costBasis = nil
                description = "No stock to sell (old position was already exercised)"
            }
            
        case .nakedCall:
            // Naked Call 被行权：需要市价买入，在 strike 卖出
            if let marketPrice = expectedMarketPrice {
                // 有预期市场价，计算损失
                let assignmentLoss = (marketPrice - newStrike) * Double(totalShares)
                newLegPnL = newPremiumReceived - assignmentLoss
                costBasis = oldStrategy.getMarginCost()
                description = "New Naked Call exercised: Buy at $\(String(format: "%.2f", marketPrice)), sell at $\(String(format: "%.2f", newStrike))"
            } else {
                // 没有预期市场价，无法计算
                newLegPnL = 0  // 占位值
                costBasis = oldStrategy.getMarginCost()
                isCalculated = false
                missingDataWarning = "Cannot calculate: Expected stock price at expiration is required for Naked Call exercise scenario"
                description = "⚠️ Calculation not possible without expected stock price"
            }
            
        case .cashSecuredPut:
            // CSP 被行权：在 new strike 买入股票
            newLegPnL = newPremiumReceived
            let netCostPerShare = newStrike - (newPremiumReceived / Double(totalShares))
            finalStockQty = totalShares
            finalStockCost = netCostPerShare
            costBasis = newStrike * Double(totalShares) - newPremiumReceived
            description = "New Put exercised: Stock purchased at $\(String(format: "%.2f", newStrike))"
            
        case .nakedPut:
            // 类似 CSP
            newLegPnL = newPremiumReceived
            let netCostPerShare = newStrike - (newPremiumReceived / Double(totalShares))
            finalStockQty = totalShares
            finalStockCost = netCostPerShare
            costBasis = oldStrategy.getMarginCost()
            description = "New Naked Put exercised: Stock purchased at $\(String(format: "%.2f", newStrike))"
        }
        
        let totalPnL = oldLegPnL + newLegPnL
        let returnPercent: Double? = costBasis.map { $0 > 0 ? totalPnL / $0 : nil } ?? nil
        
        return ScenarioResult(
            newLegPnL: newLegPnL,
            totalPnL: totalPnL,
            costBasis: costBasis,
            returnPercent: returnPercent,
            finalStockQuantity: finalStockQty,
            finalStockCostBasis: finalStockCost,
            description: description,
            isCalculated: isCalculated,
            missingDataWarning: missingDataWarning
        )
    }
    
    // MARK: - 计算新仓不被行权的情景
    private static func calcNewLegNotExercisedScenario(
        oldStrategy: OptionStrategy,
        oldLegPnL: Double,
        stockAfterOldLeg: Int?,
        stockCostAfterOldLeg: Double?,
        newInput: NewPositionInput,
        newPremiumReceived: Double
    ) -> ScenarioResult {
        
        let quantity = newInput.quantityNew ?? oldStrategy.contracts
        let totalShares = quantity * contractSize
        let expectedMarketPrice = newInput.expectedMarketPriceAtExpiration
        
        var newLegPnL: Double
        var finalStockQty: Int? = stockAfterOldLeg
        var finalStockCost: Double? = stockCostAfterOldLeg
        var costBasis: Double?
        var description: String
        var isCalculated = true
        var missingDataWarning: String? = nil
        
        switch oldStrategy.optionType {
        case .coveredCall:
            // Covered Call 到期：必须有 expectedStockPrice 才能计算
            if let marketPrice = expectedMarketPrice,
               let qty = stockAfterOldLeg,
               let cost = stockCostAfterOldLeg,
               qty > 0 {
                // 有预期股价，可以计算完整 P/L
                // P/L = (S_T - cost) × shares + premium
                let stockPnL = (marketPrice - cost) * Double(qty)
                newLegPnL = stockPnL + newPremiumReceived
                finalStockQty = qty
                finalStockCost = cost
                costBasis = cost * Double(qty)
                description = "New Call expired: Stock held, valued at $\(String(format: "%.2f", marketPrice)). P/L = (S_T - cost) × shares + premium"
            } else {
                // 没有预期股价或没有股票，无法计算
                newLegPnL = 0  // 占位值
                costBasis = nil
                isCalculated = false
                if stockAfterOldLeg == nil || (stockAfterOldLeg ?? 0) == 0 {
                    missingDataWarning = "No stock to calculate P/L"
                    description = "⚠️ No stock position"
                } else {
                    missingDataWarning = "Cannot calculate: Expected stock price at expiration is required for Covered Call expiry scenario. P/L = (S_T - cost) × shares + premium"
                    description = "⚠️ Calculation not possible without expected stock price (S_T)"
                }
            }
            
        case .nakedCall:
            // Naked Call 未被行权：保留权利金（最优情况）
            newLegPnL = newPremiumReceived
            costBasis = oldStrategy.getMarginCost()
            description = "New Naked Call expired: Kept full premium $\(String(format: "%.2f", newPremiumReceived))"
            
        case .cashSecuredPut:
            // CSP 未被行权：保留权利金，不买股票
            newLegPnL = newPremiumReceived
            costBasis = newInput.strikeNew * Double(totalShares)
            finalStockQty = nil
            finalStockCost = nil
            description = "New Put expired: Kept premium $\(String(format: "%.2f", newPremiumReceived)), no stock purchased"
            
        case .nakedPut:
            // Naked Put 未被行权：保留权利金
            newLegPnL = newPremiumReceived
            costBasis = oldStrategy.getMarginCost()
            finalStockQty = nil
            finalStockCost = nil
            description = "New Naked Put expired: Kept full premium $\(String(format: "%.2f", newPremiumReceived))"
        }
        
        let totalPnL = oldLegPnL + newLegPnL
        let returnPercent: Double? = costBasis.map { $0 > 0 ? totalPnL / $0 : nil } ?? nil
        
        return ScenarioResult(
            newLegPnL: newLegPnL,
            totalPnL: totalPnL,
            costBasis: costBasis,
            returnPercent: returnPercent,
            finalStockQuantity: finalStockQty,
            finalStockCostBasis: finalStockCost,
            description: description,
            isCalculated: isCalculated,
            missingDataWarning: missingDataWarning
        )
    }
    
    // MARK: - 生成计算说明
    private static func generateBreakdown(
        oldStrategy: OptionStrategy,
        assumption: OldLegAssumption,
        newInput: NewPositionInput,
        oldLegPnL: Double,
        newPremiumReceived: Double,
        exercisedScenario: ScenarioResult,
        notExercisedScenario: ScenarioResult
    ) -> String {
        
        let shares = oldStrategy.contracts * contractSize
        let oldPremium = oldStrategy.optionPrice * Double(shares)
        
        var lines: [String] = []
        
        lines.append("📊 Calculation Breakdown:")
        lines.append("")
        
        // === 旧仓部分（已确定）===
        lines.append("=== OLD POSITION (Realized) ===")
        lines.append("Strategy: \(oldStrategy.optionType.displayName)")
        lines.append("Strike: $\(String(format: "%.2f", oldStrategy.strikePrice))")
        lines.append("Premium Received: $\(String(format: "%.2f", oldPremium))")
        lines.append("Outcome: \(assumption.endMode.displayName)")
        
        if assumption.endMode == .closed, let close = assumption.closePrice {
            let closeCost = close * Double(shares)
            lines.append("Close Price: $\(String(format: "%.2f", close)) per share")
            lines.append("Close Cost: $\(String(format: "%.2f", closeCost))")
        }
        
        lines.append("✅ Old Leg P/L: $\(String(format: "%.2f", oldLegPnL))")
        lines.append("")
        
        // === 新仓部分（未确定）===
        lines.append("=== NEW POSITION (Future Scenarios) ===")
        lines.append("New Strike: $\(String(format: "%.2f", newInput.strikeNew))")
        lines.append("Premium Received: $\(String(format: "%.2f", newInput.premiumNew)) per share")
        lines.append("Premium Total: $\(String(format: "%.2f", newPremiumReceived))")
        lines.append("")
        
        // 情景 1
        lines.append("📈 SCENARIO 1: If New Position Is Exercised")
        lines.append(exercisedScenario.description)
        lines.append("New Leg P/L: $\(String(format: "%.2f", exercisedScenario.newLegPnL))")
        lines.append("Total P/L: $\(String(format: "%.2f", exercisedScenario.totalPnL))")
        if let ret = exercisedScenario.returnPercent {
            lines.append("Return: \(String(format: "%.2f", ret * 100))%")
        }
        lines.append("")
        
        // 情景 2
        lines.append("📉 SCENARIO 2: If New Position Expires/Not Exercised")
        lines.append(notExercisedScenario.description)
        lines.append("New Leg P/L: $\(String(format: "%.2f", notExercisedScenario.newLegPnL))")
        lines.append("Total P/L: $\(String(format: "%.2f", notExercisedScenario.totalPnL))")
        if let ret = notExercisedScenario.returnPercent {
            lines.append("Return: \(String(format: "%.2f", ret * 100))%")
        }
        
        return lines.joined(separator: "\n")
    }
}
