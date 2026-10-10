# spell-checker:words childitem shimgen

$frameworkDir = get-childitem C:\Windows\Microsoft.NET\Framework\ -dir | sort-object -desc | select-object -first 1

push-location $($MyInvocation.MyCommand.Path | Split-Path)
& "$($frameworkDir.fullname)\csc.exe" /noLogo shim.cs
# shim.exe is embedded in shimgen.exe as a resource (named "shim.exe"), so shimgen can construct
# shims without needing an external shim.exe template; build shim.exe first (above) so it's current
& "$($frameworkDir.fullname)\csc.exe" /noLogo /resource:shim.exe shimgen.cs
pop-location
