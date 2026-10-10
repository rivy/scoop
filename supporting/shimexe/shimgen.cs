// spell-checker:ignore (names) Roy Ivy III * rivy (types) RCDATA (vars) shimgen outpath

// NOTE: C#v5 code restricted (for no-dependency builds on Win10/Win11)

using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

[assembly: AssemblyTitle("shimgen")]
[assembly: AssemblyDescription("creates/modifies generic command shims (used by Scoop)")]
[assembly: AssemblyProduct("Scoop")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace shim
{
	// creates (or modifies, by re-running against the same --output) a shim executable;
	// by default, writes a sidecar `name.shim` config file (matching Scoop's current shim.exe behavior);
	// with --embed, instead writes the config directly into the shim exe's own SHIM_CONFIG resource
	class ShimGen
	{
		[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
		static extern IntPtr BeginUpdateResource(string pFileName, bool bDeleteExistingResources);

		[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
		static extern bool UpdateResource(IntPtr hUpdate, IntPtr lpType, string lpName, ushort wLanguage, byte[] lpData, uint cbData);

		[DllImport("kernel32.dll", SetLastError = true)]
		static extern bool EndUpdateResource(IntPtr hUpdate, bool fDiscard);

		const int RT_RCDATA = 10;
		const string ShimConfigResourceName = "SHIM_CONFIG"; // must match `shim.cs`'s embedded resource name
		const ushort LANG_NEUTRAL = 0;

		static int Main(string[] args)
		{
			string output = null, path = null, targetArgs = null, template = null;
			bool embed = false;

			for (var i = 0; i < args.Length; i++)
			{
				switch (args[i])
				{
					case "--output":
					case "-o":
						output = args[++i];
						break;
					case "--path":
					case "-p":
						path = args[++i];
						break;
					case "--args":
					case "-a":
						targetArgs = args[++i];
						break;
					case "--template":
						template = args[++i];
						break;
					case "--embed":
						embed = true;
						break;
					default:
						Console.Error.WriteLine("Unrecognized argument: " + args[i]);
						return 1;
				}
			}

			if (string.IsNullOrEmpty(output) || string.IsNullOrEmpty(path))
			{
				Console.Error.WriteLine("usage: shimgen --output <shim.exe> --path <target.exe> [--args \"<extra args>\"] [--embed] [--template <template-shim.exe>]");
				return 1;
			}

			if (template == null)
			{
				var selfDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
				template = Path.Combine(selfDir, "shim.exe");
			}
			if (!File.Exists(template))
			{
				Console.Error.WriteLine("Couldn't find shim template at " + template);
				return 1;
			}

			// copy/overwrite the template shim exe to the output path (also covers "modify": re-running
			// shimgen against an existing --output replaces its binary and rewrites/re-embeds its config)
			File.Copy(template, output, overwrite: true);

			var configText = "path = " + path + "\r\n";
			if (!string.IsNullOrEmpty(targetArgs))
			{
				configText += "args = " + targetArgs + "\r\n";
			}

			if (embed)
			{
				EmbedConfig(output, configText);
			}
			else
			{
				var sidecarPath = Path.Combine(
						Path.GetDirectoryName(output),
						Path.GetFileNameWithoutExtension(output) + ".shim");
				File.WriteAllText(sidecarPath, configText);
			}

			return 0;
		}

		static void EmbedConfig(string exePath, string configText)
		{
			var configBytes = Encoding.UTF8.GetBytes(configText);

			var hUpdate = BeginUpdateResource(exePath, false);
			if (hUpdate == IntPtr.Zero)
			{
				throw new InvalidOperationException("BeginUpdateResource failed (" + Marshal.GetLastWin32Error() + ")");
			}

			var ok = UpdateResource(hUpdate, (IntPtr)RT_RCDATA, ShimConfigResourceName, LANG_NEUTRAL, configBytes, (uint)configBytes.Length);
			if (!ok)
			{
				var err = Marshal.GetLastWin32Error();
				EndUpdateResource(hUpdate, /* discard => */ true);
				throw new InvalidOperationException("UpdateResource failed (" + err + ")");
			}

			if (!EndUpdateResource(hUpdate, /* discard => */ false))
			{
				throw new InvalidOperationException("EndUpdateResource failed (" + Marshal.GetLastWin32Error() + ")");
			}
		}
	}
}
