using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;

// ==================== 常量与全局状态 ====================

// hsmmts.exe 工作目录：全局固定路径，由单实例互斥保证不被多个实例同时使用
string exeDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Temp", "HSMM");
string exePath = Path.Combine(exeDir, "hsmmts.exe");

// 本实例创建的子进程 PID，退出时只终止这些进程，不影响系统中同名进程
var childPids = new ConcurrentBag<int>();

// 60 秒一个周期，按内存使用率分 5 档（每 20% 一档）：每分钟 1-5 次清理，均匀分布
const int CycleMs = 60_000;

// ==================== 启动 ====================

// 1. 单实例互斥：作为服务应全局唯一，避免多个实例争用同一临时目录
Mutex? singleInstance = null;
try
{
    singleInstance = new Mutex(initiallyOwned: true, @"Global\Hydride_HSMM_SingleInstance", out bool createdNew);
    if (!createdNew)
    {
        Log("ERROR: Another Hydride instance is already running. Exiting.");
        return 2;
    }
}
catch (Exception ex)
{
    Log($"WARN: Could not acquire single-instance mutex, continuing anyway: {ex.Message}");
}

// 2. 解码 LIBPCL2.dll 得到 hsmmts.exe
Directory.CreateDirectory(exeDir);

string dllPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "libs", "LIBPCL2.dll");
if (!File.Exists(dllPath))
{
    Log($"ERROR: libs\\LIBPCL2.dll not found (tried: {dllPath})");
    return 1;
}

byte[] exeBytes = Convert.FromBase64String(File.ReadAllText(dllPath).Trim());
File.WriteAllBytes(exePath, exeBytes);
Log($"hsmmts.exe written: {exePath}");
Log("Hydride System Memory Manager Service started (Press Ctrl+C to exit)");

// 3. 退出信号
using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    cts.Cancel();
};

// 4. 主服务循环
try
{
    while (!cts.Token.IsCancellationRequested)
    {
        double memPct = GetMemoryPercent();
        int runsThisCycle = Math.Clamp((int)(memPct / 20) + 1, 1, 5);
        int intervalMs = CycleMs / runsThisCycle;

        Log($"Mem {memPct:F1}% → {runsThisCycle} run(s) this cycle (every {intervalMs / 1000.0:F1}s)");

        for (int i = 0; i < runsThisCycle; i++)
        {
            if (cts.Token.IsCancellationRequested) break;

            RunCleanupOnce();

            // 取消时 WaitHandle 被置位，WaitOne 立即返回 true → 退出
            if (cts.Token.WaitHandle.WaitOne(intervalMs)) break;
        }

        Console.WriteLine();
    }
}
catch (Exception ex)
{
    Log($"Fatal error in main loop: {ex.Message}");
}
finally
{
    KillAndCleanup();
}

// 保持单实例 Mutex 存活到进程结束，避免被提前回收导致锁失效
GC.KeepAlive(singleInstance);

return 0;


// ==================== 辅助函数（由浅到深） ====================

// ── 基础工具 ──

/// 带时间戳的日志输出
static void Log(string msg) => Console.WriteLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {msg}");

// ── 内存状态（底层 P/Invoke 与结构定义） ──

[DllImport("kernel32.dll", SetLastError = true)]
static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

/// 查询系统物理内存状态，失败时抛出异常（由调用方决定如何处理）
static MEMORYSTATUSEX GetMemoryStatus()
{
    var mem = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
    if (!GlobalMemoryStatusEx(ref mem))
        throw new InvalidOperationException($"GlobalMemoryStatusEx failed: {Marshal.GetLastWin32Error()}");
    return mem;
}

/// 当前物理内存使用率（0-100）
static double GetMemoryPercent()
{
    var mem = GetMemoryStatus();
    return (double)(mem.ullTotalPhys - mem.ullAvailPhys) / mem.ullTotalPhys * 100.0;
}

/// 当前已使用物理内存（MB）
static long GetUsedMemoryMB()
{
    var mem = GetMemoryStatus();
    return (long)((mem.ullTotalPhys - mem.ullAvailPhys) / 1024 / 1024);
}

// ── 子进程执行 ──

