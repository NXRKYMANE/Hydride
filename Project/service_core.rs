// Windows 原生结构体沿用其官方命名（MEMORYSTATUSEX 等全大写缩写）
#![allow(clippy::upper_case_acronyms)]

use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

// ==================== 常量与全局状态 ====================

const CYCLE_MS: u64 = 60_000;
const SE_PROFILE_SINGLE_PROCESS: u32 = 13;   // 清 Standby 列表所需特权
const SYSTEM_MEMORY_LIST_INFO: i32 = 80;      // NtSetSystemInformation 信息类
const SYSTEM_FILE_CACHE_INFO: i32 = 21;       // 清系统文件缓存工作集
const SYSTEM_REGISTRY_RECON_INFO: i32 = 155;  // 清注册表缓存（win8.1+）
const SYSTEM_COMBINE_PHYS_MEM_INFO: i32 = 130; // 合并物理内存列表（win10+）
const MEMORY_EMPTY_WORKING_SETS: i32 = 2;     // 内核级清空全部进程工作集
const MEMORY_PURGE_STANDBY_LIST: i32 = 4;     // 清空 Standby 列表命令
const MEMORY_PURGE_LOW_PRIORITY_STANDBY: i32 = 5; // 清空低优先级 Standby 列表
const TH32CS_SNAPPROCESS: u32 = 0x0000_0002;  // 进程快照
const PROCESS_QUERY_INFORMATION: u32 = 0x0400;
const PROCESS_SET_QUOTA: u32 = 0x0100;        // 修剪工作集所需权限
const MAX_PATH: usize = 260;
const CPU_REDUCE_HIGH: f64 = 30.0;            // CPU ≥30% 降 1 档
const CPU_REDUCE_HEAVY: f64 = 60.0;           // CPU ≥60% 降 2 档
const CPU_PAUSE: f64 = 85.0;                  // CPU ≥85% 本周期暂停

static STOP: AtomicBool = AtomicBool::new(false);
static LAST_CPU: Mutex<(u64, u64)> = Mutex::new((0, 0));  // 上次 (idle, total) 采样

// ==================== Windows FFI ====================

#[repr(C)]
struct MEMORYSTATUSEX {
    dw_length: u32,
    dw_memory_load: u32,
    ull_total_phys: u64,
    ull_avail_phys: u64,
    ull_total_page_file: u64,
    ull_avail_page_file: u64,
    ull_total_virtual: u64,
    ull_avail_virtual: u64,
    ull_avail_extended_virtual: u64,
}

#[repr(C)]
struct PROCESSENTRY32W {
    dw_size: u32,
    cnt_usage: u32,
    th32_process_id: u32,
    th32_default_heap_id: usize,
    th32_module_id: u32,
    cnt_threads: u32,
    th32_parent_process_id: u32,
    pc_pri_class_base: i32,
    dw_flags: u32,
    sz_exe_file: [u16; MAX_PATH],
}

#[repr(C)]
struct FILETIME {
    dw_low_date_time: u32,
    dw_high_date_time: u32,
}

// NtSetSystemInformation(SystemFileCacheInformation) 参数：64 字节结构，前 16 字节工作集上下限置 -1 清空文件缓存
#[repr(C)]
struct SystemFilecacheInformation {
    ul_minimum_working_set: usize,
    ul_maximum_working_set: usize,
    _reserved: [u8; 48],
}

// NtSetSystemInformation(SystemCombinePhysicalMemoryInformation) 参数：Handle=0 + 空页数组触发合并（16 字节）
#[repr(C)]
struct SystemMemoryCombineInformationEx {
    handle: *mut c_void,
    pages: [usize; 1],
}

unsafe extern "system" {
    fn GlobalMemoryStatusEx(lp_buffer: *mut MEMORYSTATUSEX) -> i32;
    fn CreateMutexW(
        attributes: *const c_void,
        initial_owner: i32,
        name: *const u16,
    ) -> *mut c_void;
    fn GetLastError() -> u32;
    fn NtSetSystemInformation(
        info_class: i32,
        info: *const c_void,
        len: u32,
    ) -> i32;
    fn NtQuerySystemInformation(
        info_class: i32,
        info: *mut c_void,
        len: u32,
        ret_len: *mut u32,
    ) -> i32;
    fn RtlAdjustPrivilege(
        privilege: u32,
        enable: u8,
        current_thread: u8,
        old_value: *mut u8,
    ) -> i32;
    fn CreateToolhelp32Snapshot(flags: u32, pid: u32) -> isize;
    fn Process32FirstW(snapshot: isize, entry: *mut PROCESSENTRY32W) -> i32;
    fn Process32NextW(snapshot: isize, entry: *mut PROCESSENTRY32W) -> i32;
    fn OpenProcess(access: u32, inherit: i32, pid: u32) -> *mut c_void;
    fn SetProcessWorkingSetSize(handle: *mut c_void, min: usize, max: usize) -> i32;
    fn CloseHandle(handle: *mut c_void) -> i32;
    fn GetSystemTimes(idle: *mut FILETIME, kernel: *mut FILETIME, user: *mut FILETIME) -> i32;
}

