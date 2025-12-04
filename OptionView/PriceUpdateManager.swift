//
//  PriceUpdateManager.swift
//  OptionView
//
//  Created by Auto on 11/25/25.
//

import Foundation
import SwiftUI
import Combine

/// 全局价格更新管理器
/// 负责定期从Yahoo Finance获取股票价格并更新缓存
class PriceUpdateManager: ObservableObject {
    static let shared = PriceUpdateManager()
    
    /// 价格缓存：symbol -> price
    @Published var priceCache: [String: Double] = [:]
    
    /// 最后更新时间
    @Published var lastUpdateTime: Date?
    
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 60.0 // 60秒更新一次
    private let yahooFinanceService = YahooFinanceService.shared
    
    private init() {
        // 私有初始化，确保单例模式
    }
    
    /// 启动价格更新服务
    /// - Parameter symbols: 需要更新的股票代码列表
    func startUpdating(symbols: [String]) {
        // 停止现有定时器
        stopUpdating()
        
        // 立即执行一次更新
        Task {
            await updatePrices(for: symbols)
        }
        
        // 设置定时器，每60秒更新一次
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.updatePrices(for: symbols)
            }
        }
        
        // 确保定时器在后台线程也能运行
        RunLoop.current.add(updateTimer!, forMode: .common)
    }
    
    /// 停止价格更新服务
    func stopUpdating() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    /// 更新指定symbols的价格
    /// - Parameter symbols: 股票代码列表
    private func updatePrices(for symbols: [String]) async {
        guard !symbols.isEmpty else { return }
        
        // 去重
        let uniqueSymbols = Array(Set(symbols))
        
        print("📊 开始更新 \(uniqueSymbols.count) 个股票的价格...")
        
        let results = await yahooFinanceService.fetchPrices(for: uniqueSymbols)
        
        // 更新缓存（只更新成功获取的价格）
        await MainActor.run {
            for (symbol, price) in results {
                if let price = price {
                    self.priceCache[symbol.uppercased()] = price
                    print("✅ \(symbol): $\(String(format: "%.2f", price))")
                } else {
                    print("⚠️ \(symbol): 获取价格失败，保留缓存值")
                }
            }
            self.lastUpdateTime = Date()
            print("📊 价格更新完成，最后更新时间: \(self.lastUpdateTime?.formatted() ?? "N/A")")
        }
    }
    
    /// 获取指定symbol的价格（从缓存）
    /// - Parameter symbol: 股票代码
    /// - Returns: 价格，如果缓存中没有则返回nil
    func getPrice(for symbol: String) -> Double? {
        return priceCache[symbol.uppercased()]
    }
    
    /// 手动触发一次价格更新
    /// - Parameter symbols: 股票代码列表
    func refreshPrices(for symbols: [String]) {
        Task {
            await updatePrices(for: symbols)
        }
    }
}

