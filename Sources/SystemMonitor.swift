import Foundation
import Darwin
import IOKit
import IOKit.ps
@preconcurrency import UserNotifications

// MARK: - 数据模型

struct CPUUsage {
    var total: Double = 0      // 0...100（含用户+系统，按全部逻辑核）
    var user: Double = 0
    var system: Double = 0
    var idle: Double = 0
    var perCore: [Double] = []
}

struct MemoryUsage {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var free: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var active: UInt64 = 0
    var inactive: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
}

struct DiskUsage {
    var total: UInt64 = 0
    var free: UInt64 = 0
    var readBytesPerSec: Double = 0
    var writeBytesPerSec: Double = 0
}

struct NetworkUsage {
    var downBytesPerSec: Double = 0
    var upBytesPerSec: Double = 0
    var totalDown: UInt64 = 0
    var totalUp: UInt64 = 0
    var primaryInterface: String = "—"
}

struct BatteryUsage {
    var present = false
    var percent = 0
    var charging = false
    var source = "—"
}

struct ProcessEntry: Identifiable {
    var id: Int { pid }
    let pid: Int
    let name: String
    let cpu: Double
    let memMB: Double
}

/// 点击进程行后展示的详情（按需采集，不随每秒刷新拉取）
struct ProcessDetail: Identifiable {
    var id: Int { pid }
    let pid: Int
    let name: String
    let path: String
    let threadCount: Int
    let listenPorts: [Int]
    let cpu: Double
    let memMB: Double
}

/// 菜单栏可勾选的读数项
enum MenuMetric: String, CaseIterable, Identifiable {
    case cpu, memory, down, up, load, disk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .down: return "下载网速"
        case .up: return "上传网速"
        case .load: return "系统负载"
        case .disk: return "磁盘读速"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .down: return "arrow.down"
        case .up: return "arrow.up"
        case .load: return "chart.bar"
        case .disk: return "internaldrive"
        }
    }
}

/// 进程表排序字段
enum ProcessSortKey: String {
    case cpu = "CPU"
    case memMB = "内存"
    case pid = "PID"
    case name = "进程名"
}

struct Thermals {
    var state: String = "正常"              // nominal / fair / serious / critical
    var stateRaw: Int = 0
    var stateColor: String = "green"        // UI 用
    var note: String = "热状态（ProcessInfo.thermalState，公开接口）"
}

struct GPUUsage {
    var utilization: Double = -1            // -1 = 该环境不可读，不编数字
    var source: String = "IOReport（Apple Silicon 私有报告接口）"
    var note: String = "沙箱或系统策略限制时显示 —，不代表 0"
}

struct SMARTInfo: Identifiable {
    var id: String { disk }
    var available = false
    var status: String = "—"                // Verified / Failing / ...
    var disk: String = "disk0"
}

/// 告警配置（阈值百分比，0 = 关闭）
struct AlertConfig {
    var cpu: Double = 0
    var memory: Double = 0
    var holdSeconds: Int = 3   // 连续超标秒数才触发，防抖动误报
}

/// 告警事件（仅内存留存最近 30 条，不落盘）
struct AlertEvent: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let isRecovery: Bool
    let detail: String
}

/// 偏好设置持久化键
enum PrefKey {
    static let appearance = "macpulse.appearance"          // 0 跟随系统 / 1 浅色 / 2 深色
    static let refreshInterval = "macpulse.refreshInterval" // 秒
    static let menuBarVisible = "macpulse.menuBarVisible"
    static let menuBarShowNet = "macpulse.menuBarShowNet"  // 旧版兼容键
    static let menuMetrics = "macpulse.menuMetrics"        // [MenuMetric.rawValue]
    static let windowOnTop = "macpulse.windowOnTop"
    static let alertCPU = "macpulse.alertCPU"
    static let alertMemory = "macpulse.alertMemory"
    static let alertHold = "macpulse.alertHold"
}

enum PreferenceDefaults {
    static func register() {
        UserDefaults.standard.register(defaults: [
            PrefKey.appearance: 2,                 // 默认深色（高对比，避免浅色朦胧）
            PrefKey.refreshInterval: 1.0,
            PrefKey.menuBarVisible: true,
            PrefKey.menuBarShowNet: true,
            PrefKey.menuMetrics: ["cpu", "memory", "down"],
            PrefKey.windowOnTop: false,
            PrefKey.alertCPU: 0.0,
            PrefKey.alertMemory: 0.0,
            PrefKey.alertHold: 3
        ])
    }
}

struct AIService: Identifiable {
    var id: Int { port }
    let name: String
    let port: Int
    let detail: String
    var online = false
    var latencyMs: Double = 0
}

struct NowPlaying {
    var title = "当前无媒体播放"
    var artist = "—"
    var album = "—"
    var app = "—"
    var isPlaying = false
    var duration: Double = 0
    var elapsed: Double = 0
    var rate: Double = 0
}

/// 已知本地 AI 服务端口（只读探测，不发送任何数据）
private let kAIServicePorts: [(name: String, port: Int, detail: String)] = [
    ("CC Switch", 15721, "Claude Code 代理"),
    ("Ollama", 11434, "本地模型 API"),
    ("LM Studio", 1234, "本地模型 API"),
    ("llama.cpp", 8080, "OpenAI 兼容"),
    ("vLLM", 8000, "OpenAI 兼容"),
]

/// 进程名 / 路径关键词，用于识别 AI 相关进程
private let kAIKeywords: [String] = [
    "ollama", "llama", "vllm", "python", "claude", "codex", "workbuddy",
    "openclaw", "hermes", "gemini", "opencode", "llm", "transformers",
    "cc-switch", "ccswitch", "mcp-server", "cursor", "copilot", "lmstudio",
]