// ==================== 启动 ====================

pub fn main_entry() {
    if !acquire_single_instance() {
        log("ERROR: Another Hydride instance is already running. Exiting.");
        return;
    }

    enable_standby_privilege();

    log("Windows RAM Clean Service started (Press Ctrl+C to exit)");

    // Ctrl+C 置位停止标志，主循环据此退出
    ctrlc::set_handler(|| STOP.store(true, Ordering::SeqCst)).ok();

    // 主服务循环：双引擎按内存分档 + CPU 门控，同周期内交错执行
    while !STOP.load(Ordering::SeqCst) {
        let mem_pct = get_memory_percent();
        let cpu_pct = get_cpu_percent();
        // 缓存综合清理固定 1 次/分；CPU 极高时与工作集一起整周期暂停
        let standby_runs = if cpu_pct >= CPU_PAUSE { 0 } else { 1 };
        // 内存定档（1~5 次/分），CPU 高负载降档、极高本周期暂停
        let mem_runs = ((mem_pct / 25.0) as i32 + 1).clamp(1, 5);
        let ws_runs = if cpu_pct >= CPU_PAUSE {
            0
        } else if cpu_pct >= CPU_REDUCE_HEAVY {
            (mem_runs - 2).max(1)
        } else if cpu_pct >= CPU_REDUCE_HIGH {
            (mem_runs - 1).max(1)
        } else {
            mem_runs
        };
        let ws_interval = CYCLE_MS / ws_runs.max(1) as u64;
        let standby_interval = CYCLE_MS / standby_runs.max(1) as u64;

        log(&format!(
            "Mem {mem_pct:.1}% | CPU {cpu_pct:.0}% → WorkingSet {} run(s)/min, Standby {} run(s)/min",
            if ws_runs == 0 { "paused".to_string() } else { ws_runs.to_string() },
            if standby_runs == 0 { "paused".to_string() } else { standby_runs.to_string() }
        ));

        // 交错执行：记录两引擎各自的下一次触发时刻（相对周期起点）
        let start = Instant::now();
        let mut next_ws = 0u64;
        let mut next_standby = 0u64;
        let mut ws_done = 0;
        let mut standby_done = 0;

        // 周期内循环：交错执行直到本周期（60s）结束，保证周期长度恒定
        while !STOP.load(Ordering::SeqCst) {
            let elapsed = start.elapsed().as_millis() as u64;

            if ws_done < ws_runs && elapsed >= next_ws {
                run_cleanup_once();
                ws_done += 1;
                next_ws += ws_interval;
            }

            if standby_done < standby_runs && elapsed >= next_standby {
                clear_caches();
                standby_done += 1;
                next_standby += standby_interval;
            }

            // 已到周期末尾：进入下一周期
            if elapsed >= CYCLE_MS {
                break;
            }

            // 等待两引擎中更早的下一次触发点（已完成的一侧等到周期结束；每次最多 1 秒）
            let wait_until = std::cmp::min(
                if ws_done < ws_runs { next_ws } else { CYCLE_MS },
                if standby_done < standby_runs { next_standby } else { CYCLE_MS },
            );
            let wait_ms = wait_until.saturating_sub(elapsed).min(1000);
            std::thread::sleep(Duration::from_millis(wait_ms));
        }

        println!();
        use std::io::Write;
        let _ = std::io::stdout().flush();
    }

    log("Service stopped.");
}

// ==================== 基础工具 ====================

/// 日志输出（立即 flush，保证服务日志实时落盘；时间戳由服务宿主统一添加）
fn log(msg: &str) {
    use std::io::Write;
    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    let _ = writeln!(lock, "{msg}");
    let _ = lock.flush();
}

/// 缩进续行日志（清理结果行），立即 flush
fn log_cont(msg: &str) {
    use std::io::Write;
    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    let _ = writeln!(lock, "   {msg}");
    let _ = lock.flush();
}

/// 单实例互斥：作为服务应全局唯一，避免多个实例同时清理
fn acquire_single_instance() -> bool {
    let name: Vec<u16> = "Global\\Hydride_WRCS_SingleInstance"
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    let handle = unsafe { CreateMutexW(std::ptr::null(), 1, name.as_ptr()) };
    if handle.is_null() || unsafe { GetLastError() } == 183 {
        return false; // ERROR_ALREADY_EXISTS
    }
    let _ = handle; // 原始指针离开作用域不会释放句柄，锁保持有效
    true
}