/// 启动 hsmmts.exe 并等待其结束，超时（15 秒）则强制终止整棵进程树
void RunExe(ProcessStartInfo psi)
{
    Process? p = null;
    try
    {
        p = Process.Start(psi);
        if (p == null)
        {
            Log($"Failed to start process (Process.Start returned null): {psi.FileName}");
            return;
        }

        // 记录本实例创建的子进程 PID
        childPids.Add(p.Id);

        if (!p.WaitForExit(15_000))
        {
            try
            {
                p.Kill(entireProcessTree: true);
                Log($"  hsmmts PID {p.Id} timed out, killed");
            }
            catch (Exception ex) { Log($"  Failed to kill timed-out process PID {p.Id}: {ex.Message}"); }
        }
    }
    catch (Exception ex) { Log($"Failed to run {psi.FileName}: {ex.Message}"); }
    finally
    {
        p?.Dispose();
    }
}

// ── 单次清理 ──

/// 确保 hsmmts.exe 可用：被外部清理工具删除时从 LIBPCL2.dll 重新解码还原
void EnsureHsmmts()
{
    if (File.Exists(exePath)) return;

    try
    {
        Directory.CreateDirectory(exeDir);
        byte[] exeBytes = Convert.FromBase64String(File.ReadAllText(dllPath).Trim());
        File.WriteAllBytes(exePath, exeBytes);
        Log($"hsmmts.exe missing, restored: {exePath}");
    }
    catch (Exception ex) { Log($"Failed to restore hsmmts.exe: {ex.Message}"); }
}

/// 执行一次内存清理：运行 hsmmts.exe --memory，对比清理前后内存，并删除其工作目录
void RunCleanupOnce()
{
    try
    {
        EnsureHsmmts();
        var psi = new ProcessStartInfo
        {
            FileName = exePath,
            Arguments = "--memory",
            UseShellExecute = false,
            CreateNoWindow = true
        };

        long before = GetUsedMemoryMB();

        RunExe(psi);
        try { Directory.Delete(Path.Combine(exeDir, "PCL"), recursive: true); }
        catch (Exception ex) { Log($"  Failed to delete PCL work dir: {ex.Message}"); }

        long after = GetUsedMemoryMB();
        long delta = before - after;
        double pctChg = before > 0 ? Math.Abs(delta) / (double)before * 100.0 : 0;
        string arrow = delta >= 0 ? "↓" : "↑";
        Console.WriteLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}]   Used: {before}MB → {after}MB ({(delta >= 0 ? "+" : "-")}{Math.Abs(delta)}MB, {pctChg:F1}%{arrow})");
    }
    catch (Exception ex) { Log($"RunCleanupOnce failed: {ex.Message}"); }
}

// ── 退出清理 ──

/// 服务退出时：只终止本实例创建的子进程，然后删除整个工作目录
void KillAndCleanup()
{
    Log("Cleaning up...");

    // 只终止本实例创建的子进程（记录 PID），不影响其他实例或系统中同名进程
    foreach (var pid in childPids)
    {
        try
        {
            using var p = Process.GetProcessById(pid);
            // 防 PID 复用误杀：确认进程名仍为 hsmmts
            if (p.ProcessName.Equals("hsmmts", StringComparison.OrdinalIgnoreCase))
            {
                p.Kill(entireProcessTree: true);
                p.WaitForExit(5_000);
                Log($"  Terminated child process PID {pid}");
            }
        }
        catch (Exception ex)
        {
            Log($"  Failed to terminate PID {pid}: {ex.Message}");
        }
    }

    try { Directory.Delete(exeDir, recursive: true); Log($"  Deleted {exeDir}"); }
    catch (Exception ex) { Log($"  Delete failed: {ex.Message}"); }

    Log("Service stopped.");
}

// ── 类型定义（置于所有顶层语句之后） ──

[StructLayout(LayoutKind.Sequential)]
struct MEMORYSTATUSEX
{
    public uint dwLength;
    public uint dwMemoryLoad;
    public ulong ullTotalPhys;
    public ulong ullAvailPhys;
    public ulong ullTotalPageFile;
    public ulong ullAvailPageFile;
    public ulong ullTotalVirtual;
    public ulong ullAvailVirtual;
    public ulong ullAvailExtendedVirtual;
}
