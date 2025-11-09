//
//  RollCalculatorView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/5/25.
//  Updated by Ziwen Chen on 11/8/25.
//

import SwiftUI
import SwiftData

struct RollCalculatorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var strategies: [OptionStrategy]
    
    // 输入参数
    @State private var selectedStrategy: OptionStrategy?
    @State private var oldLegEndMode: OldLegEndMode = .expired
    @State private var closePrice: String = ""
    @State private var marketPriceAtExercise: String = ""  // Naked Call/Put 被行权时的市场价
    @State private var newStrike: String = ""
    @State private var newPremium: String = ""
    @State private var newOptionType: OptionType = .coveredCall
    // ❌ 移除：不需要预期股价，Diagram 已涵盖
    
    // 显示选择器
    @State private var showingStrategyPicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                // 选择历史策略
                Section {
                    Button {
                        showingStrategyPicker = true
                    } label: {
                        HStack {
                            Text("Select Previous Strategy")
                                .foregroundStyle(.primary)
                            Spacer()
                            if let strategy = selectedStrategy {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(strategy.symbol)")
                                        .foregroundStyle(.primary)
                                    Text(strategy.optionType.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("None")
                                    .foregroundStyle(.tertiary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    if let strategy = selectedStrategy {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Strike:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatPrice(strategy.strikePrice))
                            }
                            HStack {
                                Text("Premium Received:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatPrice(strategy.optionPrice))
                                    .foregroundStyle(.green)
                            }
                            HStack {
                                Text("Contracts:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(strategy.contracts)")
                            }
                            if strategy.optionType == .coveredCall {
                                HStack {
                                    Text("Stock Cost Basis:")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(formatPrice(strategy.averagePricePerShare))
                                }
                            }
                        }
                        .font(.subheadline)
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Previous Position")
                } footer: {
                    Text("Select the option strategy you want to roll from")
                }
                
                // 旧仓结局选择
                if selectedStrategy != nil {
                    Section {
                        Picker("Outcome", selection: $oldLegEndMode) {
                            ForEach(OldLegEndMode.allCases) { mode in
                                HStack {
                                    Image(systemName: mode.icon)
                                    Text(mode.displayName)
                                }
                                .tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        Text(oldLegEndMode.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // 如果选择了平仓，需要输入平仓价
                        if oldLegEndMode == .closed {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Close Price (per share)")
                                    Spacer()
                                    TextField("0.00", text: $closePrice)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 120)
                                }
                                
                                if !closePrice.isEmpty && !closePrice.isValidPositiveNumber {
                                    Text("Please enter a valid positive number")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        
                        // 如果是 Naked Call/Put 被行权，需要输入行权时的市场价
                        if oldLegEndMode == .exercised,
                           let strategy = selectedStrategy,
                           strategy.optionType.isNaked {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Market Price at Exercise")
                                    Spacer()
                                    TextField("0.00", text: $marketPriceAtExercise)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 120)
                                }
                                
                                Text("Stock market price when option was exercised")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if !marketPriceAtExercise.isEmpty && !marketPriceAtExercise.isValidPositiveNumber {
                                    Text("Please enter a valid positive number")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    } header: {
                        Text("Old Position Outcome")
                    } footer: {
                        Text("How did your previous option position end?")
                    }
                }
                
                // 新仓输入参数
                if selectedStrategy != nil {
                    Section {
                        // 选择新策略类型
                        Picker("New Strategy Type", selection: $newOptionType) {
                            ForEach(OptionType.allCases, id: \.self) { type in
                                Text(type.displayName)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        // 策略兼容性提示
                        if let oldType = selectedStrategy?.optionType {
                            strategyCompatibilityHint(oldType: oldType, newType: newOptionType)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("New Strike")
                                Spacer()
                                TextField("0.00", text: $newStrike)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 120)
                            }
                            
                            if !newStrike.isEmpty && !newStrike.isValidPositiveNumber {
                                Text("Please enter a valid positive number")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("New Premium (per share)")
                                Spacer()
                                TextField("0.00", text: $newPremium)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 120)
                            }
                            
                            if !newPremium.isEmpty && !newPremium.isValidPositiveNumber {
                                Text("Please enter a valid positive number")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    } header: {
                        Text("New Position Parameters")
                    } footer: {
                        Text("Choose the type of option strategy you want to roll into")
                    }
                }
                
                // Payoff Diagram 按钮
                if canShowDiagram() {
                    Section {
                        NavigationLink {
                            if let strategy = selectedStrategy,
                               let newStrikeValue = Double(newStrike),
                               let newPremiumValue = Double(newPremium) {
                                let assumption = OldLegAssumption(
                                    endMode: oldLegEndMode,
                                    closePrice: Double(closePrice),
                                    marketPriceAtExercise: Double(marketPriceAtExercise),
                                    stockPriceAtExpiration: nil
                                )
                                
                                RollPayoffDiagramView(
                                    oldStrategy: strategy,
                                    oldAssumption: assumption,
                                    newOptionType: newOptionType,
                                    newStrike: newStrikeValue,
                                    newPremium: newPremiumValue
                                )
                                .navigationTitle("Roll P/L Diagram")
                                .navigationBarTitleDisplayMode(.inline)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "chart.xyaxis.line")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        LinearGradient(
                                            colors: [.blue, .blue.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("View Payoff Diagram")
                                        .font(.headline)
                                    
                                    Text("Visualize P/L at different stock prices")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                        }
                    } header: {
                        Text("Analysis")
                    } footer: {
                        Text("See how total P/L changes with different stock prices at expiration")
                    }
                }
            }
            .navigationTitle("Roll Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingStrategyPicker) {
                StrategyPickerView(
                    strategies: strategies,
                    selectedStrategy: $selectedStrategy
                )
            }
            .onChange(of: selectedStrategy) { oldValue, newValue in
                // 当选择新策略时，自动设置默认的新策略类型为相同类型
                if let strategy = newValue {
                    newOptionType = strategy.optionType
                }
            }
        }
    }
    
    // 策略兼容性提示
    @ViewBuilder
    private func strategyCompatibilityHint(oldType: OptionType, newType: OptionType) -> some View {
        let compatibility = getStrategyCompatibility(oldType: oldType, newType: newType)
        
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: compatibility.icon)
                .foregroundStyle(compatibility.color)
                .font(.caption)
            
            Text(compatibility.message)
                .font(.caption)
                .foregroundStyle(compatibility.color)
        }
        .padding(.vertical, 4)
    }
    
    // 判断策略兼容性
    private func getStrategyCompatibility(oldType: OptionType, newType: OptionType) -> (icon: String, color: Color, message: String) {
        // 相同策略
        if oldType == newType {
            return ("checkmark.circle.fill", .green, "Rolling to the same strategy type")
        }
        
        // Call <-> Put 转换
        if oldType.isCall && newType.isPut {
            return ("exclamationmark.triangle.fill", .orange, "⚠️ Switching from Call to Put - Make sure you understand the implications")
        }
        if oldType.isPut && newType.isCall {
            return ("exclamationmark.triangle.fill", .orange, "⚠️ Switching from Put to Call - Make sure you understand the implications")
        }
        
        // Covered <-> Naked 转换
        if oldType == .coveredCall && newType == .nakedCall {
            return ("exclamationmark.triangle.fill", .orange, "⚠️ Switching to Naked Call - Higher risk, requires margin")
        }
        if oldType == .nakedCall && newType == .coveredCall {
            return ("info.circle.fill", .blue, "ℹ️ Switching to Covered Call - Need to own stock first")
        }
        if oldType == .cashSecuredPut && newType == .nakedPut {
            return ("exclamationmark.triangle.fill", .orange, "⚠️ Switching to Naked Put - Higher risk, requires margin")
        }
        if oldType == .nakedPut && newType == .cashSecuredPut {
            return ("checkmark.circle.fill", .green, "✅ Switching to Cash-Secured Put - Lower risk")
        }
        
        return ("info.circle.fill", .blue, "Rolling to a different strategy type")
    }
    
    // 检查是否可以显示 Diagram
    private func canShowDiagram() -> Bool {
        guard let strategy = selectedStrategy,
              let _ = Double(newStrike),
              let _ = Double(newPremium) else {
            return false
        }
        
        // 如果选择了 closed，必须有 closePrice
        if oldLegEndMode == .closed {
            guard let _ = Double(closePrice) else {
                return false
            }
        }
        
        // 如果是 Naked Call/Put 被行权，必须有 marketPriceAtExercise
        if oldLegEndMode == .exercised && strategy.optionType.isNaked {
            guard let _ = Double(marketPriceAtExercise) else {
                return false
            }
        }
        
        return true
    }
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
}



// MARK: - Strategy Picker View
struct StrategyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let strategies: [OptionStrategy]
    @Binding var selectedStrategy: OptionStrategy?
    
    var body: some View {
        NavigationStack {
            List {
                if strategies.isEmpty {
                    ContentUnavailableView(
                        "No Strategies",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Add some option strategies first")
                    )
                } else {
                    ForEach(strategies) { strategy in
                        Button {
                            selectedStrategy = strategy
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(strategy.symbol)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    
                                    HStack {
                                        Text(strategy.optionType.displayName)
                                        Text("•")
                                        Text(formatPrice(strategy.strikePrice))
                                        Text("•")
                                        Text(formattedDate(strategy.expirationDate))
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if let selected = selectedStrategy,
                                   selected.id == strategy.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Strategy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }
    
    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Old RollCalculator (Deprecated - kept for reference)
/*
struct RollCalculator {
    let strategy: OptionStrategy
    let currentPrice: Double
    let newStrike: Double
    let newPremium: Double
    
    // ... old implementation ...
}
*/

#Preview {
    RollCalculatorView()
        .modelContainer(for: OptionStrategy.self, inMemory: true)
}
