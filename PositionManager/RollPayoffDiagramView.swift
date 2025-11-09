//
//  RollPayoffDiagramView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/8/25.
//

import SwiftUI
import Charts

// MARK: - Roll Payoff Point
struct RollPayoffPoint: Identifiable {
    let id = UUID()
    let stockPrice: Double  // S_T (到期时的股价)
    let totalPnL: Double    // 总 P/L
}

// MARK: - Roll Payoff Calculator
class RollPayoffCalculator {
    /// 计算在不同 S_T 下的 P/L
    static func calculateRollPayoff(
        oldStrategy: OptionStrategy,
        oldAssumption: OldLegAssumption,
        newOptionType: OptionType,
        newStrike: Double,
        newPremium: Double,
        priceRange: [Double]
    ) -> [RollPayoffPoint] {
        
        // 1. 计算旧仓的已实现 P/L（固定的）
        let (oldLegPnL, stockAfterOld, stockCostAfterOld) = RollCalculatorEngine.calcOldLegPnLAndStockState(
            strategy: oldStrategy,
            assumption: oldAssumption
        )
        
        let newPremiumReceived = newPremium * Double(oldStrategy.contracts) * 100
        
        // 2. 对于每个 S_T，计算总 P/L
        return priceRange.map { ST in
            let totalPnL = calculatePnLAtPrice(
                oldStrategy: oldStrategy,
                oldLegPnL: oldLegPnL,
                stockAfterOld: stockAfterOld,
                stockCostAfterOld: stockCostAfterOld,
                newOptionType: newOptionType,
                newStrike: newStrike,
                newPremiumReceived: newPremiumReceived,
                ST: ST
            )
            
            return RollPayoffPoint(stockPrice: ST, totalPnL: totalPnL)
        }
    }
    
    /// 计算在特定股价下的 P/L
    private static func calculatePnLAtPrice(
        oldStrategy: OptionStrategy,
        oldLegPnL: Double,
        stockAfterOld: Int?,
        stockCostAfterOld: Double?,
        newOptionType: OptionType,
        newStrike: Double,
        newPremiumReceived: Double,
        ST: Double
    ) -> Double {
        
        let quantity = oldStrategy.contracts
        let totalShares = quantity * 100
        
        var newLegPnL: Double
        
        switch newOptionType {
        case .coveredCall:
            // Covered Call
            if let stockQty = stockAfterOld,
               let stockCost = stockCostAfterOld,
               stockQty > 0 {
                // 有股票（旧仓 expired 或 closed 的情况）
                if ST >= newStrike {
                    // 新 Call 被行权：在 new strike 卖出
                    let stockPnL = (newStrike - stockCost) * Double(stockQty)
                    newLegPnL = stockPnL + newPremiumReceived
                } else {
                    // 新 Call 到期：股票继续持有
                    // P/L = (S_T - cost) × shares + premium
                    let stockPnL = (ST - stockCost) * Double(stockQty)
                    newLegPnL = stockPnL + newPremiumReceived
                }
            } else {
                // 没有股票（旧仓 exercised 的情况）
                // 只有新仓的权利金收入，没有股票损益
                newLegPnL = newPremiumReceived
            }
            
        case .nakedCall:
            // Naked Call
            if ST >= newStrike {
                // 被行权：Loss = (S_T - strike) × shares
                let loss = (ST - newStrike) * Double(totalShares)
                newLegPnL = newPremiumReceived - loss
            } else {
                // 到期：收全部权利金
                newLegPnL = newPremiumReceived
            }
            
        case .cashSecuredPut:
            // CSP
            if ST <= newStrike {
                // 被行权：在 strike 买入，但现在价值 S_T
                // P/L = (S_T - strike) × shares + premium
                let stockPnL = (ST - newStrike) * Double(totalShares)
                newLegPnL = stockPnL + newPremiumReceived
            } else {
                // 到期：收全部权利金
                newLegPnL = newPremiumReceived
            }
            
        case .nakedPut:
            // Naked Put
            if ST <= newStrike {
                // 被行权
                let loss = (newStrike - ST) * Double(totalShares)
                newLegPnL = newPremiumReceived - loss
            } else {
                // 到期
                newLegPnL = newPremiumReceived
            }
        }
        
        return oldLegPnL + newLegPnL
    }
    