/// 纯本地 TCP 连接探测（127.0.0.1:port），带回环延迟；不发送任何数据
private func probeLocalPort(_ port: Int) -> (online: Bool, latencyMs: Double) {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(UInt16(port).bigEndian)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return (false, 0) }
    defer { close(fd) }
    // 本地回环 connect 微秒级返回；探测已放后台队列，不会阻塞 UI
    let start = Date()
    let result = withUnsafePointer(to: &addr) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    if result == 0 {
        return (true, Date().timeIntervalSince(start) * 1000)
    }
    return (false, 0)
}

// MARK: - 底层采集函数（纯 C / Mach / IOKit，不依赖 top、ps 等被沙箱拦截的命令）

private func sysctlString(_ name: String) -> String? {
    var size = 0
    if sysctlbyname(name, nil, &size, nil, 0) != 0 { return nil }
    var buf = [CChar](repeating: 0, count: size + 1)
    if sysctlbyname(name, &buf, &size, nil, 0) != 0 { return nil }
    return String(cString: buf)
}

private func sysctlUint64(_ name: String) -> UInt64? {
    var value: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    if sysctlbyname(name, &value, &size, nil, 0) != 0 { return nil }
    return value
}

/// host_statistics64 的 CPU 总 tick（四个状态）
private func readCPUTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { p in
            host_statistics64(mach_host_self(), host_flavor_t(HOST_CPU_LOAD_INFO), p, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }
    return (UInt64(bitPattern: Int64(info.cpu_ticks.0)),
            UInt64(bitPattern: Int64(info.cpu_ticks.1)),
            UInt64(bitPattern: Int64(info.cpu_ticks.2)),
            UInt64(bitPattern: Int64(info.cpu_ticks.3)))
}

/// 每个逻辑核的 tick 数组：[core][state]
private func readPerCoreTicks() -> [[UInt64]]? {
    var count: mach_msg_type_number_t = 0
    var numCPU: mach_msg_type_number_t = 0
    var info: processor_info_array_t?
    let kr = host_processor_info(mach_host_self(),
                                 processor_flavor_t(PROCESSOR_CPU_LOAD_INFO),
                                 &numCPU, &info, &count)
    guard kr == KERN_SUCCESS, let arr = info else { return nil }
    defer {
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: arr),
                      vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.size))
    }
    let states = Int(CPU_STATE_MAX)
    var result: [[UInt64]] = []
    for i in 0..<Int(numCPU) {
        var one: [UInt64] = []
        for s in 0..<states {
            let v = arr[i * states + s]
            one.append(UInt64(bitPattern: Int64(v)))
        }
        result.append(one)
    }
    return result
}

/// 内存统计（页数）
private func readVMStats() -> vm_statistics64_data_t? {
    var info = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { p in
            host_statistics64(mach_host_self(), host_flavor_t(HOST_VM_INFO64), p, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }
    return info
}

/// 网络字节数（取所有非 lo0 接口的 link 层累计）
private func readNetworkBytes() -> (down: UInt64, up: UInt64, iface: String)? {
    var addrs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrs) == 0, let head = addrs else { return nil }
    defer { freeifaddrs(head) }
    var down: UInt64 = 0, up: UInt64 = 0
    var primary = "—"
    var primaryTraffic: UInt64 = 0
    var cur: UnsafeMutablePointer<ifaddrs>? = head
    while let node = cur {
        let ifa = node.pointee
        if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK),
           let data = ifa.ifa_data {
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            let name = String(cString: ifa.ifa_name)
            let ib = UInt64(d.ifi_ibytes)
            let ob = UInt64(d.ifi_obytes)
            if name != "lo0" && !name.hasPrefix("gif") && !name.hasPrefix("stf") {
                down += ib
                up += ob
                // 展示流量最大的物理口（如 en0 / en1），跳过隧道口
                let traffic = ib + ob
                if traffic > primaryTraffic {
                    primaryTraffic = traffic
                    primary = name
                }
            }
        }
        cur = ifa.ifa_next
    }
    return (down, up, primary)
}

/// 磁盘累计读写字节（IOKit 遍历块存储驱动）
private func readDiskIOBytes() -> (read: UInt64, write: UInt64)? {
    let matching = IOServiceMatching("IOBlockStorageDriver")
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iter) }
    var totalRead: UInt64 = 0, totalWrite: UInt64 = 0
    var service = IOIteratorNext(iter)
    while service != 0 {
        if let props = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString,
                                                       kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
            if let r = props["Bytes (Read)"] as? NSNumber { totalRead += r.uint64Value }
            if let w = props["Bytes (Write)"] as? NSNumber { totalWrite += w.uint64Value }
        }
        IOObjectRelease(service)
        service = IOIteratorNext(iter)
    }
    return (totalRead, totalWrite)
}

/// 系统平均负载（1/5/15 分钟）。
/// 沙箱下 sysctlbyname("vm.loadavg") 会返回 size=24（应为 28）且不填 buffer，读数不可信；
/// 改用系统自带 uptime 输出解析 "load averages: a b c"。
private func readLoadAverage() -> (one: Double, five: Double, fifteen: Double) {
    let task = Process()
    task.launchPath = "/usr/bin/uptime"
    let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
    do { try task.run() } catch { return (0, 0, 0) }
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard let marker = out.range(of: "load averages:") else { return (0, 0, 0) }
    let tail = out[marker.upperBound...]
    let nums = tail.split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap { Double($0) }
    guard nums.count >= 3 else { return (0, 0, 0) }
    return (nums[0], nums[1], nums[2])
}

