$myDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

$source = "shim.cs"
$target = "shim.exe"

push-location $myDirectory
$fwdir = get-childitem C:\Windows\Microsoft.NET\Framework\ -dir | sort-object -desc | select-object -first 1
& "$($fwdir.fullname)\csc.exe" /nologo /out:"$target" "$source"
pop-location

$sourcePath = Convert-Path "$myDirectory\$source"
$targetPath = Convert-Path "$myDirectory\$target"

# replace the PE TimeDateStamp with the hash of the source file (for reproducibility)
# ref: <https://learn.microsoft.com/en-us/windows/win32/debug/pe-format> @@ <https://archive.is/T7uwq>
# ref: <https://devblogs.microsoft.com/oldnewthing/20180103-00/?p=97705> @@ <https://archive.is/Yeusm>
# research: <https://chentiangemalc.wordpress.com/2021/02/24/parsing-pe-files-in-powershell> @@ <https://archive.is/bX7ZR>
# research: <https://stackoverflow.com/questions/5795270/keep-exe-timestamp-from-changing> @@ <https://archive.is/yYBeH>
# research: [Past performance...](https://ericlippert.com/2012/05/31/past-performance-is-no-guarantee-of-future-results) @@ <https://archive.is/T7UUR>
# research: [Deterministic builds in C#](https://gist.github.com/aelij/b20271f4bd0ab1298e49068b388b54ae)
# research: [Deterministic builds in Roslyn](https://blog.paranoidcoding.org/2016/04/05/deterministic-builds-in-roslyn.html) @@ <https://archive.is/cxy6N>
# research: <https://superuser.com/questions/639351/does-compiling-a-program-twice-produce-a-bit-for-bit-identical-binary>
# research: <https://github.com/dotnet/roslyn/blob/5c54ff70dbadc082a9470f380a0e0a8ff88f65e7/docs/compilers/Deterministic%20Inputs.md>
# research: <https://0xrick.github.io/win-internals/pe1> @@ <https://archive.is/E3qqD>
# research: <https://0xrick.github.io/win-internals/pe2> @@ <https://archive.is/w07oS>
# research: <https://0xrick.github.io/win-internals/pe2> @@ <https://archive.is/E3Gp4>
# research/tools: <https://github.com/Velocidex/go-pe> , <https://github.com/horsicq/XPEViewer>

# Create the source hash
$sourceBytes = [IO.File]::ReadAllBytes($sourcePath)
# * use SHA256; *very high* collision resistance
$hasher = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
$hash = $hasher.ComputeHash($sourceBytes)
# * fold the SHA256 (256-bit) hash into a 32-bit hash using bitwise XOR; required for replacement of the COFF TimeDateStamp field
$hash32bit = 0
for ($i = 0; $i -lt $hash.Length; $i += 4) {
    $hash32bit = $hash32bit -bxor [BitConverter]::ToInt32($hash, $i)
}
$hashBytes = [BitConverter]::GetBytes($hash32bit)
## 'Folded (bit-XOR) 32-bit SHA256 hash: {0:X8}' -f $hash32bit
## 'Hash bytes: {0}' -f ($hashBytes -join ', ')

# Read the target, verify the header, and replace the COFF TimeDateStamp field with the source hash
$targetBytes = [IO.File]::ReadAllBytes($targetPath)
#
# * verify the DOS header stub signature ([0x5A,0x4D], "MZ"; from "Mark Zbikowski", one of the original architects of MS-DOS)
$offsetToDOSBrand = 0x0;
$DOSBrand = [Text.Encoding]::ASCII.GetBytes("MZ")
$headerByteSlice = $targetBytes[$offsetToDOSBrand..($offsetToDOSBrand + $DOSBrand.Length - 1)]
# '$DOSBrand: [ {0} ]' -f ($DOSBrand -join ', ')
# '$headerByteSlice: [ {0} ]' -f ($headerByteSlice -join ', ')
if ($(Compare-Object $headerByteSlice $DOSBrand).count -ne 0) {
    "Not a valid PE file (missing DOS header stub signature)."
}
# * verify the PE header signature ([0x50,0x45,0x0,0x0], "PE\0\0"; "Portable Executable")
$offsetToPEHeaderOffset = 0x3c;
$offsetToPEBrand = [BitConverter]::ToInt32($targetBytes, $offsetToPEHeaderOffset)
$PEBrand = [Text.Encoding]::ASCII.GetBytes("PE`0`0")
$headerByteSlice = $targetBytes[$offsetToPEBrand..($offsetToPEBrand + $PEBrand.Length - 1)]
# '$PEBrand: [ {0} ]' -f ($PEBrand -join ', ')
# '$headerByteSlice: [ {0} ]' -f ($headerByteSlice -join ', ')
if ($(Compare-Object $headerByteSlice $PEBrand).count -ne 0) {
    throw "Not a valid PE file (missing DOS header stub signature)."
}
#
$offsetToCOFF = $offsetToPEbrand + 4
$offsetToTimeDateStamp = $offsetToCOFF + 4
# * set the TimeDateStamp to the hash of the source file
[Array]::Copy($hashBytes, 0, $targetBytes, $offsetToTimeDateStamp, $hashBytes.Length)

# Write the modified bytes back to the target
[IO.File]::WriteAllBytes($targetPath, $targetBytes)