    /// 生成价格范围
    static func generatePriceRange(oldStrategy: OptionStrategy, newStrike: Double) -> [Double] {
        let oldStrike = oldStrategy.strikePrice
        let minStrike = min(oldStrike, newStrike)
        let maxStrike = max(oldStrike, newStrike)
        
        // 左右各留 30% 空间
        let rangeWidth = maxStrike - minStrike
        let buffer = max(rangeWidth * 0.3, minStrike * 0.2)
        
        let minPrice = max(0, minStrike - buffer)
        let maxPrice = maxStrike + buffer
        
        let steps = 100
        let step = (maxPrice - minPrice) / Double(steps)
        
        return stride(from: minPrice, through: maxPrice, by: step).map { $0 }
    }
}

// MARK: - Roll Payoff Diagram View
struct RollPayoffDiagramView: View {
    let oldStrategy: OptionStrategy
    let oldAssumption: OldLegAssumption
    let newOptionType: OptionType
    let newStrike: Double
    let newPremium: Double
    
    @State private var selectedPrice: Double?
    @State private var selectedProfit: Double?
    
    private var payoffPoints: [RollPayoffPoint] {
        let priceRange = RollPayoffCalculator.generatePriceRange(
            oldStrategy: oldStrategy,
            newStrike: newStrike
        )
        
        return RollPayoffCalculator.calculateRollPayoff(
            oldStrategy: oldStrategy,
            oldAssumption: oldAssumption,
            newOptionType: newOptionType,
            newStrike: newStrike,
            newPremium: newPremium,
            priceRange: priceRange
        )
    }
    
    private var chartMinY: Double {
        let allProfits = payoffPoints.map { $0.totalPnL }
        let minProfit = allProfits.min() ?? 0
        return minProfit - abs(minProfit) * 0.2
    }
    
    private var chartMaxY: Double {
        let allProfits = payoffPoints.map { $0.totalPnL }
        let maxProfit = allProfits.max() ?? 0
        return maxProfit + abs(maxProfit) * 0.2
    }
    
    private var chartMinX: Double {
        payoffPoints.map { $0.stockPrice }.min() ?? 0
    }
    
    private var chartMaxX: Double {
        payoffPoints.map { $0.stockPrice }.max() ?? 100
    }
    
    private var maxProfit: Double {
        payoffPoints.map { $0.totalPnL }.max() ?? 0
    }
    
    private var maxLoss: Double {
        payoffPoints.map { $0.totalPnL }.min() ?? 0
    }
    