/// swap 使用量
private func readSwap() -> (used: UInt64, total: UInt64) {
    var size = 0
    guard sysctlbyname("vm.swapusage", nil, &size, nil, 0) == 0 else { return (0, 0) }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctlbyname("vm.swapusage", &buf, &size, nil, 0) == 0 else { return (0, 0) }
    // xsw_usage: u_int64_t xsu_total, xsu_avail, xsu_used, u_int32_t xsu_pagesize, boolean_t xsu_encrypted
    let total = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt64.self) }
    let used  = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt64.self) }
    return (used, total)
}

/// 电池（IOKit）
private func readBattery() -> BatteryUsage {
    var b = BatteryUsage()
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
          !list.isEmpty else { return b }
    for src in list {
        guard let desc = IOPSGetPowerSourceDescription(snapshot, src)?.takeUnretainedValue() as? [String: Any] else { continue }
        let cur = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
        let max = desc[kIOPSMaxCapacityKey as String] as? Int ?? 0
        guard max > 0 else { continue }
        b.present = true
        b.percent = Int(Double(cur) / Double(max) * 100)
        b.charging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
        b.source = desc[kIOPSPowerSourceStateKey as String] as? String ?? "—"
        break
    }
    return b
}

// MARK: - 进程快照（libproc，避免依赖 ps）

private struct ProcSnap {
    let pid: Int32
    let user: UInt64
    let system: UInt64
    let resident: UInt64
}

private func readProcSnapshot() -> [ProcSnap] {
    var pids = [Int32](repeating: 0, count: 8192)
    let n = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<Int32>.size * pids.count))
    let count = Int(n) / MemoryLayout<Int32>.size
    guard count > 0 else { return [] }
    var result: [ProcSnap] = []
    for i in 0..<count {
        let pid = pids[i]
        guard pid > 0 else { continue }
        var info = proc_taskinfo()
        let sz = proc_pidinfo(pid, Int32(PROC_PIDTASKINFO), 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
        guard sz == MemoryLayout<proc_taskinfo>.size else { continue }
        result.append(ProcSnap(pid: pid,
                               user: info.pti_total_user,
                               system: info.pti_total_system,
                               resident: info.pti_resident_size))
    }
    return result
}

// MARK: - 媒体播放（MediaRemote 私有框架，动态加载；macOS 标准 Now Playing 机制）

private typealias MRGetInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
private typealias MRGetPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
private typealias MRGetClient = @convention(c) (DispatchQueue, @escaping @convention(block) (CFTypeRef?) -> Void) -> Void
private typealias MRClientString = @convention(c) (CFTypeRef) -> CFString?

// MARK: - 热状态 / GPU / SMART / 告警

/// 热状态：ProcessInfo.thermalState 是 Apple 公开 API，免权限、免 root。
private func readThermals() -> Thermals {
    let raw = ProcessInfo.processInfo.thermalState.rawValue
    let (state, color): (String, String) = switch raw {
        case 0: ("正常", "green")
        case 1: ("轻度受热", "yellow")
        case 2: ("明显受热", "orange")
        default: ("严重受热", "red")
    }
    return Thermals(state: state, stateRaw: raw, stateColor: color)
}

/// IOReport 类型别名（Apple Silicon GPU 利用率，私有接口，动态加载避免沙箱启动崩溃）
private typealias IOReportCopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
private typealias IOReportCreateSubscription = @convention(c) (CFMutableDictionary?, CFMutableDictionary?, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFDictionary?) -> UnsafeMutableRawPointer?
private typealias IOReportCreateSamples = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary?, CFDictionary?) -> Unmanaged<CFDictionary>?
private typealias IOReportCreateSamplesDelta = @convention(c) (CFDictionary?, CFDictionary?, CFDictionary?) -> Unmanaged<CFDictionary>?
private typealias IOReportSimpleGet = @convention(c) (CFDictionary?, CFDictionary?) -> Int64

/// GPU 利用率：尝试 IOReport 的 GPU Busy / GPU Utilization 通道。
/// 沙箱或系统策略限制时返回 -1（界面显示 —），绝不把不可读当成 0。
private func readGPUUtilization() -> Double {
    guard let h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return -1 }
    func sym<T>(_ n: String, _ t: T.Type) -> T? {
        guard let p = dlsym(h, n) else { return nil }
        return unsafeBitCast(p, to: t)
    }
    guard let copyCh = sym("IOReportCopyChannelsInGroup", IOReportCopyChannels.self),
          let createSub = sym("IOReportCreateSubscription", IOReportCreateSubscription.self),
          let createSamples = sym("IOReportCreateSamples", IOReportCreateSamples.self),
          let createDelta = sym("IOReportCreateSamplesDelta", IOReportCreateSamplesDelta.self),
          let simpleGet = sym("IOReportSimpleGetIntegerValue", IOReportSimpleGet.self) else { return -1 }

    // 尝试多组通道名（不同 macOS / 芯片代际命名不同）
    let candidates: [(String, String)] = [
        ("GPU", "GPU Busy"), ("GPU", "GPU Utilization"),
        ("GPU", "Core Utilization"), ("SoC", "GPU Busy"),
    ]
    for (group, channel) in candidates {
        guard let chRef = copyCh(group as CFString, channel as CFString, 0, 0, 0) else { continue }
        let channels = chRef.takeRetainedValue()
        guard (channels as? [String: Any])?.isEmpty == false else { continue }
        var subscribed: Unmanaged<CFMutableDictionary>? = nil
        guard let sub = createSub(nil, channels, &subscribed, 0, nil) else { continue }
        // ★ 修复：subscribed 由 Create 规则返回，只能 takeRetainedValue 一次。
        // 两次采样都必须用 unretained 借用同一对象，否则第二次是悬空指针（读到垃圾值/崩溃）。
        guard let subDict = subscribed?.takeUnretainedValue() else { continue }
        guard let s0 = createSamples(sub, subDict, nil)?.takeRetainedValue() else {
            subscribed?.release(); continue
        }
        usleep(150_000)
        guard let s1 = createSamples(sub, subDict, nil)?.takeRetainedValue() else {
            subscribed?.release(); continue
        }
        guard let delta = createDelta(s0, s1, nil)?.takeRetainedValue() else {
            subscribed?.release(); continue
        }
        subscribed?.release()
        // kIOReportItemIndex = 0，取第一个条目的整数值
        let cfg: [String: Any] = ["kIOReportItemIndex": 0]
        let val = simpleGet(delta, cfg as CFDictionary)
        // Int64.min 表示该通道不含简单整数值（如 Volt-Temp HM 的 RawElements 结构），不是 0
        if val > 0 && val <= 100_000 {
            // 部分通道以 0..100 或 0..100000（百分比 ×1000）回报，统一归一到 0..100
            return val > 100 ? Double(val) / 1000.0 : Double(val)
        }
    }
    return -1
}