/// 启用清空 Standby 列表所需特权（管理员令牌中默认禁用），失败仅记日志
fn enable_standby_privilege() {
    let mut old = 0u8;
    let status = unsafe { RtlAdjustPrivilege(SE_PROFILE_SINGLE_PROCESS, 1, 0, &mut old) };
    if status != 0 {
        log(&format!(
            "WARN: EnableStandbyPrivilege failed: NTSTATUS 0x{status:08X} (not running as administrator?)"
        ));
    }
}

// ==================== 内存状态 ====================

fn get_memory_status() -> MEMORYSTATUSEX {
    let mut mem = MEMORYSTATUSEX {
        dw_length: size_of::<MEMORYSTATUSEX>() as u32,
        dw_memory_load: 0,
        ull_total_phys: 0,
        ull_avail_phys: 0,
        ull_total_page_file: 0,
        ull_avail_page_file: 0,
        ull_total_virtual: 0,
        ull_avail_virtual: 0,
        ull_avail_extended_virtual: 0,
    };
    unsafe { GlobalMemoryStatusEx(&mut mem) };
    mem
}

/// 当前物理内存使用率（0-100）
fn get_memory_percent() -> f64 {
    let mem = get_memory_status();
    (mem.ull_total_phys - mem.ull_avail_phys) as f64 / mem.ull_total_phys as f64 * 100.0
}

/// 当前已使用物理内存（MB）
fn get_used_memory_mb() -> u64 {
    let mem = get_memory_status();
    (mem.ull_total_phys - mem.ull_avail_phys) / 1024 / 1024
}

/// 系统 CPU 使用率（0-100），基于两次采样差值；首次采样返回 0
fn get_cpu_percent() -> f64 {
    let mut idle = FILETIME { dw_low_date_time: 0, dw_high_date_time: 0 };
    let mut kernel = FILETIME { dw_low_date_time: 0, dw_high_date_time: 0 };
    let mut user = FILETIME { dw_low_date_time: 0, dw_high_date_time: 0 };
    if unsafe { GetSystemTimes(&mut idle, &mut kernel, &mut user) } == 0 {
        return 0.0;
    }

    let to_u64 = |ft: FILETIME| (ft.dw_high_date_time as u64) << 32 | ft.dw_low_date_time as u64;
    let now_idle = to_u64(idle);
    let now_total = now_idle + to_u64(kernel) + to_u64(user);

    let mut last = LAST_CPU.lock().unwrap();
    if last.1 == 0 || now_total <= last.1 {
        *last = (now_idle, now_total);
        return 0.0; // 首次采样或时间倒退，无法计算
    }
    let idle_delta = now_idle - last.0;
    let total_delta = now_total - last.1;
    *last = (now_idle, now_total);
    if total_delta == 0 {
        return 0.0;
    }
    (1.0 - idle_delta as f64 / total_delta as f64) * 100.0
}

/// 当前 Standby 缓存大小（MB），失败返回 0
fn get_standby_mb() -> u64 {
    // 先以 0 长度查询所需缓冲大小（必然返回长度不足，仅取 len），再按字段偏移读取
    let mut len = 0u32;
    let _ = unsafe { NtQuerySystemInformation(SYSTEM_MEMORY_LIST_INFO, std::ptr::null_mut(), 0, &mut len) };
    if len == 0 {
        return 0;
    }

    let mut buf = vec![0u8; len as usize];
    let status = unsafe { NtQuerySystemInformation(SYSTEM_MEMORY_LIST_INFO, buf.as_mut_ptr() as *mut c_void, len, &mut len) };
    if status != 0 {
        return 0;
    }

    // StandbyPageCount 为第 7 个 ULONG_PTR（偏移 48），随后 5 类缓存细分；每页 4KB
    let read_u64 = |off: usize| u64::from_le_bytes(buf[off..off + 8].try_into().unwrap());
    let pages = read_u64(48) + read_u64(56) + read_u64(64) + read_u64(72) + read_u64(80) + read_u64(88);
    pages * 4 / 1024
}

// ==================== 工作集清理引擎 ====================

/// 内核级清空全部进程工作集（一条调用），失败（无特权）则回退到逐进程修剪
fn trim_working_sets() {
    if !set_memory_command(MEMORY_EMPTY_WORKING_SETS) {
        trim_working_sets_by_enumeration();
    }
}

/// 内核级内存列表命令（NtSetSystemInformation(SystemMemoryListInformation)），成功返回 true
fn set_memory_command(command: i32) -> bool {
    let status = unsafe {
        NtSetSystemInformation(
            SYSTEM_MEMORY_LIST_INFO,
            &command as *const i32 as *const c_void,
            size_of::<i32>() as u32,
        )
    };
    if status != 0 {
        log(&format!("MemoryList command {command} failed: NTSTATUS 0x{status:08X}"));
        return false;
    }
    true
}

