//
//  AddStrategyView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/4/25.
//

import SwiftUI
import SwiftData

struct AddStrategyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // 编辑模式：传入已存在的策略
    var strategyToEdit: OptionStrategy?
    
    @State private var symbol: String = ""
    @State private var optionType: OptionType = .coveredCall
    @State private var expirationDate: Date = Date()
    @State private var strikePrice: String = ""
    @State private var optionPrice: String = ""
    @State private var averagePricePerShare: String = ""
    @State private var marginCost: String = ""  // 新增：保证金成本
    @State private var contracts: String = ""
    @State private var exerciseStatus: ExerciseStatus = .unknown
    // 市场价格现在由系统自动获取，不再需要用户输入
    
    // 缺失的错误状态（用于保存前校验）
    @State private var strikePriceError: Bool = false
    @State private var optionPriceError: Bool = false
    @State private var avgPriceError: Bool = false
    @State private var marginCostError: Bool = false
    @State private var contractsError: Bool = false
    
    // Focus states
    @FocusState private var focusedField: Field?
    
    enum Field {
        case symbol, strikePrice, optionPrice, avgPrice, marginCost, contracts
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Stock Information") {
                    TextField("Stock Symbol", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .symbol)
                        .disabled(isEditMode) // 编辑模式下不能修改 symbol
                }
                
                Section("Option Details") {
                    Picker("Option Strategy Type", selection: $optionType) {
                        ForEach(OptionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    DatePicker("Expiration Date", selection: $expirationDate, displayedComponents: .date)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Strike Price", text: $strikePrice)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .strikePrice)
                        
                        if !strikePrice.isEmpty && !strikePrice.isValidPositiveNumber {
                            Text("Please enter a valid positive number")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Option Premium", text: $optionPrice)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .optionPrice)
                        
                        if !optionPrice.isEmpty && !optionPrice.isValidPositiveNumber {
                            Text("Please enter a valid positive number")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                Section("Position Information") {
                    // 只有 Covered Call 需要输入股票均价
                    if optionType == .coveredCall {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Stock Cost Basis (Average Price Per Share)", text: $averagePricePerShare)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .avgPrice)
                            
                            if !averagePricePerShare.isEmpty && !averagePricePerShare.isValidPositiveNumber {
                                Text("Please enter a valid positive number")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            
                            Text("Enter the cost basis of your stock position")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Naked Call/Put 可以输入保证金成本（可选）
                    if optionType == .nakedCall || optionType == .nakedPut {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Margin Cost (Optional)", text: $marginCost)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .marginCost)
                            
                            if !marginCost.isEmpty && !marginCost.isValidPositiveNumber {
                                Text("Please enter a valid positive number")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            
                            // 显示估算值
                            if let strike = Double(strikePrice), let contractsInt = Int(contracts), contractsInt > 0 {
                                let estimatedRate = optionType == .nakedCall ? 0.20 : 0.15
                                let estimated = strike * Double(contractsInt) * 100 * estimatedRate
                                
                                Text("If left empty, will estimate at \(Int(estimatedRate * 100))% of strike value ≈ $\(String(format: "%.2f", estimated))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Number of Contracts", text: $contracts)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .contracts)
                        
                        if !contracts.isEmpty && !contracts.isValidPositiveInteger {
                            Text("Please enter a valid positive integer")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(isEditMode ? "Edit Strategy" : "Add Strategy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 键盘工具栏 - 显示 Done 按钮
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        // 关闭键盘
                        focusedField = nil
                    }
                }
                
                // 导航栏工具栏
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveStrategy()
                    }
                    .disabled(!isFormValid)
                }
            }
            .task {
                // 使用 task 替代 onAppear，确保在视图准备好后加载数据
                loadStrategyData()
            }
            .onChange(of: optionType) { oldValue, newValue in
                // 当切换到非 Covered Call 时，清空均价字段
                if newValue != .coveredCall {
                    averagePricePerShare = ""
                }
                // 当切换到非 Naked 策略时，清空保证金字段
                if newValue != .nakedCall && newValue != .nakedPut {
                    marginCost = ""
                }
            }
        }
    }
    
    // MARK: - 辅助属性和方法
    
    private var isEditMode: Bool {
        strategyToEdit != nil
    }
    
    // 市场价格现在由系统自动获取，不再需要手动输入
    // 以下方法已废弃，但保留以避免编译错误
    
    // 加载策略数据（编辑模式）
    private func loadStrategyData() {
        guard let strategy = strategyToEdit else { return }
        
        symbol = strategy.symbol
        optionType = strategy.optionType
        expirationDate = strategy.expirationDate
        strikePrice = String(format: "%.2f", strategy.strikePrice)
        optionPrice = String(format: "%.2f", strategy.optionPrice)
        averagePricePerShare = String(format: "%.2f", strategy.averagePricePerShare)
        contracts = String(strategy.contracts)
        // 行权状态现在由系统自动判断，不再需要加载
        exerciseStatus = strategy.exerciseStatus // 保留用于显示，但不允许用户修改
        
        // 加载保证金成本（如果有）
        if let margin = strategy.marginCost {
            marginCost = String(format: "%.2f", margin)
        }
        
        // 市场价格现在由系统自动获取，不再需要加载到输入框
    }
    
    // Validation functions
    private func validateStrikePrice() {
        if strikePrice.isEmpty {
            strikePriceError = false
            return
        }
        if let value = Double(strikePrice), value > 0 {
            strikePriceError = false
        } else {
            strikePriceError = true
        }
    }
    
    private func validateOptionPrice() {
        if optionPrice.isEmpty {
            optionPriceError = false
            return
        }
        if let value = Double(optionPrice), value > 0 {
            optionPriceError = false
        } else {
            optionPriceError = true
        }
    }
    
    private func validateAvgPrice() {
        if averagePricePerShare.isEmpty {
            avgPriceError = false
            return
        }
        if let value = Double(averagePricePerShare), value > 0 {
            avgPriceError = false
        } else {
            avgPriceError = true
        }
    }
    
    private func validateContracts() {
        if contracts.isEmpty {
            contractsError = false
            return
        }
        if let value = Int(contracts), value > 0 {
            contractsError = false
        } else {
            contractsError = true
        }
    }
    
    private var isFormValid: Bool {
        let basicValid = !symbol.isEmpty &&
                        strikePrice.isValidPositiveNumber &&
                        optionPrice.isValidPositiveNumber &&
                        contracts.isValidPositiveInteger
        
        // Covered Call 需要验证股票均价
        if optionType == .coveredCall {
            let avgPriceValid = averagePricePerShare.isValidPositiveNumber
            return basicValid && avgPriceValid
        }
        
        // 市场价格现在由系统自动获取，不再需要验证
        // 其他策略类型不需要额外验证
        return basicValid
    }
    
    private func saveStrategy() {
        // Validate all fields one more time
        validateStrikePrice()
        validateOptionPrice()
        validateContracts()
        
        // Only validate avg price for Covered Call
        if optionType == .coveredCall {
            validateAvgPrice()
            guard !avgPriceError else { return }
        }
        
        // If there are any errors, don't save
        guard !strikePriceError && !optionPriceError && !contractsError else {
            return
        }
        
        guard let strikePriceValue = Double(strikePrice),
              let optionPriceValue = Double(optionPrice),
              let contractsValue = Int(contracts) else {
            return
        }
        
        // 根据策略类型设置均价
        let avgPriceValue: Double
        if optionType == .coveredCall {
            guard let value = Double(averagePricePerShare) else { return }
            avgPriceValue = value
        } else {
            // 其他策略类型均价设为 0
            avgPriceValue = 0
        }
        
        // 处理保证金成本（仅用于 Naked Call/Put）
        let marginCostValue: Double?
        if optionType == .nakedCall || optionType == .nakedPut {
            if !marginCost.isEmpty, let value = Double(marginCost) {
                marginCostValue = value
            } else {
                marginCostValue = nil  // 留空，将使用默认估算
            }
        } else {
            marginCostValue = nil
        }
        
        // 市场价格现在由系统自动从Yahoo Finance获取和更新
        // 保存时保留现有的市场价格（如果有），但不从用户输入中获取
        var exerciseMarketPriceValue: Double? = nil
        var currentMarketPriceValue: Double? = nil
        
        // 如果是编辑模式，保留现有的市场价格
        if let existingStrategy = strategyToEdit {
            exerciseMarketPriceValue = existingStrategy.exerciseMarketPrice
            currentMarketPriceValue = existingStrategy.currentMarketPrice
        }
        
        if let existingStrategy = strategyToEdit {
            // 编辑模式：更新现有策略
            existingStrategy.optionType = optionType
            existingStrategy.expirationDate = expirationDate
            existingStrategy.strikePrice = strikePriceValue
            existingStrategy.optionPrice = optionPriceValue
            existingStrategy.averagePricePerShare = avgPriceValue
            existingStrategy.contracts = contractsValue
            // 行权状态现在由系统自动判断和更新，不再从用户输入中获取
            // 保留现有的行权状态，系统会在价格更新时自动更新
            existingStrategy.marginCost = marginCostValue
            existingStrategy.exerciseMarketPrice = exerciseMarketPriceValue
            existingStrategy.currentMarketPrice = currentMarketPriceValue
        } else {
            // 添加模式：创建新策略
            // 新策略初始状态设为 unknown，系统会在价格更新时自动判断
            let newStrategy = OptionStrategy(
                symbol: symbol,
                optionType: optionType,
                expirationDate: expirationDate,
                strikePrice: strikePriceValue,
                optionPrice: optionPriceValue,
                averagePricePerShare: avgPriceValue,
                contracts: contractsValue,
                exerciseStatus: .unknown, // 初始状态设为 unknown，系统会自动更新
                marginCost: marginCostValue,
                exerciseMarketPrice: exerciseMarketPriceValue,
                currentMarketPrice: currentMarketPriceValue
            )
            modelContext.insert(newStrategy)
        }
        
        dismiss()
    }
}

#Preview("Add Mode") {
    AddStrategyView(strategyToEdit: nil)
        .modelContainer(for: OptionStrategy.self, inMemory: true)
}

#Preview("Edit Mode") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: OptionStrategy.self, configurations: config)
    
    let sampleStrategy = OptionStrategy(
        symbol: "AAPL",
        optionType: .coveredCall,
        expirationDate: Date(),
        strikePrice: 150.0,
        optionPrice: 5.50,
        averagePricePerShare: 145.0,
        contracts: 10,
        exerciseStatus: .unknown
    )
    container.mainContext.insert(sampleStrategy)
    
    return AddStrategyView(strategyToEdit: sampleStrategy)
        .modelContainer(container)
}