/// 枚举所有物理磁盘（diskutil list physical 只读）
private func listPhysicalDisks() -> [String] {
    let task = Process()
    task.launchPath = "/usr/sbin/diskutil"
    task.arguments = ["list", "physical"]
    let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
    do { try task.run() } catch { return ["disk0"] }
    let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    var disks: [String] = []
    for line in s.split(separator: "\n") {
        let t = String(line).trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("/dev/disk"), let d = t.split(separator: " ").first {
            disks.append(String(d.dropFirst(5)))  // "/dev/disk0" -> "disk0"
        }
    }
    return disks.isEmpty ? ["disk0"] : disks
}

/// S.M.A.R.T. 磁盘健康：diskutil info -plist（系统自带，只读，无 root）
private func readSMARTAll() -> [SMARTInfo] {
    let disks = listPhysicalDisks()
    var results: [SMARTInfo] = []
    for disk in disks {
        let task = Process()
        task.launchPath = "/usr/sbin/diskutil"
        task.arguments = ["info", "-plist", disk]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
        do { try task.run() } catch { continue }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        var format: PropertyListSerialization.PropertyListFormat = .xml
        let plist = try? PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any]
        var status = plist?["SMARTStatus"] as? String
        if status == nil {
            let s = String(data: data, encoding: .utf8) ?? ""
            if let line = s.range(of: "<key>SMARTStatus</key>"),
               let vs = s.range(of: "<string>", range: line.upperBound..<s.endIndex),
               let ve = s.range(of: "</string>", range: vs.upperBound..<s.endIndex) {
                status = String(s[vs.upperBound..<ve.lowerBound])
            }
        }
        if let st = status { results.append(SMARTInfo(available: true, status: st, disk: disk)) }
    }
    return results
}

