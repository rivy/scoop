$fwdir = get-childitem C:\Windows\Microsoft.NET\Framework\ -dir | sort-object -desc | select-object -first 1

push-location $($MyInvocation.MyCommand.Path | Split-Path)
& "$($fwdir.fullname)\csc.exe" /nologo shim.cs
pop-location
