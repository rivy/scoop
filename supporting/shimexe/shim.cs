// spell-checker:ignore (names) Deno choco (people) Roy Ivy III * rivy (types) RCDATA STARTUPINFO Unmanaged VERSIONINFO (vars) passthru shimgen noop waitforexit usetargetworkingdirectory

// NOTE: C#v5 code restricted (for no-dependency builds on Win10/Win11)

using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Runtime.InteropServices;

// embeds a Win32 VERSIONINFO resource (visible in Explorer's file Properties > Details tab);
// readable at runtime via `FileVersionInfo.GetVersionInfo(path)` or assembly reflection
[assembly: AssemblyTitle("shim")]
[assembly: AssemblyDescription("generic command shim (used by Scoop)")]
[assembly: AssemblyProduct("Scoop")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

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

		// used to read an embedded SHIM_CONFIG resource (written by `shimgen --embed`), if present
		[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
		static extern IntPtr GetModuleHandle(string lpModuleName);

		[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
		static extern IntPtr FindResource(IntPtr hModule, string lpName, IntPtr lpType);

		[DllImport("kernel32.dll", SetLastError = true)]
		static extern IntPtr LoadResource(IntPtr hModule, IntPtr hResInfo);

		[DllImport("kernel32.dll", SetLastError = true)]
		static extern IntPtr LockResource(IntPtr hResData);

		[DllImport("kernel32.dll", SetLastError = true)]
		static extern uint SizeofResource(IntPtr hModule, IntPtr hResInfo);

		const int RT_RCDATA = 10;
		static readonly IntPtr RT_RCDATA_PTR = (IntPtr)RT_RCDATA;
		const string ShimConfigResourceName = "SHIM_CONFIG"; // must match `shimgen`'s embedded resource name

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

			// config is read from an embedded SHIM_CONFIG resource, if present (see `shimgen --embed`);
			// o/w fall back to the external sidecar `name.shim` config file (current default behavior)
			var configText = GetEmbeddedConfigText();
			if (configText == null)
			{
				if (!File.Exists(configPath))
				{
					Console.Error.WriteLine("Couldn't find " + Path.GetFileName(configPath) + " in " + dir);
					return 1;
				}
				configText = File.ReadAllText(configPath);
			}

			var config = ParseConfig(configText);
			var pathOfTarget = Path.Combine(dir, Get(config, "path")).Trim();
			var additionalTargetArgs = Get(config, "args");

			var si = new STARTUPINFO();
			var pi = new PROCESS_INFORMATION();

			// create command line for shim target
			var commandLine = Environment.CommandLine;
			var targetArgs = additionalTargetArgs ?? ""; // prefix position
			var commandWords = GetWords(commandLine);
			var arg0 = commandWords.Count > 0 ? commandWords[0].ToString().Trim() : null;

			// recognized shim-only flags (`choco`-shimgen-style); consumed here and stripped before
			// building the target's command line -- ref: <https://github.com/chocolatey/shimgen> "Shim Arguments"
			bool shimgenHelp = false, shimgenLog = false, shimgenWaitForExit = false, shimgenExit = false,
				shimgenGui = false, shimgenUseTargetWorkingDirectory = false, shimgenNoop = false;

			var commandPassthruArgs = commandWords.Count > 1 ? commandLine.Substring(commandWords[1].Index) : null;
			if (commandPassthruArgs != null)
			{
				var baseIndex = commandWords[1].Index;
				// walk in reverse so removing a span doesn't disturb the (still original-commandLine-relative)
				// indices of the spans not yet processed
				for (var i = commandWords.Count - 1; i >= 1; i--)
				{
					var isFlag = true;
					switch (commandWords[i].Value.ToLowerInvariant())
					{
						case "--shimgen-help": shimgenHelp = true; break;
						case "--shimgen-log": shimgenLog = true; break;
						case "--shimgen-waitforexit": shimgenWaitForExit = true; break;
						case "--shimgen-exit": shimgenExit = true; break;
						case "--shimgen-gui": shimgenGui = true; break;
						case "--shimgen-usetargetworkingdirectory": shimgenUseTargetWorkingDirectory = true; break;
						case "--shimgen-noop": shimgenNoop = true; break;
						default: isFlag = false; break;
					}
					if (isFlag)
					{
						commandPassthruArgs = commandPassthruArgs.Remove(commandWords[i].Index - baseIndex, commandWords[i].Length);
					}
				}
				commandPassthruArgs = commandPassthruArgs.Trim();
				if (commandPassthruArgs.Length == 0) commandPassthruArgs = null;
			}

			if (shimgenHelp)
			{
				Console.WriteLine("Shim Arguments:");
				Console.WriteLine("  --shimgen-help                        show this help and exit without running the target");
				Console.WriteLine("  --shimgen-log                         show shim diagnostic logging on the command line");
				Console.WriteLine("  --shimgen-waitforexit                 explicitly wait for the target to exit");
				Console.WriteLine("  --shimgen-exit                        explicitly exit immediately, without waiting for the target");
				Console.WriteLine("  --shimgen-gui                         treat the target as a GUI app (exit immediately, unless overridden by --shimgen-waitforexit)");
				Console.WriteLine("  --shimgen-usetargetworkingdirectory   run the target with its own directory as the working directory");
				Console.WriteLine("  --shimgen-noop                        show what would be run, without actually running the target");
				return 0;
			}

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
				if (shimTargetIsMe)
				{
					Environment.SetEnvironmentVariable("SHIM_ARG0", !(string.IsNullOrEmpty(envShimARG0)) ? envShimARG0 : null);
				}
				else
				{
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

			// `--shimgen-usetargetworkingdirectory`: run with the target's own directory as the working directory
			var targetWorkingDirectory = shimgenUseTargetWorkingDirectory ? Path.GetDirectoryName(pathOfTarget) : null;

			// default: behave as a command-line program (wait for the target to exit);
			// `--shimgen-gui`/`--shimgen-exit` request an immediate return; `--shimgen-waitforexit` always wins
			var waitForExit = true;
			if (shimgenGui) waitForExit = false;
			if (shimgenExit) waitForExit = false;
			if (shimgenWaitForExit) waitForExit = true;

			if (shimgenLog || shimgenNoop)
			{
				Console.WriteLine("shim: target command    : " + cmd);
				Console.WriteLine("shim: working directory  : " + (targetWorkingDirectory ?? "(inherited)"));
				Console.WriteLine("shim: wait for exit      : " + waitForExit);
			}

			if (shimgenNoop)
			{
				return 0;
			}

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
					lpCurrentDirectory: targetWorkingDirectory, // null => inherit parent; o/w target's own directory
					lpStartupInfo: ref si,
					lpProcessInformation: out pi))
			{
				exit_code = (uint)Marshal.GetLastWin32Error();
			}
			else
			{
				if (waitForExit)
				{
					WaitForSingleObject(pi.hProcess, INFINITE);
					GetExitCodeProcess(pi.hProcess, out exit_code);
				}

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

		static Dictionary<string, string> ParseConfig(string text)
		{
			var config = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
			using (var reader = new StringReader(text))
			{
				string line;
				while ((line = reader.ReadLine()) != null)
				{
					var m = Regex.Match(line, @"([^=]+)=(.*)");
					if (m.Success)
					{
						config[m.Groups[1].Value.Trim()] = m.Groups[2].Value.Trim();
					}
				}
			}
			return config;
		}

		// reads the SHIM_CONFIG resource embedded in this executable (by `shimgen --embed`); returns null if absent
		static string GetEmbeddedConfigText()
		{
			var hModule = GetModuleHandle(null);
			var hResInfo = FindResource(hModule, ShimConfigResourceName, RT_RCDATA_PTR);
			if (hResInfo == IntPtr.Zero) return null;
			var size = SizeofResource(hModule, hResInfo);
			var hResData = LoadResource(hModule, hResInfo);
			if (hResData == IntPtr.Zero || size == 0) return null;
			var pData = LockResource(hResData);
			if (pData == IntPtr.Zero) return null;
			var bytes = new byte[size];
			Marshal.Copy(pData, bytes, 0, (int)size);
			return Encoding.UTF8.GetString(bytes);
		}
	}
}
