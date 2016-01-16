function usage($text) {
    $text | select-string '(?m)^# Usage: ([^\n]*)$' | foreach-object { "usage: " + $_.matches[0].groups[1].value }
}

function summary($text) {
    $text | select-string '(?m)^# Summary: ([^\n]*)$' | foreach-object { $_.matches[0].groups[1].value }
}

function help($text) {
    $help_lines = $text | select-string '(?ms)^# Help:(.(?!^[^#]))*' | foreach-object { $_.matches[0].value; }
    $help_lines -replace '(?ms)^#\s?(Help: )?', ''
}

function my_usage { # gets usage for the calling script
    usage ([System.IO.File]::ReadAllText($(resolve-path $myInvocation.PSCommandPath)))
}
