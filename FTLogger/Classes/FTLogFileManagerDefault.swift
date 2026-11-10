//
//  FTLogFileManagerDefault.swift
//  FTLogger
//
//  Created by 熊坤鹏 on 2026/10/15.
//

import Foundation

import CocoaLumberjack

/// 自定义日志文件管理器。
///
/// 继承 DDLogFileManagerDefault 后，只做两件事：
/// 1. 覆盖 newLogFileName：决定新文件叫什么
/// 2. 覆盖 isLogFile(withName:)：决定哪些文件被认作日志文件
///
/// 命名效果：`FTLog 2026-10-15--14-30-25-123.log`
class FTLogFileManagerDefault: DDLogFileManagerDefault {

    /// 新日志文件的名称。
    ///
    /// CocoaLumberjack 每次滚动生成新文件时都会读取这个属性。
    /// 格式：`FTLog 2026-10-15--14-30-25-123.log`
    ///
    /// 相比默认的 `log-XXXXXX.txt`（随机后缀），时间戳命名好处：
    /// - 文件名可读，一眼看出创建时间
    /// - 按文件名排序天然等于按时间排序
    /// - 排查问题不用打开文件就能定位时间段
    override var newLogFileName: String {
        let formattedDate = dateFormatter.string(from: Date())
        return String(format: "%@ %@.log", Constrants.logName, formattedDate)
    }

    /// 判断某个文件名是否属于本管理器的日志文件。
    ///
    /// CocoaLumberjack 在扫描日志目录、执行数量上限清理、
    /// 获取 sortedLogFilePaths 时都会调用此方法做过滤。
    ///
    /// 规则：以 "FTLog " 开头，且以 ".log" 结尾。
    /// 前缀带空格，避免匹配到 logger.log、logcat.log 这类"前缀碰巧相同"的文件。
    ///
    /// 注意：如果改了 newLogFileName 的格式，这里必须同步改，否则新文件不会被识别。
    override func isLogFile(withName fileName: String) -> Bool {
        let hasProperPrefix = fileName.hasPrefix(Constrants.logName + " ")
        let hasProperSuffix = fileName.hasSuffix(".log")
        return hasProperPrefix && hasProperSuffix
    }

    /// 日志文件名相关常量。
    ///
    /// 单独抽出来，避免 newLogFileName 和 isLogFile 两处硬编码不一致。
    /// 注意：Constrants 是 Constants 的拼写笔误，建议改名。
    /// 优化建议：前缀最好带项目标识（如 "FTLog"），避免和其他库的日志文件冲突。
    enum Constrants {
        static let logName: String = "FTLog"
    }

    /// 用于生成文件名中的时间戳，懒加载（只有真正生成文件名时才创建）。
    ///
    /// 格式：2026-10-15--14-30-25-123
    /// 用 `'-'` 转义横线，避免和日期格式占位符混淆。
    /// 精确到毫秒，保证同一秒内多次滚动也不会重名。
    private lazy var dateFormatter: DateFormatter = {
        let temp = DateFormatter()
        temp.dateFormat = "yyyy'-'MM'-'dd'--'HH'-'mm'-'ss'-'SSS'"
        return temp
    }()
}
