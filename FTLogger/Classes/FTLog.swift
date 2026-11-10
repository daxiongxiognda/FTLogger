//
//  FTLog.swift
//  FTLogger
//
//  Created by 熊坤鹏 on 2026/10/15.
//

import Foundation
import CocoaLumberjack

/// 无实例的命名空间，全静态方法，避免被随意 new。
///
/// 设计意图：
/// 1. 用 enum 而非 class/struct，天然不可实例化，语义上就是"工具集合"。
/// 2. 所有日志调用统一走 FTLog，业务层不直接依赖 CocoaLumberjack，
///    未来替换日志框架只需改这一个文件（门面模式 / Facade）。
/// 3. 参数统一为 String，调用方使用字符串插值，兼容 CocoaLumberjack 新版
///    DDLogMessageFormat API，避免 deprecation 警告。
public enum FTLog {

    // MARK: - 内部状态

    /// 保证 start() 只执行一次的锁
    private static let startLock = NSLock()
    private static var _started = false

    /// 文件日志器实例，供后续获取日志文件路径 / 手动上传使用
    private static var _fileLogger: DDFileLogger?

    // MARK: - 五个日志级别（结构相同，仅底层 DDLog* 不同）

    /// 错误：崩溃风险、接口失败、不可恢复问题。
    ///
    /// 使用场景：
    /// - 网络请求最终失败
    /// - 数据解析异常
    /// - 关键资源加载失败
    ///
    /// - Parameters:
    ///   - message: 日志内容，使用字符串插值构建，如 `"请求失败: \(error)"`
    ///   - file:    编译期自动注入的调用文件（#fileID，模块+文件名）
    ///   - method:  编译期自动注入的调用函数名
    ///   - line:    编译期自动注入的调用行号
    public static func error(
        _ message: DDLogMessageFormat,
        file: StaticString = #fileID,
        method: StaticString = #function,
        line: UInt = #line
    ) {
        DDLogError(
            message,
            file: file,
            function: method,
            line: line,
            asynchronous: true   // 异步写入，降低 UI 线程阻塞
        )
    }

    /// 警告：异常但可继续、降级、重试等。
    ///
    /// 使用场景：
    /// - 接口降级到缓存
    /// - 重试后仍失败但非致命
    /// - 参数不合法但已兜底
    public static func warning(
        _ message: DDLogMessageFormat,
        file: StaticString = #fileID,
        method: StaticString = #function,
        line: UInt = #line
    ) {
        DDLogWarn(
            message,
            file: file,
            function: method,
            line: line,
            asynchronous: true
        )
    }

    /// 信息：关键业务流程节点。
    ///
    /// 使用场景：
    /// - 登录成功、退出登录
    /// - 分享完成（ShareAction 里常用 FTLog.info）
    /// - 页面关键跳转
    ///
    /// 注意：文件日志的级别阈值是 .info，所以 info 及以上才会落盘。
    public static func info(
        _ message: DDLogMessageFormat,
        file: StaticString = #fileID,
        method: StaticString = #function,
        line: UInt = #line
    ) {
        DDLogInfo(
            message,
            file: file,
            function: method,
            line: line,
            asynchronous: true
        )
    }

    /// 调试：开发期细节，Release 常通过全局 log level 过滤。
    ///
    /// 使用场景：
    /// - 变量取值、分支走向
    /// - 接口入参/出参
    ///
    /// 注意：debug 默认不写入文件，只在控制台可见，避免磁盘膨胀。
    public static func debug(
        _ message: DDLogMessageFormat,
        file: StaticString = #fileID,
        method: StaticString = #function,
        line: UInt = #line
    ) {
        DDLogDebug(
            message,
            file: file,
            function: method,
            line: line,
            asynchronous: true
        )
    }

    /// 冗长：最细粒度跟踪，通常只在深度排查时临时开启。
    ///
    /// 使用场景：
    /// - 循环内部状态
    /// - 大量数据遍历细节
    public static func verbose(
        _ message: DDLogMessageFormat,
        file: StaticString = #fileID,
        method: StaticString = #function,
        line: UInt = #line
    ) {
        DDLogVerbose(
            message,
            file: file,
            function: method,
            line: line,
            asynchronous: true
        )
    }

