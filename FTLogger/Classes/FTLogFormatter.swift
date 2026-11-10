//
//  FTLogFormatter.swift
//  FTLogger
//
//  Created by 熊坤鹏 on 2026/10/15.
//

import Foundation

import CocoaLumberjack

/// 日志格式化器：决定每条日志最终输出的字符串样式。
///
/// 通过 `includeTime` 一个开关，同时服务两个后端：
/// - 控制台（DDOSLogger）：includeTime = false，os_log 自带时间戳
/// - 文件（DDFileLogger）：includeTime = true，离线排查需要时间
///
/// 输出格式（文件场景）：
/// `2026/10/15 14:30:25:123  LoginViewController.swift[42], login() 🔵 INFO: 用户登录成功: 1001`
class FTLogFormatter: NSObject {

    /// 是否在行首拼接时间戳
    let isIncludeTime: Bool

    init(includeTime: Bool = false) {
        self.isIncludeTime = includeTime
        super.init()
    }

    /// 日期格式化器，懒加载（控制台场景不会创建，省开销）
    /// 格式：2026/10/15 14:30:25:123（精确到毫秒）
    private lazy var dateFormatter: DateFormatter = {
        let temp = DateFormatter()
        temp.formatterBehavior = .behavior10_4
        temp.dateFormat = "yyyy/MM/dd HH:mm:ss:SSS"
        return temp
    }()
}

extension FTLogFormatter: DDLogFormatter {

    /// 核心方法：把 DDLogMessage 转成最终输出的字符串
    /// - Parameter logMessage: CocoaLumberjack 内部封装的日志消息对象
    /// - Returns: 格式化后的字符串；返回 nil 表示丢弃这条日志
    func format(message logMessage: DDLogMessage) -> String? {

        // 1) 级别 → emoji + 文案，控制台一眼可辨
        let level: String
        switch logMessage.flag {
        case .error:   level = "🔴 ERROR"
        case .warning: level = "🟡 WARNING"
        case .info:    level = "🔵 INFO"
        case .debug:   level = "🟢 DEBUG"
        case .verbose: level = "🟣 VERBOSE"
        default:       level = "⚫️ UNKNOWN"
        }

        // 2) 时间戳（可选）
        let time: String
        if isIncludeTime {
            time = dateFormatter.string(from: logMessage.timestamp) + "  "
        } else {
            time = ""
        }

        // 3) 组装：时间 + 短文件名[行号] + 函数名 + 级别 + 消息
        //    function 可能为 nil，做兼容分支
        if let function = logMessage.function {
            return time + "\((logMessage.file as NSString).lastPathComponent)" +
            "[\(logMessage.line)], \(function) \(level): \(logMessage.message)"
        } else {
            return time + "\((logMessage.file as NSString).lastPathComponent)" +
            "[\(logMessage.line)] \(level): \(logMessage.message)"
        }
    }
}