/// 读取系统级「正在播放」信息。私有 API，失败时返回 nil（如沙箱隔离或无人播放），调用方静默降级。
private func readNowPlaying() -> NowPlaying? {
    guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else { return nil }
    func sym<T>(_ n: String, _ t: T.Type) -> T? {
        guard let p = dlsym(h, n) else { return nil }
        return unsafeBitCast(p, to: t)
    }
    guard let getInfo = sym("MRMediaRemoteGetNowPlayingInfo", MRGetInfo.self),
          let getPlaying = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying", MRGetPlaying.self) else { return nil }

    var np = NowPlaying()
    let sem = DispatchSemaphore(value: 0)
    let q = DispatchQueue.global(qos: .utility)

    getPlaying(q) { np.isPlaying = $0; sem.signal() }
    guard sem.wait(timeout: .now() + 0.5) == .success else { return nil }

    getInfo(q) { dict in
        guard let dict = dict else { sem.signal(); return }
        let d = dict as NSDictionary
        np.title = d.value(forKey: "kMRMediaRemoteNowPlayingInfoTitle") as? String ?? "未知曲目"
        np.artist = d.value(forKey: "kMRMediaRemoteNowPlayingInfoArtist") as? String ?? "—"
        np.album = d.value(forKey: "kMRMediaRemoteNowPlayingInfoAlbum") as? String ?? "—"
        np.duration = (d.value(forKey: "kMRMediaRemoteNowPlayingInfoDuration") as? NSNumber)?.doubleValue ?? 0
        np.elapsed = (d.value(forKey: "kMRMediaRemoteNowPlayingInfoElapsedTime") as? NSNumber)?.doubleValue ?? 0
        np.rate = (d.value(forKey: "kMRMediaRemoteNowPlayingInfoPlaybackRate") as? NSNumber)?.doubleValue ?? 0
        sem.signal()
    }
    guard sem.wait(timeout: .now() + 0.5) == .success else { return nil }

    if np.title == "未知曲目" && !np.isPlaying { return nil }

    if let getClient = sym("MRMediaRemoteGetNowPlayingClient", MRGetClient.self),
       let getBundle = sym("MRNowPlayingClientGetBundleIdentifier", MRClientString.self) {
        getClient(q) { client in
            if let c = client, let bundle = getBundle(c) {
                let b = bundle as String
                np.app = b.contains("music") ? "Apple Music"
                    : b.contains("spotify") ? "Spotify"
                    : b.contains("mygo") ? "MyGo Music"
                    : (b as NSString).lastPathComponent
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 0.5)
    }
    return np
}

// MARK: - 主监控器

@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published var showAbout = false
    @Published var showSettings = false

    // MARK: 偏好设置（修改即持久化）
    @Published var appearanceMode: Int = 2 {
        didSet { UserDefaults.standard.set(appearanceMode, forKey: PrefKey.appearance) }
    }
    @Published var refreshInterval: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: PrefKey.refreshInterval)
            restartTimer()
        }
    }
    @Published var menuBarVisible: Bool = true {
        didSet { UserDefaults.standard.set(menuBarVisible, forKey: PrefKey.menuBarVisible) }
    }
    @Published var menuBarShowNet: Bool = true {
        didSet { UserDefaults.standard.set(menuBarShowNet, forKey: PrefKey.menuBarShowNet) }
    }
    /// 菜单栏读数项（按数组顺序显示），修改即持久化
    @Published var menuMetrics: [MenuMetric] = [.cpu, .memory, .down] {
        didSet {
            UserDefaults.standard.set(menuMetrics.map(\.rawValue), forKey: PrefKey.menuMetrics)
            // 兼容旧设置界面读取
            menuBarShowNet = menuMetrics.contains(.down)
        }
    }
    @Published var windowOnTop: Bool = false {
        didSet { UserDefaults.standard.set(windowOnTop, forKey: PrefKey.windowOnTop) }
    }

    @Published var cpu = CPUUsage()
    @Published var memory = MemoryUsage()
    @Published var disk = DiskUsage()
    @Published var network = NetworkUsage()
    @Published var battery = BatteryUsage()
    @Published var thermals = Thermals()
    @Published var processes: [ProcessEntry] = []
    @Published var aiProcesses: [ProcessEntry] = []
    @Published var processSortKey: ProcessSortKey = .cpu
    @Published var processSortAscending = false
    @Published var processActionMessage = ""
    @Published var loadOne = 0.0
    @Published var loadFive = 0.0
    @Published var loadFifteen = 0.0
    /// MacPulse 自身开销（复用进程快照，不额外采集）
    @Published var selfCPU: Double = 0
    @Published var selfMemMB: Double = 0
    @Published var aiServices: [AIService] = []
    @Published var nowPlaying = NowPlaying()
    @Published var gpu = GPUUsage()
    @Published var smartDisks: [SMARTInfo] = []
    @Published var alertConfig = AlertConfig() {
        didSet {
            let ud = UserDefaults.standard
            ud.set(alertConfig.cpu, forKey: PrefKey.alertCPU)
            ud.set(alertConfig.memory, forKey: PrefKey.alertMemory)
            ud.set(alertConfig.holdSeconds, forKey: PrefKey.alertHold)
        }
    }
    @Published var alertStatus = ""
    /// 最近告警事件（触发 / 恢复），仅内存保留 30 条
    @Published var alertHistory: [AlertEvent] = []
    /// 进程详情弹窗选中的进程及按需读取的详情
    @Published var selectedProcess: ProcessEntry?
    @Published var selectedProcessDetail: ProcessDetail?
    @Published var detailKillArmed = false
    @Published var cpuHistory: [Double] = []
    @Published var memHistory: [Double] = []
    @Published var downHistory: [Double] = []
    @Published var upHistory: [Double] = []
    @Published var lastUpdate = Date()
    @Published var uptime: TimeInterval = 0

    // 静态系统信息
    let chipName: String
    let perfCores: Int
    let effCores: Int
    let osVersion: String
    let buildVersion: String
    let hostname: String
    let pageSize: UInt64

    private var prevCPU: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var prevCoreTicks: [[UInt64]] = []
    private var prevNet: (down: UInt64, up: UInt64)?
    private var prevDisk: (read: UInt64, write: UInt64)?
    private var prevProc: [Int32: ProcSnap] = [:]
    private var allProcesses: [ProcessEntry] = []
    private var lastProcTime: Date = Date()
    private var lastServiceProbe = Date(timeIntervalSince1970: 0)
    private var lastHeavyProbe = Date(timeIntervalSince1970: 0)
    private var lastAlertFire = Date(timeIntervalSince1970: 0)
    private var alertBreachSince: Date?
    private var alertWasActive = false
    private var timer: Timer?
    private let worker = DispatchQueue(label: "com.macpulse.worker", qos: .utility)

    private static let historyLen = 50

    init() {
        PreferenceDefaults.register()
        let ud = UserDefaults.standard
        appearanceMode = ud.integer(forKey: PrefKey.appearance)
        refreshInterval = ud.double(forKey: PrefKey.refreshInterval)
        menuBarVisible = ud.bool(forKey: PrefKey.menuBarVisible)
        menuBarShowNet = ud.bool(forKey: PrefKey.menuBarShowNet)
        // 菜单栏读数：优先新键；首次升级时按旧「显示网速」开关迁移
        let savedMetrics = ud.stringArray(forKey: PrefKey.menuMetrics) ?? []
        if savedMetrics.isEmpty {
            menuMetrics = ud.bool(forKey: PrefKey.menuBarShowNet) ? [.cpu, .memory, .down] : [.cpu, .memory]
        } else {
            let parsed = savedMetrics.compactMap { MenuMetric(rawValue: $0) }
            menuMetrics = parsed.isEmpty ? [.cpu, .memory, .down] : parsed
        }
        windowOnTop = ud.bool(forKey: PrefKey.windowOnTop)
        alertConfig = AlertConfig(cpu: ud.double(forKey: PrefKey.alertCPU),
                                  memory: ud.double(forKey: PrefKey.alertMemory),
                                  holdSeconds: ud.integer(forKey: PrefKey.alertHold))

        chipName = sysctlString("machdep.cpu.brand_string") ?? "未知芯片"
        perfCores = Int(sysctlUint64("hw.perflevel0.logicalcpu") ?? 0)
        effCores = Int(sysctlUint64("hw.perflevel1.logicalcpu") ?? 0)
        hostname = ProcessInfo.processInfo.hostName
        pageSize = UInt64(vm_page_size)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        buildVersion = sysctlString("kern.osversion") ?? "—"
        let z = [Double](repeating: 0, count: Self.historyLen)
        cpuHistory = z; memHistory = z; downHistory = z; upHistory = z
        refresh()
        restartTimer()
        // 初始化期赋值不触发 didSet，显式落盘一次，确保偏好可见
        UserDefaults.standard.set(menuMetrics.map(\.rawValue), forKey: PrefKey.menuMetrics)
    }

    deinit { timer?.invalidate() }

    /// 按偏好间隔重建刷新定时器（0.25–10 秒范围内）
    private func restartTimer() {
        timer?.invalidate()
        let interval = min(max(refreshInterval, 0.25), 10.0)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// 重置所有偏好为默认值
    func resetPreferences() {
        appearanceMode = 2
        refreshInterval = 1.0
        menuBarVisible = true
        menuBarShowNet = true
        menuMetrics = [.cpu, .memory, .down]
        windowOnTop = false
        alertConfig = AlertConfig()
        alertHistory.removeAll()
        alertWasActive = false
    }

    func refresh() {
        let now = Date()
        let dt = max(prevCPU != nil ? now.timeIntervalSince(lastTickTime) : 1.0, 0.05)
        lastTickTime = now

        refreshCPU(dt: dt)
        refreshMemory()
        refreshDisk(dt: dt)
        refreshNetwork(dt: dt)
        battery = readBattery()
        uptime = ProcessInfo.processInfo.systemUptime
        refreshProcesses(dt: dt)
        thermals = readThermals()
        checkAlerts()
        if now.timeIntervalSince(lastServiceProbe) >= 2.0 {
            refreshAIServices()
            refreshNowPlaying()
            lastServiceProbe = now
        }
        // GPU / SMART 探测较重（IOReport 订阅 + diskutil 进程），每 5 秒一次，放后台队列
        if now.timeIntervalSince(lastHeavyProbe) >= 5.0 {
            lastHeavyProbe = now
            worker.async { [weak self] in
                let gpuUtil = readGPUUtilization()
                let smartInfo = readSMARTAll()
                let load = readLoadAverage()
                Task { @MainActor in
                    self?.gpu.utilization = gpuUtil
                    self?.smartDisks = smartInfo
                    self?.loadOne = load.one
                    self?.loadFive = load.five
                    self?.loadFifteen = load.fifteen
                }
            }
        }

        lastUpdate = now
    }

    private var lastTickTime = Date()

    private func refreshCPU(dt: Double) {
        guard let t = readCPUTicks() else { return }
        if let p = prevCPU {
            let userD = wrappingDiff(t.user, p.user)
            let sysD = wrappingDiff(t.system, p.system)
            let idleD = wrappingDiff(t.idle, p.idle)
            let niceD = wrappingDiff(t.nice, p.nice)
            let totalD = userD + sysD + idleD + niceD
            if totalD > 0 {
                cpu.user = Double(userD) / Double(totalD) * 100
                cpu.system = Double(sysD) / Double(totalD) * 100
                cpu.idle = Double(idleD) / Double(totalD) * 100
                cpu.total = min(100, cpu.user + cpu.system)
                push(&cpuHistory, cpu.total)
            }
        }
        prevCPU = t

        if let cores = readPerCoreTicks() {
            var values: [Double] = []
            if prevCoreTicks.count == cores.count {
                for (i, c) in cores.enumerated() {
                    let userD = wrappingDiff(c[0], prevCoreTicks[i][0])
                    let sysD = wrappingDiff(c[1], prevCoreTicks[i][1])
                    let idleD = wrappingDiff(c[2], prevCoreTicks[i][2])
                    let niceD = wrappingDiff(c[3], prevCoreTicks[i][3])
                    let tot = userD + sysD + idleD + niceD
                    values.append(tot > 0 ? Double(userD + sysD) / Double(tot) * 100 : 0)
                }
            }
            cpu.perCore = values
            prevCoreTicks = cores
        }
    }

    private func refreshMemory() {
        guard let vm = readVMStats() else { return }
        let total = sysctlUint64("hw.memsize") ?? 0
        let p = pageSize
        let free = UInt64(vm.free_count) * p
        let active = UInt64(vm.active_count) * p
        let inactive = UInt64(vm.inactive_count) * p
        let wired = UInt64(vm.wire_count) * p
        let compressed = UInt64(vm.compressor_page_count) * p
        let cached = UInt64(vm.external_page_count) * p
        // 已用 ≈ 总 - 空闲 - 非活跃 - 文件缓存（与活动监视器口径接近）
        var used = total > 0 ? total - free - inactive - cached : 0
        if used > total { used = total }
        memory.total = total
        memory.free = free
        memory.active = active
        memory.inactive = inactive
        memory.wired = wired
        memory.compressed = compressed
        memory.cached = cached
        memory.used = used
        let sw = readSwap()
        memory.swapUsed = sw.used
        memory.swapTotal = sw.total
        push(&memHistory, total > 0 ? Double(used) / Double(total) * 100 : 0)
    }

    private func refreshDisk(dt: Double) {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            if let t = attrs[.systemSize] as? NSNumber { disk.total = t.uint64Value }
            if let f = attrs[.systemFreeSize] as? NSNumber { disk.free = f.uint64Value }
        }
        if let io = readDiskIOBytes() {
            if let p = prevDisk {
                let rd = Double(wrappingDiff(io.read, p.read)) / dt
                let wd = Double(wrappingDiff(io.write, p.write)) / dt
                disk.readBytesPerSec = max(0, rd)
                disk.writeBytesPerSec = max(0, wd)
            }
            prevDisk = io
        }
    }

    private func refreshNetwork(dt: Double) {
        guard let n = readNetworkBytes() else { return }
        network.totalDown = n.down
        network.totalUp = n.up
        network.primaryInterface = n.iface
        if let p = prevNet {
            network.downBytesPerSec = Double(wrappingDiff(n.down, p.down)) / dt
            network.upBytesPerSec = Double(wrappingDiff(n.up, p.up)) / dt
        }
        prevNet = (n.down, n.up)
        push(&downHistory, network.downBytesPerSec)
        push(&upHistory, network.upBytesPerSec)
    }

    private func refreshProcesses(dt: Double) {
        let snap = readProcSnapshot()
        let now = Date()
        let interval = max(now.timeIntervalSince(lastProcTime), 0.05)
        lastProcTime = now
        var entries: [ProcessEntry] = []
        let totalMem = memory.total
        // 口径：libproc task_time 是「单核等效纳秒」，除以墙钟时间得到单核百分比
        // （单核满载 = 100%），与「活动监视器」一致。顶部 CPU 总量是全核汇总
        // （多核相加），两者口径不同，不可直接求和对比——见界面说明。
        for p in snap {
            let prev = prevProc[p.pid]
            let userNs = prev.map { wrappingDiff(p.user, $0.user) } ?? 0
            let sysNs = prev.map { wrappingDiff(p.system, $0.system) } ?? 0
            let cpuPct = Double(userNs + sysNs) / (interval * 1_000_000_000) * 100
            let memMB = totalMem > 0 ? Double(p.resident) / 1_048_576.0 : 0
            if let name = processName(pid: p.pid) {
                entries.append(ProcessEntry(pid: Int(p.pid), name: name, cpu: min(cpuPct, 100), memMB: memMB))
            }
        }
        prevProc = Dictionary(uniqueKeysWithValues: snap.map { ($0.pid, $0) })
        allProcesses = entries
        // 自身开销：从同一份快照取本进程（单核口径，与进程表一致）
        let myPid = Int32(getpid())
        if let me = entries.first(where: { $0.pid == Int(myPid) }) {
            selfCPU = me.cpu
            selfMemMB = me.memMB
        } else if let raw = snap.first(where: { $0.pid == myPid }) {
            selfCPU = 0
            selfMemMB = totalMem > 0 ? Double(raw.resident) / 1_048_576.0 : 0
        }
        applyProcessSort()
        // 复用同一份进程快照筛选 AI 相关进程（按内存排序，AI 服务多为常驻、内存更有辨识度）
        let ai = entries.filter { e in
            let lower = e.name.lowercased()
            return kAIKeywords.contains { lower.contains($0) }
        }
        aiProcesses = ai.sorted { $0.memMB > $1.memMB }.prefix(6).map { $0 }
    }

    /// 按当前列排序进程表；点击列头时切换方向并立即重排
    func setProcessSort(_ key: ProcessSortKey) {
        if processSortKey == key {
            processSortAscending.toggle()
        } else {
            processSortKey = key
            // 数值列默认降序，名称/PID 默认升序
            processSortAscending = (key == .name || key == .pid)
        }
        applyProcessSort()
    }

    private func applyProcessSort() {
        let asc = processSortAscending
        func cmp(_ a: ProcessEntry, _ b: ProcessEntry) -> Bool {
            switch processSortKey {
            case .cpu:   return asc ? a.cpu < b.cpu : a.cpu > b.cpu
            case .memMB: return asc ? a.memMB < b.memMB : a.memMB > b.memMB
            case .pid:   return asc ? a.pid < b.pid : a.pid > b.pid
            case .name:  return asc ? a.name.localizedCompare(b.name) == .orderedAscending
                                    : a.name.localizedCompare(b.name) == .orderedDescending
            }
        }
        processes = allProcesses.sorted(by: cmp).prefix(8).map { $0 }
    }

    /// 结束进程（SIGTERM 优先，失败返回错误描述）；不结束 PID 1 / 自身
    func terminateProcess(_ pid: Int) {
        guard pid > 1, pid != Int(getpid()) else {
            processActionMessage = "受保护的进程，已跳过结束操作"
            return
        }
        if kill(pid_t(pid), SIGTERM) == 0 {
            processActionMessage = "已向 PID \(pid) 发送终止信号"
        } else {
            processActionMessage = "结束 PID \(pid) 失败（errno \(errno)）"
        }
    }

    /// CPU / 内存阈值告警：需连续超标 holdSeconds 秒才触发，且每 30 秒最多通知一次
    private func checkAlerts() {
        let cfg = alertConfig
        guard cfg.cpu > 0 || cfg.memory > 0 else {
            if alertWasActive { appendAlertEvent(true, detail: "告警阈值已关闭") }
            alertStatus = ""; alertBreachSince = nil; return
        }
        var hits: [String] = []
        if cfg.cpu > 0 && cpu.total >= cfg.cpu { hits.append("CPU \(Int(cpu.total))% ≥ \(Int(cfg.cpu))%") }
        let memPct = memory.total > 0 ? Double(memory.used) / Double(memory.total) * 100 : 0
        if cfg.memory > 0 && memPct >= cfg.memory { hits.append("内存 \(Int(memPct))% ≥ \(Int(cfg.memory))%") }

        let now = Date()
        if hits.isEmpty {
            if alertWasActive { appendAlertEvent(true, detail: "CPU / 内存已恢复正常") }
            alertStatus = ""; alertBreachSince = nil
            return
        }
        // 防抖：记录连续超标起点，未满足持续时长只显示"观察中"
        if alertBreachSince == nil { alertBreachSince = now }
        let held = now.timeIntervalSince(alertBreachSince!)
        if held < Double(cfg.holdSeconds) {
            alertStatus = String(format: "观察中 %.0f/%ds · %@", held, cfg.holdSeconds, hits.joined(separator: " · "))
            return
        }
        alertStatus = "告警：" + hits.joined(separator: " · ")
        guard now.timeIntervalSince(lastAlertFire) >= 30 else { return }
        lastAlertFire = now
        appendAlertEvent(false, detail: hits.joined(separator: " · "))
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "MacPulse 性能告警"
            content.body = hits.joined(separator: "\n")
            content.sound = .default
            let req = UNNotificationRequest(identifier: "com.macpulse.alert.\(UUID().uuidString)", content: content, trigger: nil)
            center.add(req, withCompletionHandler: nil)
        }
    }

    /// 告警事件记入内存台账（最多 30 条），不落盘
    private func appendAlertEvent(_ isRecovery: Bool, detail: String) {
        alertWasActive = !isRecovery
        alertHistory.insert(AlertEvent(time: Date(), isRecovery: isRecovery, detail: detail), at: 0)
        if alertHistory.count > 30 { alertHistory.removeLast(alertHistory.count - 30) }
    }

    func clearAlertHistory() {
        alertHistory.removeAll()
    }

    /// 请求通知授权（用户从界面点击开启告警时调用）
    func requestAlertPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 选中进程：同时读取一次详情（lsof 较重，不进入每秒刷新循环）
    func selectProcess(_ entry: ProcessEntry?) {
        selectedProcess = entry
        if let e = entry { selectedProcessDetail = processDetail(for: e) }
        else { selectedProcessDetail = nil }
        detailKillArmed = false
    }

    func refreshProcessDetail() {
        guard let e = selectedProcess else { return }
        selectedProcessDetail = processDetail(for: e)
    }

    /// 按需读取进程详情（完整路径 / 线程数 / 监听端口），不进入每秒刷新循环
    func processDetail(for entry: ProcessEntry) -> ProcessDetail {
        let pid = Int32(entry.pid)
        var buf = [CChar](repeating: 0, count: 4096)
        _ = proc_pidinfo(pid, Int32(PROC_PIDPATHINFO), 0, &buf, Int32(buf.count))
        let path = String(cString: buf)

        var info = proc_taskinfo()
        var threads = 0
        let infoSize = MemoryLayout<proc_taskinfo>.size
        if proc_pidinfo(pid, Int32(PROC_PIDTASKINFO), 0, &info, Int32(infoSize)) == infoSize {
            threads = Int(info.pti_threadnum)
        }

        return ProcessDetail(pid: entry.pid,
                             name: entry.name,
                             path: path.isEmpty ? "—（读不到路径）" : path,
                             threadCount: threads,
                             listenPorts: listeningPorts(pid: entry.pid),
                             cpu: entry.cpu,
                             memMB: entry.memMB)
    }

    /// lsof 只读查询该进程的 TCP 监听端口；被沙箱拦截时返回空数组（界面显示 —）
    private func listeningPorts(pid: Int) -> [Int] {
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [] }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard let re = try? NSRegularExpression(pattern: ":(\\d+) \\(LISTEN\\)") else { return [] }
        let ns = out as NSString
        var ports: [Int] = []
        for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            if let r = Range(m.range(at: 1), in: out), let p = Int(out[r]) { ports.append(p) }
        }
        return Array(Set(ports)).sorted()
    }

    private func refreshAIServices() {
        // 探测放后台队列，避免 5 个端口的 socket connect 阻塞 UI 刷新
        worker.async { [weak self] in
            let results = kAIServicePorts.map { spec -> AIService in
                let r = probeLocalPort(spec.port)
                return AIService(name: spec.name, port: spec.port, detail: spec.detail,
                                 online: r.online, latencyMs: r.latencyMs)
            }
            Task { @MainActor in self?.aiServices = results }
        }
    }

    private func refreshNowPlaying() {
        worker.async { [weak self] in
            let info = readNowPlaying() ?? NowPlaying()
            Task { @MainActor in self?.nowPlaying = info }
        }
    }

    private func processName(pid: Int32) -> String? {
        // proc_name 在受限沙箱下会返回 0，改用 PROC_PIDPATHINFO 取路径末段
        var buf = [CChar](repeating: 0, count: 4096)
        _ = proc_pidinfo(pid, Int32(PROC_PIDPATHINFO), 0, &buf, Int32(buf.count))
        let path = String(cString: buf)
        guard !path.isEmpty else { return nil }
        return (path as NSString).lastPathComponent
    }

    private func push(_ arr: inout [Double], _ value: Double) {
        arr.append(value)
        if arr.count > Self.historyLen { arr.removeFirst(arr.count - Self.historyLen) }
    }

    private func wrappingDiff(_ cur: UInt64, _ prev: UInt64) -> UInt64 { cur &- prev }
}

// MARK: - 格式化工具

func fmtBytes(_ b: Double) -> String {
    guard b > 0 else { return "0 B" }
    if b < 1024 { return String(format: "%.0f B", b) }
    if b < 1_048_576 { return String(format: "%.1f KB", b / 1024) }
    if b < 1_073_741_824 { return String(format: "%.1f MB", b / 1_048_576) }
    return String(format: "%.2f GB", b / 1_073_741_824)
}

func fmtSpeed(_ bps: Double) -> String {
    guard bps > 0 else { return "0 B/s" }
    return fmtBytes(bps) + "/s"
}

func fmtUptime(_ t: TimeInterval) -> String {
    let d = Int(t) / 86400
    let h = (Int(t) % 86400) / 3600
    let m = (Int(t) % 3600) / 60
    return d > 0 ? "\(d)天 \(h)小时 \(m)分" : "\(h)小时 \(m)分"
}

func fmtTime(_ seconds: Double) -> String {
    guard seconds > 0 else { return "0:00" }
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
}