    // MARK: - 启动时调用一次

    /// 初始化日志系统，App 启动时（如 didFinishLaunching）调用一次。
    ///
    /// 挂载两个后端：
    /// 1. DDOSLogger：输出到 Xcode 控制台 / Console.app（底层 os_log），全级别。
    /// 2. DDFileLogger：写入本地文件，仅 info 及以上，24 小时滚动，最多 7 个文件。
    ///
    /// 本方法已做幂等保护，重复调用不会重复添加 logger。
    public static func start() {
        startLock.lock()
        defer { startLock.unlock() }

        guard !_started else {
            DDLogWarn("FTLog.start() 已执行过，忽略本次调用")
            return
        }
        _started = true

        // ───────── ① 控制台 / Xcode / Console.app（底层 os_log） ─────────
        let dosLogger = DDOSLogger.sharedInstance
        dosLogger.logFormatter = FTLogFormatter()  // 默认不含时间前缀（os_log 自带时间戳）
        // 环境控制台输出全级别
        DDLog.add(dosLogger, with: .all)

        // ───────── ② 磁盘文件日志 ─────────
        // 显式指定日志目录，避免默认 Caches 被系统清理
        let logsDirectory = FTLog.defaultLogsDirectory()
        let fileManager = FTLogFileManagerDefault(logsDirectory: logsDirectory)
        let fileLogger = DDFileLogger(logFileManager: fileManager)

        // 每 24 小时滚动生成新文件（等于 kDDDefaultLogRollingFrequency）
        fileLogger.rollingFrequency = 60 * 60 * 24

        // 最多保留 7 个文件，超出的旧文件自动删除（≈ 保留一周日志）
        fileLogger.logFileManager.maximumNumberOfLogFiles = 7

        // 单个文件最大 5MB，避免极端情况单文件过大
        fileLogger.maximumFileSize = 1024 * 1024 * 5

        // 文件里的格式带时间戳，方便离线排查
        fileLogger.logFormatter = FTLogFormatter(includeTime: true)

        // 关键：文件只记录 info 及以上，避免 debug/verbose 把磁盘撑爆
        DDLog.add(fileLogger, with: .info)

        _fileLogger = fileLogger
    }

    // MARK: - 日志文件管理（后续使用）

    /// 获取当前所有日志文件路径（按时间排序，旧 -> 新）。
    /// CocoaLumberjack 提供的属性
    /// 用途：
    /// - 打包上传给服务端
    /// - 在 App 内提供"导出日志"入口
    public static func logFilePaths() -> [String] {
        guard let fileLogger = _fileLogger else {
            FTLog.warning("FTLog.start() 尚未调用，无法获取日志文件")
            return []
        }
        return fileLogger.logFileManager.sortedLogFilePaths
    }

    /// 获取当前所有日志文件的 URL（便于分享 / 上传）。
    public static func logFileURLs() -> [URL] {
        return logFilePaths().compactMap { URL(fileURLWithPath: $0) }
    }

    /// 读取所有日志内容，拼接成一个字符串（用于上报 / 展示）。
    public static func readAllLogs() -> String {
        var result = ""
        for path in logFilePaths() {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                result += content
            }
        }
        return result
    }

    /// 手动触发一次日志文件滚动（生成新文件）。
    ///
    /// 用途：上报前先把当前文件"封存"，避免上报时还在写入。
    public static func rollLogFile() {
        _fileLogger?.rollLogFile(withCompletion: nil)
    }

    /// 清理所有本地日志文件。
    public static func cleanLogs() {
        guard let fileLogger = _fileLogger else { return }
        // 删除所有已存在的日志文件
        for path in fileLogger.logFileManager.sortedLogFilePaths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - 私有工具

    /// 默认日志目录：Library/Logs/FTLogger
    ///
    /// 相比 Caches，Library/Logs 不会被系统随意清理，
    /// 但也不会像 Documents 那样被 iCloud 备份（更适合日志）。
    private static func defaultLogsDirectory() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)
        let library = paths.first ?? NSTemporaryDirectory()
        let logs = (library as NSString).appendingPathComponent("Logs/FTLogger")

        if !FileManager.default.fileExists(atPath: logs) {
            try? FileManager.default.createDirectory(
                atPath: logs,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return logs
    }
}
