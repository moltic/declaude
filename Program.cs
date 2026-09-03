using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32;

namespace Declaude
{
    class Program
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct UNICODE_STRING
        {
            public ushort Length;
            public ushort MaximumLength;
            public IntPtr Buffer;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct OBJECT_ATTRIBUTES
        {
            public int Length;
            public IntPtr RootDirectory;
            public IntPtr ObjectName;
            public uint Attributes;
            public IntPtr SecurityDescriptor;
            public IntPtr SecurityQualityOfService;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct LUID
        {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct LUID_AND_ATTRIBUTES
        {
            public LUID Luid;
            public uint Attributes;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct TOKEN_PRIVILEGES
        {
            public uint PrivilegeCount;
            public LUID_AND_ATTRIBUTES Privilege;
        }

        [DllImport("ntdll.dll", CharSet = CharSet.Unicode)]
        public static extern int NtUnloadKey2(ref OBJECT_ATTRIBUTES TargetKey, uint Flags);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr hObject);

        const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
        const uint TOKEN_QUERY = 0x0008;
        const uint SE_PRIVILEGE_ENABLED = 0x00000002;
        const uint OBJ_CASE_INSENSITIVE = 0x00000040;
        const uint REG_FORCE_UNLOAD = 0x00000001;

        static string LogFilePath
        {
            get
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Declaude");
                if (!Directory.Exists(dir))
                {
                    try { Directory.CreateDirectory(dir); } catch { }
                }
                return Path.Combine(dir, "declaude.log");
            }
        }

        static void Log(string msg)
        {
            Console.WriteLine(msg);
            try
            {
                File.AppendAllText(LogFilePath, string.Format("[{0:yyyy-MM-dd HH:mm:ss}] {1}\r\n", DateTime.Now, msg));
            }
            catch { }
        }

        static bool EnablePrivilege(string privilegeName)
        {
            IntPtr hToken;
            if (!OpenProcessToken(Process.GetCurrentProcess().Handle, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out hToken))
                return false;

            try
            {
                LUID luid;
                if (!LookupPrivilegeValue(null, privilegeName, out luid))
                    return false;

                TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
                tp.PrivilegeCount = 1;
                tp.Privilege.Luid = luid;
                tp.Privilege.Attributes = SE_PRIVILEGE_ENABLED;

                return AdjustTokenPrivileges(hToken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            }
            finally
            {
                CloseHandle(hToken);
            }
        }

        static void KillProcessesAndStopServices()
        {
            Log("[*] Stopping CoworkVMService if running...");
            try
            {
                ProcessStartInfo scPsi = new ProcessStartInfo("net.exe", "stop CoworkVMService");
                scPsi.CreateNoWindow = true;
                scPsi.UseShellExecute = false;
                Process p = Process.Start(scPsi);
                if (p != null)
                {
                    p.WaitForExit(5000);
                    Log("    CoworkVMService stop executed.");
                }
            }
            catch (Exception ex)
            {
                Log("    CoworkVMService stop notice: " + ex.Message);
            }

            string[] procsToKill = new string[] { "Claude", "cowork-svc", "chrome-native-host" };
            foreach (string name in procsToKill)
            {
                try
                {
                    Process[] procs = Process.GetProcessesByName(name);
                    foreach (Process p in procs)
                    {
                        Log(string.Format("    Terminating process: {0} (PID {1})", p.ProcessName, p.Id));
                        p.Kill();
                        p.WaitForExit(2000);
                    }
                }
                catch (Exception ex)
                {
                    Log(string.Format("    Could not terminate {0}: {1}", name, ex.Message));
                }
            }
        }

        static int UnloadKey(string keyPath)
        {
            UNICODE_STRING uStr = new UNICODE_STRING();
            uStr.Length = (ushort)(keyPath.Length * 2);
            uStr.MaximumLength = (ushort)(uStr.Length + 2);
            uStr.Buffer = Marshal.StringToHGlobalUni(keyPath);

            IntPtr pUStr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(UNICODE_STRING)));
            Marshal.StructureToPtr(uStr, pUStr, false);

            OBJECT_ATTRIBUTES objAttr = new OBJECT_ATTRIBUTES();
            objAttr.Length = Marshal.SizeOf(typeof(OBJECT_ATTRIBUTES));
            objAttr.RootDirectory = IntPtr.Zero;
            objAttr.ObjectName = pUStr;
            objAttr.Attributes = OBJ_CASE_INSENSITIVE;
            objAttr.SecurityDescriptor = IntPtr.Zero;
            objAttr.SecurityQualityOfService = IntPtr.Zero;

            int status = NtUnloadKey2(ref objAttr, REG_FORCE_UNLOAD);

            Marshal.FreeHGlobal(pUStr);
            Marshal.FreeHGlobal(uStr.Buffer);

            return status;
        }

        static List<string> FindClaudeHives()
        {
            List<string> hives = new List<string>();
            try
            {
                using (RegistryKey key = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\hivelist"))
                {
                    if (key != null)
                    {
                        foreach (string valName in key.GetValueNames())
                        {
                            object val = key.GetValue(valName);
                            if (val != null)
                            {
                                string path = val.ToString();
                                if (path.IndexOf("Claude", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                    valName.IndexOf("Claude", StringComparison.OrdinalIgnoreCase) >= 0)
                                {
                                    hives.Add(valName);
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Log("[-] Failed reading hivelist: " + ex.Message);
            }
            return hives;
        }

        static bool PerformUnload()
        {
            EnablePrivilege("SeRestorePrivilege");
            EnablePrivilege("SeBackupPrivilege");
            EnablePrivilege("SeTakeOwnershipPrivilege");
            EnablePrivilege("SeDebugPrivilege");

            KillProcessesAndStopServices();

            List<string> hives = FindClaudeHives();
            if (hives.Count == 0)
            {
                Log("[+] No locked Claude registry silos found in hivelist.");
                return true;
            }

            Log(string.Format("[*] Found {0} Claude registry hive(s) to unload:", hives.Count));
            bool allSuccess = true;
            foreach (string hive in hives)
            {
                int status = UnloadKey(hive);
                if (status == 0)
                {
                    Log("    [OK] Successfully force-unloaded: " + hive);
                }
                else
                {
                    Log(string.Format("    [FAIL] Status 0x{0:X8} for: {1}", status, hive));
                    allSuccess = false;
                }
            }
            return allSuccess;
        }

        static bool IsRunningAsSystem()
        {
            using (WindowsIdentity id = WindowsIdentity.GetCurrent())
            {
                return id.IsSystem;
            }
        }

        static bool IsRunningAsAdmin()
        {
            using (WindowsIdentity id = WindowsIdentity.GetCurrent())
            {
                WindowsPrincipal principal = new WindowsPrincipal(id);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
        }

        static void Main(string[] args)
        {
            Console.Title = "Declaude - Claude Desktop Unlocker";
            Console.WriteLine("=================================================");
            Console.WriteLine("   Declaude - Claude Desktop Update Unlocker     ");
            Console.WriteLine("=================================================");

            bool isSystemMode = args.Length > 0 && args[0].Equals("--system", StringComparison.OrdinalIgnoreCase);

            if (isSystemMode || IsRunningAsSystem())
            {
                Log("[*] Executing in SYSTEM context.");
                bool ok = PerformUnload();
                Environment.ExitCode = ok ? 0 : 1;
                return;
            }

            if (!IsRunningAsAdmin())
            {
                Console.WriteLine("[!] Administrator privileges required. Prompting for UAC elevation...");
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = Process.GetCurrentProcess().MainModule.FileName;
                    psi.Verb = "runas";
                    psi.UseShellExecute = true;
                    Process p = Process.Start(psi);
                    if (p != null)
                    {
                        p.WaitForExit();
                        Environment.ExitCode = p.ExitCode;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[-] Elevation cancelled or failed: " + ex.Message);
                    Environment.ExitCode = 1;
                }
                return;
            }

            // Running as elevated Administrator:
            Log("[*] Running as Administrator. Initiating cleanup...");
            KillProcessesAndStopServices();

            // Unloading differencing registry silos requires SYSTEM context in Windows kernel
            Log("[*] Dispatching hive force-unload via elevated SYSTEM worker...");
            string exePath = Process.GetCurrentProcess().MainModule.FileName;
            string taskName = "Declaude_ForceUnload_" + Guid.NewGuid().ToString("N").Substring(0, 8);

            try
            {
                // Create one-time task running as SYSTEM
                ProcessStartInfo createPsi = new ProcessStartInfo("schtasks",
                    string.Format("/create /tn \"{0}\" /tr \"\\\"{1}\\\" --system\" /sc ONCE /st 00:00 /ru \"SYSTEM\" /rl HIGHEST /f", taskName, exePath));
                createPsi.CreateNoWindow = true;
                createPsi.UseShellExecute = false;
                Process cp = Process.Start(createPsi);
                cp.WaitForExit();

                // Trigger task immediately
                ProcessStartInfo runPsi = new ProcessStartInfo("schtasks", string.Format("/run /tn \"{0}\"", taskName));
                runPsi.CreateNoWindow = true;
                runPsi.UseShellExecute = false;
                Process rp = Process.Start(runPsi);
                rp.WaitForExit();

                // Wait a moment for worker to complete
                System.Threading.Thread.Sleep(2000);

                // Clean up task
                ProcessStartInfo delPsi = new ProcessStartInfo("schtasks", string.Format("/delete /tn \"{0}\" /f", taskName));
                delPsi.CreateNoWindow = true;
                delPsi.UseShellExecute = false;
                Process dp = Process.Start(delPsi);
                dp.WaitForExit();

                Log("[+] SYSTEM worker completed.");
            }
            catch (Exception ex)
            {
                Log("[-] Failed dispatching SYSTEM worker: " + ex.Message);
            }

            // Verify if any Claude hives remain
            List<string> remaining = FindClaudeHives();
            if (remaining.Count == 0)
            {
                Log("[+] SUCCESS: All locked Claude silos and handles have been released!");
                Log("[*] Launching Claude Desktop...");
                try
                {
                    Process.Start("explorer.exe", "shell:AppsFolder\\Claude_pzs8sxrjxfjjc!Claude");
                    Log("[+] Claude Desktop launched successfully!");
                }
                catch (Exception ex)
                {
                    Log("[!] Could not auto-launch Claude: " + ex.Message);
                }
            }
            else
            {
                Log(string.Format("[-] Warning: {0} hive(s) still remain in hivelist.", remaining.Count));
            }

            Console.WriteLine("\n[✓] Done. You can close this window now.");
            System.Threading.Thread.Sleep(3000);
        }
    }
}
