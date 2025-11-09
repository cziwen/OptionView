//
//  PositionManagerApp.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/4/25.
//

import SwiftUI
import SwiftData

@main
struct OptionViewApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            OptionStrategy.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // ------------------- ⚠️ 测试数据 - 不需要时注释掉这一行 -------------------
                    addSampleDataIfNeeded()// ------------------- ⚠️ 测试数据 - 不需要时注释掉这一行 -------------------
                    // -------------------⚠️ 测试数据 - 不需要时注释掉这一行 -------------------
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    // MARK: - 测试数据生成
    // ⚠️ 注释掉下面的整个函数来禁用测试数据
    private func addSampleDataIfNeeded() {
        let context = sharedModelContainer.mainContext
        
        // 检查是否已经有数据
        let fetchDescriptor = FetchDescriptor<OptionStrategy>()
        let existingCount = (try? context.fetchCount(fetchDescriptor)) ?? 0
        
        // 如果已经有数据，就不添加测试数据
        if existingCount > 0 {
            print("✅ 已有 \(existingCount) 条数据，跳过测试数据生成")
            return
        }
        
        print("🔧 生成测试数据...")
        
        // 创建日期
        let calendar = Calendar.current
        let today = Date()
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!
        let twoWeeks = calendar.date(byAdding: .day, value: 14, to: today)!
        let oneMonth = calendar.date(byAdding: .month, value: 1, to: today)!
        let twoMonths = calendar.date(byAdding: .month, value: 2, to: today)!
        
        // AAPL 策略 - 不同日期
        let aapl1 = OptionStrategy(
            symbol: "AAPL",
            optionType: .coveredCall,
            expirationDate: nextWeek,
            strikePrice: 180.0,
            optionPrice: 5.50,
            averagePricePerShare: 175.0,
            contracts: 5,
            exerciseStatus: .yes
        )
        
        let aapl2 = OptionStrategy(
            symbol: "AAPL",
            optionType: .cashSecuredPut,
            expirationDate: oneMonth,
            strikePrice: 165.0,
            optionPrice: 4.25,
            averagePricePerShare: 175.0,
            contracts: 3,
            exerciseStatus: .no
        )
        
        let aapl3 = OptionStrategy(
            symbol: "AAPL",
            optionType: .nakedCall,
            expirationDate: twoMonths,
            strikePrice: 185.0,
            optionPrice: 6.00,
            averagePricePerShare: 175.0,
            contracts: 4,
            exerciseStatus: .unknown
        )
        
        // TSLA 策略
        let tsla1 = OptionStrategy(
            symbol: "TSLA",
            optionType: .coveredCall,
            expirationDate: nextWeek,
            strikePrice: 250.0,
            optionPrice: 12.50,
            averagePricePerShare: 240.0,
            contracts: 2,
            exerciseStatus: .yes
        )
        
        let tsla2 = OptionStrategy(
            symbol: "TSLA",
            optionType: .cashSecuredPut,
            expirationDate: twoWeeks,
            strikePrice: 230.0,
            optionPrice: 10.00,
            averagePricePerShare: 240.0,
            contracts: 3,
            exerciseStatus: .no
        )
        
        // 插入所有策略
        let strategies = [
            aapl1, aapl2, aapl3,
            tsla1, tsla2
        ]
        
        for strategy in strategies {
            context.insert(strategy)
        }
        
        // 保存
        do {
            try context.save()
            print("✅ 成功添加 \(strategies.count) 条测试数据")
        } catch {
            print("❌ 保存测试数据失败: \(error)")
        }
    }
}
