// spell-checker:ignore (names) Deno (people) Roy Ivy III * rivy (types) STARTUPINFO Unmanaged (vars) passthru

// NOTE: C#v5 code restricted (for no-dependency builds on Win10/Win11)

using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Runtime.InteropServices;

namespace shim
{

    class Program
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CreateProcess(string lpApplicationName,
            string lpCommandLine, IntPtr lpProcessAttributes,
            IntPtr lpThreadAttributes, bool bInheritHandles,
            uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory,
            [In] ref STARTUPINFO lpStartupInfo,
            out PROCESS_INFORMATION lpProcessInformation);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct STARTUPINFO
        {
            public Int32 cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public Int32 dwX;
            public Int32 dwY;
            public Int32 dwXSize;
            public Int32 dwYSize;
            public Int32 dwXCountChars;
            public Int32 dwYCountChars;
            public Int32 dwFillAttribute;
            public Int32 dwFlags;
            public Int16 wShowWindow;
            public Int16 cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern UInt32 WaitForSingleObject(IntPtr hHandle, UInt32 dwMilliseconds);
        const UInt32 INFINITE = 0xFFFFFFFF;

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool CloseHandle(IntPtr hObject);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetConsoleCtrlHandler(ConsoleCtrlHandlerFn handler, bool add);

        enum CtrlSignalType
        {
            CTRL_C_EVENT = 0,
            CTRL_BREAK_EVENT = 1,
            CTRL_CLOSE_EVENT = 2,
            CTRL_LOGOFF_EVENT = 5,
            CTRL_SHUTDOWN_EVENT = 6
        }

        private delegate bool ConsoleCtrlHandlerFn(CtrlSignalType signal);

        private static bool ConsoleCtrlHandler(CtrlSignalType signal)
        {
            switch (signal)
            {
                case CtrlSignalType.CTRL_C_EVENT:
                case CtrlSignalType.CTRL_BREAK_EVENT:
                case CtrlSignalType.CTRL_CLOSE_EVENT:
                case CtrlSignalType.CTRL_LOGOFF_EVENT:
                case CtrlSignalType.CTRL_SHUTDOWN_EVENT:
                    return true; // signal was handled
                default:
                    return false; // signal was *not* handled
            }
        }

        static int Main(/* string[] args */)
        {
            var exe = Assembly.GetExecutingAssembly().Location;
            var dir = Path.GetDirectoryName(exe);
            var name = Path.GetFileNameWithoutExtension(exe);

            var configPath = Path.Combine(dir, name + ".shim");
            if (!File.Exists(configPath))
            {
                Console.Error.WriteLine("Couldn't find " + Path.GetFileName(configPath) + " in " + dir);
                return 1;
            }

            var config = Config(configPath);
            var pathOfTarget = Path.Combine(dir, Get(config, "path")).Trim();
            var additionalTargetArgs = Get(config, "args");

            var si = new STARTUPINFO();
            var pi = new PROCESS_INFORMATION();

            // create command line for shim target
            var commandLine = Environment.CommandLine;
            var targetArgs = additionalTargetArgs ?? ""; // prefix position
            var commandWords = GetWords(commandLine);
            var arg0 = commandWords.Count > 0 ? commandWords[0].ToString().Trim() : null;
            var commandPassthruArgs = commandWords.Count > 1 ? commandLine.Substring(commandWords[1].Index) : null;

            // act as an optional, generic shimmer with pass-thru:
            // .. leave current SHIM info, if present and for SHIM_TARGETs != our direct target
            // .. o/w place SHIM info in the environment
            // * allows wrapper shell scripts to set up SHIM info for a secondary target (ie, useful for script runners, such as `deno`)
            var envShimTarget = Environment.GetEnvironmentVariable("SHIM_TARGET");
            var envShimARG0 = Environment.GetEnvironmentVariable("SHIM_ARG0");
            var envShimARGS = Environment.GetEnvironmentVariable("SHIM_ARGS");
            var shimTarget = envShimTarget != null ? envShimTarget.Trim() : null;
            var shimTargetIsEmpty = string.IsNullOrEmpty(shimTarget);
            var shimTargetIsMe = shimTarget == arg0;
            var shimTargetIsMine = shimTarget == pathOfTarget;
            var passthruArgs = shimTargetIsMe ? envShimARGS : commandPassthruArgs;
            if (shimTargetIsEmpty || shimTargetIsMe || shimTargetIsMine)
            {
                // reset SHIM info variables
                // ... except ...
                // * SHIM_EXEC is a SHIM implementation detail (and may be removed in the future)
                // * SHIM_PIPE is impossible to set up from an application; it must be done from a BAT/CMD script
                // * SHIM_ARG0 is a pass-through for `shimTargetIsMe == true`
                // * SHIM_ARGS is a pass-through for `shimTargetIsMe == true`
                // * SHIM_ARGS is a pass-through for `shimTargetIsMine == true` (ToDO: any need for 'additive passthru' of `additionalTargetArgs`?
                foreach (DictionaryEntry envVar in Environment.GetEnvironmentVariables())
                {
                    string key = (string)envVar.Key;
                    if (key.StartsWith("SHIM_"))
                    {
                        if (shimTargetIsMine || key == "SHIM_EXEC") continue;
                        if (shimTargetIsMine || key == "SHIM_PIPE") continue;
                        Environment.SetEnvironmentVariable(key, null);
                    }
                }
                Environment.SetEnvironmentVariable("SHIM_TARGET", pathOfTarget);
                if (shimTargetIsMe) {
                    Environment.SetEnvironmentVariable("SHIM_ARG0", !(string.IsNullOrEmpty(envShimARG0)) ? envShimARG0 : null);
                } else {
                    Environment.SetEnvironmentVariable("SHIM_ARG0", !(string.IsNullOrEmpty(arg0)) ? arg0 : null);
                }
                Environment.SetEnvironmentVariable("SHIM_ARGS", !(string.IsNullOrEmpty(passthruArgs)) ? passthruArgs : null);
            }

            if (!string.IsNullOrEmpty(passthruArgs))
            {
                if (!string.IsNullOrEmpty(targetArgs)) targetArgs += " ";
                targetArgs += passthruArgs;
            }
            if (!string.IsNullOrEmpty(targetArgs)) targetArgs = " " + targetArgs;
            var cmd = "\"" + pathOfTarget + "\"" + targetArgs;

            // setup "ignore" response for Ctrl-C and other signals (to allow unalloyed handling by shim target)
            // ref: [Console Control Handlers](https://docs.microsoft.com/en-us/windows/console/console-control-handlers)
            // ref: [CTRL-C and CTRL-BREAK Signals](https://docs.microsoft.com/en-us/windows/console/ctrl-c-and-ctrl-break-signals)
            // ref: [Capture Console Exit](https://stackoverflow.com/questions/474679/capture-console-exit-c-sharp)
            if (!SetConsoleCtrlHandler(ConsoleCtrlHandler, /* add handler => true */ true))
            {
                Console.Error.WriteLine("Unable to set console control handler; CTRL-C, CTRL-BREAK, ... signal behavior may be unexpected.\n");
            }

            uint exit_code = 0;

            if (!CreateProcess(null, cmd, IntPtr.Zero, IntPtr.Zero,
                bInheritHandles: true,
                dwCreationFlags: 0,
                lpEnvironment: IntPtr.Zero, // inherit parent
                lpCurrentDirectory: null, // inherit parent
                lpStartupInfo: ref si,
                lpProcessInformation: out pi))
            {
                exit_code = (uint)Marshal.GetLastWin32Error();
            } else {
                WaitForSingleObject(pi.hProcess, INFINITE);
                GetExitCodeProcess(pi.hProcess, out exit_code);

                // Close process and thread handles.
                CloseHandle(pi.hProcess);
                CloseHandle(pi.hThread);
            }

            SetConsoleCtrlHandler(ConsoleCtrlHandler, /* remove handler => false */ false);

            return (int)exit_code;
        }

        // match words (tokens, separated by whitespace, which may have double-quoted internal whitespace)
        // ToDO: [2026-09-08; rivy] handle word splitting more robustly (see `dxx.xProcess.wordSplitCLText()`)
        static MatchCollection GetWords(string cmdLine)
        {
            const char DQ = '"';
            string DQStringReS = DQ + "[^" + DQ + "]*(" + DQ + "|$)"; // matches double-quoted string (unbalanced at end-of-line is allowed)
            string wordReS = "([^" + DQ + "\\s]+|" + DQStringReS + ")+";
            Regex wordRx = new Regex(wordReS, RegexOptions.Multiline | RegexOptions.Singleline);
            return wordRx.Matches(cmdLine);
        }

        static string Get(Dictionary<string, string> dic, string key)
        {
            string value;
            dic.TryGetValue(key, out value);
            return value;
        }

        static Dictionary<string, string> Config(string path)
        {
            var config = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var line in File.ReadAllLines(path))
            {
                var m = Regex.Match(line, @"([^=]+)=(.*)");
                if (m.Success)
                {
                    config[m.Groups[1].Value.Trim()] = m.Groups[2].Value.Trim();
                }
            }
            return config;
        }
    }
}
