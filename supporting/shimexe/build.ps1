$fwdir = get-childitem C:\Windows\Microsoft.NET\Framework\ -dir | sort-object -desc | select-object -first 1

push-location $($MyInvocation.MyCommand.Path | Split-Path)

$source = "shim.cs"
$target = "shim.exe"

& "$($fwdir.fullname)\csc.exe" /nologo /out:"$target" "$source"

# replace the PE TimeDateStamp with the hash of the source file (for reproducibility)
# ref: <https://learn.microsoft.com/en-us/windows/win32/debug/pe-format> @@ <https://archive.is/T7uwq>
# ref: <https://devblogs.microsoft.com/oldnewthing/20180103-00/?p=97705> @@ <https://archive.is/Yeusm>
# research: <https://chentiangemalc.wordpress.com/2021/02/24/parsing-pe-files-in-powershell> @@ <https://archive.is/bX7ZR>
# research: <https://stackoverflow.com/questions/5795270/keep-exe-timestamp-from-changing> @@ <https://archive.is/yYBeH>
# research/tools: <https://github.com/Velocidex/go-pe> , <https://github.com/horsicq/XPEViewer>

# Create a SHA256CryptoServiceProvider object
$sha256 = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider

# Get the contents of the source file
$sourceBytes = [System.IO.File]::ReadAllBytes($source)

# Calculate the hash of the content
$hash = $sha256.ComputeHash($sourceBytes)

# Since SHA256 produces a 256-bit hash, we need to fold it to get a 32-bit hash
$hash32 = 0
for ($i = 0; $i -lt $hash.Length; $i += 4) {
    $hash32 = $hash32 -bxor [BitConverter]::ToInt32($hash, $i)
}
# Print the 32-bit hash
# 'Folded (bit-XOR) 32-bit SHA256 hash: {0:X8}' -f $hash32
$hashBytes = [BitConverter]::GetBytes($hash32)
# 'Hash bytes: {0}' -f ($hashBytes -join ', ')

# Read all bytes from the file
$targetBytes = [System.IO.File]::ReadAllBytes($target)

# Check the DOS header stub signature
if ($targetBytes[0] -ne 0x4D -or $targetBytes[1] -ne 0x5A) {
    throw "Not a valid PE file (missing DOS header)."
}

# Get the offset to the PE signature
$offsetToPE = [BitConverter]::ToInt32($targetBytes, 0x3C)
# Check the PE signature ("PE\0\0")
if ($targetBytes[$offsetToPE] -ne 0x50 -or $targetBytes[$offsetToPE + 1] -ne 0x45 -or $targetBytes[$offsetToPE + 2] -ne 0x0 -or $targetBytes[$offsetToPE + 3] -ne 0x0) {
    throw "Not a valid PE file (missing PE signature)."
}

# Get the offset to the TimeDateStamp field
$offsetToCOFF = $offsetToPE + 4
$timeDateStampOffset = $offsetToCOFF + 4

# Set the TimeDateStamp to the hash of the source file
[System.Array]::Copy($hashBytes, 0, $targetBytes, $timeDateStampOffset, $hashBytes.Length)

# Write the modified bytes back to the target
[System.IO.File]::WriteAllBytes($target, $targetBytes)

pop-location
