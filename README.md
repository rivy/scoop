`scoop` [![Build status](https://ci.appveyor.com/api/projects/status/jgckhkhe5rdd6586/branch/master?svg=true)](https://ci.appveyor.com/project/rivy/scoop/branch/master)
=======

`scoop` is a command-line installer for Windows.

### Requirements

* Windows 7sp1+ (PowerShell 2+)
* PowerShell script execution policy must configured as either `unrestricted` or `bypass` for your user account

##### PowerShell Execution Policy

Please note that, for operation, `scoop` requires a liberal PowerShell execution policy (in the same manner as [`chocolatey`](https://chocolatey.org)). So, during installation, if the PowerShell execution policy for the current user is more restrictive than `unrestricted` (i.e., `restricted`, `allsigned`, or `remotesigned`), it will be changed to `unrestricted` and saved into the registry as the user's default policy.

###### NET framework recommendations

TL;DR: for Win7sp1, [install NET 4.0+](https://www.microsoft.com/en-us/download/details.aspx?id=48137).

Windows 7sp1 has NET framework versions 1.0, 1.1, 2.0, 3.0 and 3.5 included, but many current software builds require NET framework 4.0+. So, it is recommended that a recent NET 4.0+ framework be installed (eg, [NET 4.6](https://www.microsoft.com/en-us/download/details.aspx?id=48137)), either via [direct download](https://www.microsoft.com/en-us/download/details.aspx?id=48137) or through the Windows Update mechanism. Later Windows versions have the NET 4.0 included and require no extra efforts.

### Installation

To install, paste either of the following set of command strings at the respective shell prompt.

##### CMD Shell &middot; `C:\>`

    powershell -command "iex (new-object net.webclient).downloadstring( 'https://raw.github.com/rivy/scoop/master/bin/install.ps1' )"
    set PATH=%PATH%;%APPDATA%\scoop\shims

##### PowerShell &middot; `PS C:\>`

    iex (new-object net.webclient).downloadstring( 'https://raw.github.com/rivy/scoop/master/bin/install.ps1' )

Once installed, run `scoop help` for instructions.

What does `scoop` do?
-------------------

`scoop` installs programs from the command line with a minimal amount of friction. It tries to eliminate things like:
* Permission popup windows
* GUI wizard-style installers
* Path pollution from installing lots of programs
* Unexpected side-effects from installing and uninstalling programs
* The need to find and install dependencies
* The need to perform extra setup steps to get a working program

`scoop` is very scriptable, so you can run repeatable setups to get your environment just the way you like, e.g.:

```powershell
scoop install sudo
sudo scoop install 7zip git openssh --global
scoop install curl grep sed less tail touch
scoop install python ruby go perl
```

If you've built software that you'd like others to use, `scoop` is an alternative to building an installer (e.g. MSI or InnoSetup) &mdash; you just need to zip your program and provide a JSON manifest that describes how to install it.

### [Documentation](https://github.com/lukesampson/scoop/wiki)

Inspiration
-----------

* [Homebrew](http://mxcl.github.io/homebrew/)
* [sub](https://github.com/37signals/sub#readme)

What sort of apps can `scoop` install?
------------------------------------

The apps that install best with `scoop` are commonly called "portable" apps: i.e. compressed program files that run stand-alone when extracted and don't have side-effects like changing the registry or putting files outside the program directory.

Since installers are common, `scoop` supports them too (and their uninstallers).

`scoop` is also great at handling single-file programs and Powershell scripts. These don't even need to be compressed. See the [runat](https://github.com/lukesampson/scoop/blob/master/bucket/runat.json) package for an example: it's really just a GitHub gist.