    private var breakEvenPoints: [Double] {
        var points: [Double] = []
        
        for i in 0..<(payoffPoints.count - 1) {
            let current = payoffPoints[i]
            let next = payoffPoints[i + 1]
            
            if (current.totalPnL <= 0 && next.totalPnL >= 0) || (current.totalPnL >= 0 && next.totalPnL <= 0) {
                if next.totalPnL - current.totalPnL != 0 {
                    let ratio = -current.totalPnL / (next.totalPnL - current.totalPnL)
                    let breakEven = current.stockPrice + ratio * (next.stockPrice - current.stockPrice)
                    points.append(breakEven)
                }
            }
        }
        
        return points
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 标题
                VStack(spacing: 8) {
                    Text("Roll P/L Diagram")
                        .font(.title2.bold())
                    
                    Text("Shows total P/L at different stock prices (S_T) at expiration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Debug info
                    if let stockQty = getStockAfterOldLeg().0 {
                        Text("Stock after old leg: \(stockQty) shares")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Text("No stock after old leg")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal)
                
                // 图表
                VStack(spacing: 16) {
                    Chart {
                        // 零线参考
                        RuleMark(y: .value("Break-even", 0))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        
                        // 旧 strike 参考线
                        RuleMark(x: .value("Old Strike", oldStrategy.strikePrice))
                            .foregroundStyle(.orange.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, alignment: .center) {
                                Text("Old Strike")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        
                        // 新 strike 参考线
                        RuleMark(x: .value("New Strike", newStrike))
                            .foregroundStyle(.blue.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, alignment: .center) {
                                Text("New Strike")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        
                        // P/L 曲线
                        ForEach(payoffPoints) { point in
                            LineMark(
                                x: .value("Stock Price", point.stockPrice),
                                y: .value("P/L", point.totalPnL)
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.green, .yellow, .red],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .lineStyle(StrokeStyle(lineWidth: 3))
                        }
                        
                        // 盈利区域填充
                        ForEach(payoffPoints.filter { $0.totalPnL >= 0 }) { point in
                            AreaMark(
                                x: .value("Stock Price", point.stockPrice),
                                yStart: .value("Zero", 0),
                                yEnd: .value("P/L", point.totalPnL)
                            )
                            .foregroundStyle(.green.opacity(0.1))
                        }
                        
                        // 亏损区域填充
                        ForEach(payoffPoints.filter { $0.totalPnL < 0 }) { point in
                            AreaMark(
                                x: .value("Stock Price", point.stockPrice),
                                yStart: .value("Zero", 0),
                                yEnd: .value("P/L", point.totalPnL)
                            )
                            .foregroundStyle(.red.opacity(0.1))
                        }
                        
                        // 选中点的垂直线
                        if let price = selectedPrice {
                            RuleMark(x: .value("Selected", price))
                                .foregroundStyle(.purple.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .annotation(position: .top) {
                                    VStack(spacing: 4) {
                                        Text("S_T = $\(String(format: "%.2f", price))")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.purple)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                        }
                    }
                    .chartXScale(domain: chartMinX...chartMaxX)
                    .chartYScale(domain: chartMinY...chartMaxY)
                    .chartXAxisLabel("Stock Price at Expiration (S_T)")
                    .chartYAxisLabel("Total P/L")
                    .frame(height: 400)
                    .chartXSelection(value: $selectedPrice)
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal)
                
                // 选中点详情
                if let price = selectedPrice {
                    VStack(spacing: 12) {
                        HStack {
                            Text("At S_T = $\(String(format: "%.2f", price))")
                                .font(.headline)
                            
                            Spacer()
                            
                            if let profit = selectedProfit {
                                Text(formatPrice(profit))
                                    .font(.headline)
                                    .foregroundStyle(profit >= 0 ? .green : .red)
                            }
                        }
                        
                        // 情景说明
                        VStack(alignment: .leading, spacing: 8) {
                            if price < oldStrategy.strikePrice {
                                Label("Below old strike: Option expired", systemImage: "arrow.down.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Label("Above old strike: Option exercised", systemImage: "arrow.up.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            
                            if price < newStrike {
                                Label("Below new strike: New option will expire", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Label("Above new strike: New option will be exercised", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .padding(.horizontal)
                }
                
                // 关键指标
                metricsCard
                    .padding(.horizontal)
                
                // 策略信息
                strategyInfoCard
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .onChange(of: selectedPrice) { oldValue, newValue in
            if let price = newValue {
                let closestPoint = payoffPoints.min { p1, p2 in
                    abs(p1.stockPrice - price) < abs(p2.stockPrice - price)
                }
                selectedProfit = closestPoint?.totalPnL
            } else {
                selectedProfit = nil
            }
        }
    }
    
    // MARK: - Metrics Card
    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Metrics")
                .font(.headline)
            
            VStack(spacing: 12) {
                MetricRow(title: "Max Profit", value: formatPrice(maxProfit), color: .green)
                Divider()
                MetricRow(title: "Max Loss", value: formatPrice(maxLoss), color: .red)
                Divider()
                
                HStack {
                    Text("Break-Even Points")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if breakEvenPoints.isEmpty {
                        Text("None")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                    } else {
                        VStack(alignment: .trailing, spacing: 4) {
                            ForEach(breakEvenPoints, id: \.self) { point in
                                Text("$\(String(format: "%.2f", point))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Strategy Info Card
    private var strategyInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Roll Details")
                .font(.headline)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Old Position")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(oldStrategy.optionType.displayName)
                            .font(.subheadline.weight(.medium))
                        Text("Strike: $\(String(format: "%.2f", oldStrategy.strikePrice))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                HStack {
                    Text("New Position")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(newOptionType.displayName)
                            .font(.subheadline.weight(.medium))
                        Text("Strike: $\(String(format: "%.2f", newStrike))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                HStack {
                    Text("New Premium")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.2f", newPremium)) per share")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }
                
                Divider()
                
                HStack {
                    Text("Contracts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(oldStrategy.contracts)")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Helper Methods
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
    
    private func getStockAfterOldLeg() -> (Int?, Double?) {
        let (_, stockQty, stockCost) = RollCalculatorEngine.calcOldLegPnLAndStockState(
            strategy: oldStrategy,
            assumption: oldAssumption
        )
        return (stockQty, stockCost)
    }
}

#Preview {
    let sampleStrategy = OptionStrategy(
        symbol: "AAPL",
        optionType: .coveredCall,
        expirationDate: Date(),
        strikePrice: 150,
        optionPrice: 2.0,
        averagePricePerShare: 145,
        contracts: 1
    )
    
    let sampleAssumption = OldLegAssumption(
        endMode: .expired,
        closePrice: nil,
        marketPriceAtExercise: nil,
        stockPriceAtExpiration: nil
    )
    
    NavigationStack {
        RollPayoffDiagramView(
            oldStrategy: sampleStrategy,
            oldAssumption: sampleAssumption,
            newOptionType: .coveredCall,
            newStrike: 155,
            newPremium: 1.5
        )
        .navigationTitle("Roll P/L Diagram")
        .navigationBarTitleDisplayMode(.inline)
    }
}