/// 遍历系统进程，对每个进程修剪工作集（EmptyWorkingSet），失败静默跳过
fn trim_working_sets_by_enumeration() {
    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if snapshot == -1 {
        log("Failed to enumerate processes (CreateToolhelp32Snapshot)");
        return;
    }

    let mut entry = PROCESSENTRY32W {
        dw_size: size_of::<PROCESSENTRY32W>() as u32,
        cnt_usage: 0,
        th32_process_id: 0,
        th32_default_heap_id: 0,
        th32_module_id: 0,
        cnt_threads: 0,
        th32_parent_process_id: 0,
        pc_pri_class_base: 0,
        dw_flags: 0,
        sz_exe_file: [0; MAX_PATH],
    };

    let first = unsafe { Process32FirstW(snapshot, &mut entry) } != 0;
    while first {
        if entry.th32_process_id != 0 {
            trim_working_set(entry.th32_process_id);
        }
        if unsafe { Process32NextW(snapshot, &mut entry) } == 0 {
            break;
        }
    }
    let _ = unsafe { CloseHandle(snapshot as *mut c_void) };
}

/// 对单个进程调用 SetProcessWorkingSetSize(-1, -1)（EmptyWorkingSet），权限不足或系统进程自动跳过
fn trim_working_set(pid: u32) {
    let handle = unsafe { OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_SET_QUOTA, 0, pid) };
    if handle.is_null() {
        return;
    }
    let _ = unsafe { SetProcessWorkingSetSize(handle, usize::MAX, usize::MAX) };
    let _ = unsafe { CloseHandle(handle) };
}

/// 执行一次工作集清理（内核级 + 遍历兜底），按 Used 格式输出日志
fn run_cleanup_once() {
    let before = get_used_memory_mb();

    trim_working_sets();

    let after = get_used_memory_mb();
    let delta = before as i64 - after as i64;
    let pct_chg = if before > 0 {
        delta.unsigned_abs() as f64 / before as f64 * 100.0
    } else {
        0.0
    };
    let arrow = if delta >= 0 { "↓" } else { "↑" };
    log_cont(&format!(
        "Used: {before}MB → {after}MB ({}{}MB, {pct_chg:.1}%{arrow})",
        if delta >= 0 { "+" } else { "-" },
        delta.unsigned_abs()
    ));
}

// ==================== 缓存综合清理引擎 ====================

/// 清空系统各缓存列表（Standby/低优先级 Standby/系统文件缓存/注册表缓存/组合内存列表），
/// 源自 Mem Reduct 与 WinMemoryCleaner 的默认清理集交叉；各步失败仅记日志
fn clear_caches() {
    let before = get_standby_mb();

    set_memory_command(MEMORY_PURGE_STANDBY_LIST);
    set_memory_command(MEMORY_PURGE_LOW_PRIORITY_STANDBY);

    // 系统文件缓存：工作集上下限置 -1 触发清空（64 字节结构，服务 LocalSystem 环境下可用）
    let cache_info = SystemFilecacheInformation {
        ul_minimum_working_set: usize::MAX,
        ul_maximum_working_set: usize::MAX,
        _reserved: [0; 48],
    };
    let status = unsafe {
        NtSetSystemInformation(
            SYSTEM_FILE_CACHE_INFO,
            &cache_info as *const SystemFilecacheInformation as *const c_void,
            size_of::<SystemFilecacheInformation>() as u32,
        )
    };
    if status != 0 {
        log(&format!("SystemFileCache clear failed: NTSTATUS 0x{status:08X}"));
    }

    // 注册表缓存（win8.1+）
    let status = unsafe { NtSetSystemInformation(SYSTEM_REGISTRY_RECON_INFO, std::ptr::null(), 0) };
    if status != 0 {
        log(&format!("RegistryCache clear failed: NTSTATUS 0x{status:08X}"));
    }

    // 合并物理内存列表（win10+）
    let combine = SystemMemoryCombineInformationEx {
        handle: std::ptr::null_mut(),
        pages: [0],
    };
    let status = unsafe {
        NtSetSystemInformation(
            SYSTEM_COMBINE_PHYS_MEM_INFO,
            &combine as *const SystemMemoryCombineInformationEx as *const c_void,
            size_of::<SystemMemoryCombineInformationEx>() as u32,
        )
    };
    if status != 0 {
        log(&format!("CombineMemoryLists failed: NTSTATUS 0x{status:08X}"));
    }

    let after = get_standby_mb();
    let freed = before.saturating_sub(after);
    log_cont(&format!("Standby: {before}MB → {after}MB (freed {freed}MB)"));
}
