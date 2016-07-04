# Usage: scoop help <command>
# Summary: Show help for a command
param($cmd)

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\core.ps1"
. $(rootrelpath "lib\commands.ps1")
. $(rootrelpath "lib\help.ps1")

function print_help($cmd) {
    $file = [System.IO.File]::ReadAllText($(resolve-path (command_path $cmd)))

    $usage = usage $file
    $summary = summary $file
    $help = help $file

    if($usage) { "$usage`n" }
    if($help) { $help }
}

function print_summaries {
    $commands = @{}

    command_files | foreach-object {
        $command = command_name $_
        $summary = summary ([System.IO.File]::ReadAllText($(resolve-path (command_path $command))))
        if(!($summary)) { $summary = '' }
        $commands.add("$command ", $summary) # add padding
    }

    $commands.getenumerator() | sort-object name | format-table -hidetablehead -autosize -wrap
}

$commands = commands

if(!($cmd)) {
    "usage: scoop <command> [<args>]

Some useful commands are:"
    print_summaries
    "type 'scoop help <command>' to get help for a specific command"
} elseif($commands -contains $cmd) {
    print_help $cmd
} else {
    "scoop help: no such command '$cmd'"; exit 1
}

exit 0

