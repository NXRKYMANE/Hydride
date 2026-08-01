using System.Diagnostics;
using System.Runtime.InteropServices;

string exeDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Temp", "HSMM");
string exePath = Path.Combine(exeDir, "hsmmts.exe");

// ── 启动：解码 LIBPCL2.dll ──
Directory.CreateDirectory(exeDir);

string dllPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "libs", "LIBPCL2.dll");
if (!File.Exists(dllPath))
{
    Console.WriteLine($"ERROR: libs\\LIBPCL2.dll not found");
    Console.WriteLine($"  Tried: {dllPath}");
    return 1;
}

byte[] exeBytes = Convert.FromBase64String(File.ReadAllText(dllPath).Trim());
File.WriteAllBytes(exePath, exeBytes);
Console.WriteLine($"hsmmts.exe written: {exePath}");
Console.WriteLine("Hydride System Memory Manager Service started");
Console.WriteLine("Press Ctrl+C to exit");
Console.WriteLine();

// ── 退出清理 ──
using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    cts.Cancel();
};

// ── 主服务循环 ──
// 60 秒一个周期，8 个内存档位（每 12.5% 一档）：每分钟 1-8 次清理，均匀分布
const int CycleMs = 60_000;

try
{
    while (!cts.Token.IsCancellationRequested)
    {
        double memPct = GetMemoryPercent();
        int runsThisCycle = Math.Clamp((int)(memPct / 12.5) + 1, 1, 8);
        int intervalMs = CycleMs / runsThisCycle;

        Console.WriteLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] Mem {memPct:F1}% → {runsThisCycle} run(s) this cycle (every {intervalMs / 1000.0:F1}s)");

        for (int i = 0; i < runsThisCycle; i++)
        {
            if (cts.Token.IsCancellationRequested) break;

            RunAsmmts(exeDir, exePath);

            try { cts.Token.WaitHandle.WaitOne(intervalMs); if (cts.Token.IsCancellationRequested) break; }
            catch { break; }
        }

        Console.WriteLine();
    }
}
finally
{
    KillAndCleanup(exeDir);
}

return 0;


static void KillAndCleanup(string dir)
{
    Console.WriteLine("Cleaning up...");

    foreach (var p in Process.GetProcessesByName("hsmmts"))
    {
        try { p.Kill(entireProcessTree: true); p.WaitForExit(5_000); }
        catch { }
        finally { p.Dispose(); }
    }

    try { Directory.Delete(dir, recursive: true); Console.WriteLine($"  Deleted {dir}"); }
    catch (Exception ex) { Console.WriteLine($"  Delete failed: {ex.Message}"); }

    Console.WriteLine("Service stopped.");
}


// ── 辅助方法 ──

static void RunAsmmts(string exeDir, string exePath, string label = "  → Used:")
{
    try
    {
        var psi = new ProcessStartInfo
        {
            FileName = exePath,
            Arguments = "--memory",
            UseShellExecute = false,
            CreateNoWindow = true
        };

        long before = GetUsedMemoryMB();

        RunExe(psi);
        try { Directory.Delete(Path.Combine(exeDir, "PCL"), recursive: true); } catch { }

        long after = GetUsedMemoryMB();
        long delta = before - after;
        double pctChg = before > 0 ? Math.Abs(delta) / (double)before * 100.0 : 0;
        string arrow = delta >= 0 ? "↓" : "↑";
        Console.WriteLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {label} {before}MB → {after}MB ({(delta >= 0 ? "+" : "-")}{Math.Abs(delta)}MB, {pctChg:F1}%{arrow})");
    }
    catch { }
}

static void RunExe(ProcessStartInfo psi)
{
    Process? p = null;
    try
    {
        p = Process.Start(psi);
        if (p == null) return;

        if (!p.WaitForExit(15_000))
        {
            try { p.Kill(entireProcessTree: true); } catch { }
        }
    }
    catch { }
    finally
    {
        p?.Dispose();
    }
}

static double GetMemoryPercent()
{
    var mem = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
    GlobalMemoryStatusEx(ref mem);
    return (double)(mem.ullTotalPhys - mem.ullAvailPhys) / mem.ullTotalPhys * 100.0;
}

static long GetUsedMemoryMB()
{
    var mem = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
    GlobalMemoryStatusEx(ref mem);
    return (long)((mem.ullTotalPhys - mem.ullAvailPhys) / 1024 / 1024);
}

[DllImport("kernel32.dll", SetLastError = true)]
static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

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
