//
//  YahooFinanceService.swift
//  OptionView
//
//  Created by Auto on 11/25/25.
//

import Foundation

/// Yahoo Finance API服务，用于获取股票价格
class YahooFinanceService {
    static let shared = YahooFinanceService()
    
    private init() {}
    
    /// 获取股票的最新价格
    /// - Parameter symbol: 股票代码（如 "AAPL"）
    /// - Returns: 最新价格，如果获取失败返回nil
    func fetchPrice(for symbol: String) async -> Double? {
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol.uppercased())?interval=1d&range=1d"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL for symbol: \(symbol)")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ HTTP error for symbol: \(symbol)")
                return nil
            }
            
            // 解析JSON响应
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let chart = json?["chart"] as? [String: Any],
                  let result = chart["result"] as? [[String: Any]],
                  let firstResult = result.first,
                  let meta = firstResult["meta"] as? [String: Any],
                  let regularMarketPrice = meta["regularMarketPrice"] as? Double else {
                print("❌ Failed to parse price for symbol: \(symbol)")
                return nil
            }
            
            return regularMarketPrice
            
        } catch {
            print("❌ Error fetching price for \(symbol): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 批量获取多个股票的价格
    /// - Parameter symbols: 股票代码数组
    /// - Returns: 字典，key为symbol，value为价格（如果获取失败则为nil）
    func fetchPrices(for symbols: [String]) async -> [String: Double?] {
        // 使用TaskGroup并发获取价格
        await withTaskGroup(of: (String, Double?).self) { group in
            var results: [String: Double?] = [:]
            
            for symbol in symbols {
                group.addTask {
                    let price = await self.fetchPrice(for: symbol)
                    return (symbol, price)
                }
            }
            
            for await (symbol, price) in group {
                results[symbol] = price
            }
            
            return results
        }
    }
}

