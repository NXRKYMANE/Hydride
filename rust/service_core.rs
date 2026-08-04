// Windows 原生结构体沿用其官方命名（MEMORYSTATUSEX 等全大写缩写）
#![allow(clippy::upper_case_acronyms)]

use std::ffi::c_void;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use base64::Engine;

// ==================== 常量与全局状态 ====================

const CYCLE_MS: u64 = 60_000;
const SE_PROFILE_SINGLE_PROCESS: u32 = 13;   // 清 Standby 列表所需特权
const SYSTEM_MEMORY_LIST_INFO: i32 = 80;      // NtSetSystemInformation 信息类
const MEMORY_PURGE_STANDBY_LIST: i32 = 4;     // 清空 Standby 列表命令

static CHILD_PIDS: Mutex<Vec<u32>> = Mutex::new(Vec::new());
static STOP: AtomicBool = AtomicBool::new(false);

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
}

// ==================== 启动 ====================

pub fn main_entry() {
    if !acquire_single_instance() {
        log("ERROR: Another Hydride instance is already running. Exiting.");
        return;
    }

    enable_standby_privilege();

    // 解码 LIBPCL2.dll 得到 hsmmts.exe
    let exe_dir = std::env::var("WINDIR")
        .unwrap_or_else(|_| "C:\\Windows".to_string());
    let exe_dir = PathBuf::from(exe_dir).join("Temp").join("HSMM");
    let exe_path = exe_dir.join("hsmmts.exe");

    fs::create_dir_all(&exe_dir).ok();

    let dll_path = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()))
        .unwrap_or_default()
        .join("libs")
        .join("LIBPCL2.dll");

    if !dll_path.exists() {
        log(&format!("ERROR: libs\\LIBPCL2.dll not found (tried: {})", dll_path.display()));
        return;
    }

    if let Err(e) = decode_hsmmts(&dll_path, &exe_path) {
        log(&format!("ERROR: failed to decode hsmmts.exe: {e}"));
        return;
    }
    log(&format!("hsmmts.exe written: {}", exe_path.display()));
    log("Hydride System Memory Manager Service started (Press Ctrl+C to exit)");

    // Ctrl+C 置位停止标志，主循环据此退出并执行清理
    ctrlc::set_handler(|| STOP.store(true, Ordering::SeqCst)).ok();

    // 主服务循环：双引擎按内存使用率分档，同周期内交错执行
    while !STOP.load(Ordering::SeqCst) {
        let mem_pct = get_memory_percent();
        let pcl_runs = ((mem_pct / 25.0) as i32 + 1).clamp(1, 4);      // PCL2：每 25% 一档，1~4 次/分
        let standby_runs = ((mem_pct / 50.0) as i32 + 1).clamp(1, 2);  // Standby：每 50% 一档，1~2 次/分
        let pcl_interval = CYCLE_MS / pcl_runs as u64;
        let standby_interval = CYCLE_MS / standby_runs as u64;

        log(&format!(
            "Mem {mem_pct:.1}% → PCL2 {pcl_runs} run(s)/min, Standby {standby_runs} run(s)/min"
        ));

        // 交错执行：记录两引擎各自的下一次触发时刻（相对周期起点）
        let start = Instant::now();
        let mut next_pcl = 0u64;
        let mut next_standby = 0u64;
        let mut pcl_done = 0;
        let mut standby_done = 0;

        while (pcl_done < pcl_runs || standby_done < standby_runs) && !STOP.load(Ordering::SeqCst) {
            let elapsed = start.elapsed().as_millis() as u64;

            if pcl_done < pcl_runs && elapsed >= next_pcl {
                run_cleanup_once(&exe_path, &dll_path, &exe_dir);
                pcl_done += 1;
                next_pcl += pcl_interval;
            }

            if standby_done < standby_runs && elapsed >= next_standby {
                clear_standby_list();
                standby_done += 1;
                next_standby += standby_interval;
            }

            // 等待到两引擎中更早的下一次触发点（每次最多 1 秒）
            let wait_until = std::cmp::min(
                if pcl_done < pcl_runs { next_pcl } else { u64::MAX },
                if standby_done < standby_runs { next_standby } else { u64::MAX },
            );
            let wait_ms = wait_until.saturating_sub(elapsed).min(1000);
            std::thread::sleep(Duration::from_millis(wait_ms));
        }

        println!();
        use std::io::Write;
        let _ = std::io::stdout().flush();
    }

    kill_and_cleanup(&exe_dir);
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

