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

namespace shimgen
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

		const string TemplateResourceName = "shim.exe"; // must match the `csc /resource:` identifier in build.ps1

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

			byte[] templateBytes;
			if (template != null)
			{
				if (!File.Exists(template))
				{
					Console.Error.WriteLine("Couldn't find shim template at " + template);
					return 1;
				}
				templateBytes = File.ReadAllBytes(template);
			}
			else
			{
				// normally embedded directly in this exe (via `csc /resource:shim.exe`), so no external
				// shim.exe file is needed; fall back to a sibling shim.exe for dev-time flexibility
				templateBytes = GetEmbeddedTemplateBytes();
				if (templateBytes == null)
				{
					var selfDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
					var siblingTemplate = Path.Combine(selfDir, "shim.exe");
					if (!File.Exists(siblingTemplate))
					{
						Console.Error.WriteLine("Couldn't find an embedded or sibling shim.exe template");
						return 1;
					}
					templateBytes = File.ReadAllBytes(siblingTemplate);
				}
			}

			// write/overwrite the template shim exe to the output path (also covers "modify": re-running
			// shimgen against an existing --output replaces its binary and rewrites/re-embeds its config)
			File.WriteAllBytes(output, templateBytes);

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

		// reads the `shim.exe` template bytes embedded in this executable's own managed resources
		// (via `csc /resource:shim.exe`, see build.ps1); returns null if not embedded
		static byte[] GetEmbeddedTemplateBytes()
		{
			var asm = Assembly.GetExecutingAssembly();
			using (var stream = asm.GetManifestResourceStream(TemplateResourceName))
			{
				if (stream == null) return null;
				var bytes = new byte[stream.Length];
				var offset = 0;
				while (offset < bytes.Length)
				{
					var read = stream.Read(bytes, offset, bytes.Length - offset);
					if (read <= 0) break;
					offset += read;
				}
				return bytes;
			}
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
