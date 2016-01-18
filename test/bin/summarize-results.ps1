param(
    [parameter(mandatory=$false)][string] $testresults_xml = $null ,
    [parameter(mandatory=$false)][switch] $detailed = $false ,
    [parameter(ValueFromRemainingArguments=$true)][array] $args = @()
    )

set-strictmode -version latest

if (($null -eq $testresults_xml) -or ($testresults_xml.length  -eq 0)) { throw 'test results XML file required' }
if (-not (resolve-path $testresults_xml)) { throw "'$testresults_xml' not found" }

$indent_size = 3

$tests = [xml](get-content (resolve-path $testresults_xml))

function format-time( [decimal]$t ) {
    $unit = 's'
    if ( $t -lt 1 ) {
        $t = $t * 1000
        $unit = 'ms'
    }
    "{0:f1} {1}" -f $t, $unit
}

write-host "Test Summary"
foreach ($t in $tests.'test-results'.'test-suite'.'results'.'test-suite') {
    $c = 'red'
    $p = '[!] '
    if ($t.success -eq 'true') {
        $c = 'green'
        $p = '[+] '
    }
    write-host -foreground $c $( "{0}{1}{2} ~ {3}" -f @($(' '*$indent_size*0), $p, $t.description, $(format-time $t.time)) )
    if ($detailed  -or ($t.success -ne 'true') -or ($t.result -eq 'ignored')) {
        foreach ($s in $t.results.'test-case') {
            $c = 'red'
            $p = '[!] '
            if ($s.success -eq 'true') {
                $c = 'green'
                $p = '[+] '
            }
            if ($s.result -eq 'ignored') {
                $c = 'yellow'
                $p = '[-] '
            }
            write-host -foreground $c $( "{0}{1}{2} ~ {3}" -f @($(' '*$indent_size*1), $p, $s.description, $(format-time $s.time)) )
            if ($s.success -ne 'true') {
                $lines = [regex]::Split($s.failure.message,'(?m)\r?\n?$')
                foreach ($line in $lines) {
                    $line = [regex]::Replace($line, '\r\n|\r|\n', '')
                    if ($line -match '^\s*$') { continue; }
                    write-host -foreground $c $( "{0}{1}" -f @($(' '*$indent_size*2), $line) )
                }
            }
        }
    }
}

$n_total = [int]$tests.'test-results'.total
$n_failures = [int]$tests.'test-results'.failures
$n_passed = $n_total - $n_failures
$n_skipped = [int]$tests.'test-results'.ignored

write-host -nonewline $("Total tests: {0} " -f $n_total)
if ($n_passed -gt 0) { write-host -nonewline $("Passed: {0} " -f $n_passed) -foreground green }
if ($n_failures -gt 0) { write-host -nonewline $("Failed: {0} " -f $n_failures) -foreground red }
if ($n_skipped -gt 0) { write-host -nonewline $("(Skipped: {0}) " -f $n_skipped) -foreground yellow }
write-host $("~ {0} " -f $(format-time $tests.'test-results'.'test-suite'.time))