/// 单实例互斥：作为服务应全局唯一，避免多个实例争用同一临时目录
fn acquire_single_instance() -> bool {
    let name: Vec<u16> = "Global\\Hydride_HSMM_SingleInstance"
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

/// 解码 LIBPCL2.dll（base64）为 hsmmts.exe
fn decode_hsmmts(dll_path: &Path, exe_path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let content = fs::read_to_string(dll_path)?;
    let bytes = base64::engine::general_purpose::STANDARD.decode(content.trim())?;
    fs::write(exe_path, bytes)?;
    Ok(())
}

// ==================== 内存状态 ====================

fn get_memory_status() -> MEMORYSTATUSEX {
    let mut mem = MEMORYSTATUSEX {
        dw_length: std::mem::size_of::<MEMORYSTATUSEX>() as u32,
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

/// 当前 Standby 缓存大小（MB），失败返回 0
fn get_standby_mb() -> u64 {
    // 先以 0 长度查询所需缓冲大小，再按字段偏移读取
    let mut len = 0u32;
    let status = unsafe { NtQuerySystemInformation(SYSTEM_MEMORY_LIST_INFO, std::ptr::null_mut(), 0, &mut len) };
    if status != 0 || len == 0 {
        return 0;
    }

    let mut buf = vec![0u8; len as usize];
    let status = unsafe { NtQuerySystemInformation(SYSTEM_MEMORY_LIST_INFO, buf.as_mut_ptr() as *mut c_void, len, &mut len) };
    if status != 0 {
        return 0;
    }

    // StandbyPageCount 为第 7 个 ULONG_PTR（偏移 48），随后三类缓存细分；每页 4KB
    let read_u64 = |off: usize| u64::from_le_bytes(buf[off..off + 8].try_into().unwrap());
    let pages = read_u64(48) + read_u64(56) + read_u64(64) + read_u64(72);
    pages * 4 / 1024
}

// ==================== Standby 清理 ====================

/// 清空系统 Standby 列表（缓存页），按 Standby 格式输出日志
fn clear_standby_list() {
    let before = get_standby_mb();

    let command = MEMORY_PURGE_STANDBY_LIST;
    let status = unsafe {
        NtSetSystemInformation(
            SYSTEM_MEMORY_LIST_INFO,
            &command as *const i32 as *const c_void,
            std::mem::size_of::<i32>() as u32,
        )
    };
    if status != 0 {
        log(&format!("ClearStandbyList failed: NTSTATUS 0x{status:08X}"));
        return;
    }

    let after = get_standby_mb();
    let freed = before.saturating_sub(after);
    log_cont(&format!("Standby: {before}MB → {after}MB (freed {freed}MB)"));
}

// ==================== PCL2 引擎 ====================

/// 确保 hsmmts.exe 可用：被外部清理工具删除时从 LIBPCL2.dll 重新解码还原
fn ensure_hsmmts(exe_path: &Path, dll_path: &Path) {
    if exe_path.exists() {
        return;
    }
    if let Err(e) = decode_hsmmts(dll_path, exe_path) {
        log(&format!("Failed to restore hsmmts.exe: {e}"));
        return;
    }
    log(&format!("hsmmts.exe missing, restored: {}", exe_path.display()));
}

/// 启动 hsmmts.exe --memory 并等待其结束，超时（15 秒）则强制终止整棵进程树
fn run_hsmmts(exe_path: &Path) {
    match Command::new(exe_path).arg("--memory").spawn() {
        Ok(mut child) => {
            let pid = child.id();
            CHILD_PIDS.lock().unwrap().push(pid);

            let deadline = Instant::now() + Duration::from_secs(15);
            loop {
                match child.try_wait() {
                    // 正常退出：从列表移除，退出清理不再对已结束的进程执行 taskkill
                    Ok(Some(_)) => {
                        CHILD_PIDS.lock().unwrap().retain(|&p| p != pid);
                        break;
                    }
                    Ok(None) if Instant::now() >= deadline => {
                        kill_tree(pid);
                        log(&format!("  hsmmts PID {pid} timed out, killed"));
                        break;
                    }
                    Ok(None) => std::thread::sleep(Duration::from_millis(100)),
                    Err(e) => {
                        log(&format!("Failed to wait hsmmts PID {pid}: {e}"));
                        break;
                    }
                }
            }
        }
        Err(e) => log(&format!("Failed to run {}: {e}", exe_path.display())),
    }
}

/// 强制终止整棵进程树（taskkill，输出重定向避免污染服务日志）
fn kill_tree(pid: u32) {
    let _ = Command::new("taskkill")
        .args(["/PID", &pid.to_string(), "/T", "/F"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// 执行一次 PCL2 内存清理：运行 hsmmts.exe --memory，按 Used 格式输出日志
fn run_cleanup_once(exe_path: &Path, dll_path: &Path, exe_dir: &Path) {
    ensure_hsmmts(exe_path, dll_path);

    let before = get_used_memory_mb();

    run_hsmmts(exe_path);
    fs::remove_dir_all(exe_dir.join("PCL")).ok();

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

// ==================== 退出清理 ====================

/// 服务退出时：只终止本实例创建的子进程，然后删除整个工作目录
fn kill_and_cleanup(exe_dir: &Path) {
    log("Cleaning up...");

    let pids = CHILD_PIDS.lock().unwrap().clone();
    for pid in pids {
        kill_tree(pid);
        log(&format!("  Terminated child process PID {pid}"));
    }

    match fs::remove_dir_all(exe_dir) {
        Ok(()) => log(&format!("  Deleted {}", exe_dir.display())),
        Err(e) => log(&format!("  Delete failed: {e}")),
    }

    log("Service stopped.");
}
