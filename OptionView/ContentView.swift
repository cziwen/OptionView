//
//  ContentView.swift
//  PositionManager
//
//  Created by Ziwen Chen on 11/4/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var priceUpdateManager = PriceUpdateManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MyStrategyView()
                .tabItem {
                    Label("My Strategy", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(0)
            
            PortfolioView()
                .tabItem {
                    Label("Portfolio", systemImage: "briefcase")
                }
                .tag(1)
            
            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
                .tag(2)
        }
        .onAppear {
            // 启动价格更新服务
            startPriceUpdateService()
        }
    }
    
    /// 启动价格更新服务
    private func startPriceUpdateService() {
        // 获取所有策略的唯一symbol列表
        let descriptor = FetchDescriptor<OptionStrategy>()
        do {
            let strategies = try modelContext.fetch(descriptor)
            let symbols = Array(Set(strategies.map { $0.symbol }))
            
            if !symbols.isEmpty {
                print("🚀 启动价格更新服务，监控 \(symbols.count) 个股票: \(symbols.joined(separator: ", "))")
                priceUpdateManager.startUpdating(symbols: symbols)
            } else {
                print("ℹ️ 暂无策略，价格更新服务待启动")
            }
        } catch {
            print("❌ 获取策略列表失败: \(error)")
        }
    }
}

// Placeholder view for future pages
struct PlaceholderView: View {
    let title: String
    
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Coming Soon",
                systemImage: "hammer",
                description: Text("\(title) feature is under development")
            )
            .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: OptionStrategy.self, inMemory: true)
}
