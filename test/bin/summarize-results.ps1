param(
    [parameter(mandatory=$false)][string] $testresults_xml = $null ,
    [parameter(mandatory=$false)][switch] $detailed = $false ,
    [parameter(ValueFromRemainingArguments=$true)][array] $args = @()
    )

set-strictmode -version latest

if (($null -eq $testresults_xml) -or ($testresults_xml.length  -eq 0)) { throw 'test results XML file required' }
if (-not (resolve-path $testresults_xml)) { throw "'$testresults_xml' not found" }

$indent_size = 3

# ref: [PowerShell XML Basics](ref: http://www.powershellmagazine.com/2013/08/19/mastering-everyday-xml-tasks-in-powershell)[`@`](https://archive.is/GfhiG)
# NOTE: as XML gets larger it may be a noticeable improvement to use `$xml = new-object -typename XML; $xml.Load( ... )`
$results = [xml](get-content (resolve-path $testresults_xml))

function format-time( [decimal]$t ) {
    $unit = 's'
    if ( $t -lt 1 ) {
        $t = $t * 1000
        $unit = 'ms'
    }
    "{0:f1} {1}" -f $t, $unit
}

write-host "Test Summary"
$test_suites = $(Select-Xml -xml $results -xpath "//test-suite[results/test-case]").Node
foreach ($s in $test_suites) {
    $c = 'red'
    $p = '[!] '
    if ($s.success -eq 'true') {
        $c = 'green'
        $p = '[+] '
    }
    write-host -foreground $c $( "{0}{1}{2} ~ {3}" -f @($(' '*$indent_size*0), $p, $s.description, $(format-time $s.time)) )
    if ($detailed  -or ($s.success -ne 'true') -or ($s.result -eq 'ignored')) {
        foreach ($t in $s.results.'test-case') {
            $c = 'red'
            $p = '[!] '
            if ($t.success -eq 'true') {
                $c = 'green'
                $p = '[+] '
            }
            if ($t.result -eq 'ignored') {
                $c = 'yellow'
                $p = '[-] '
            }
            write-host -foreground $c $( "{0}{1}{2} ~ {3}" -f @($(' '*$indent_size*1), $p, $t.description, $(format-time $t.time)) )
            if ($t.success -ne 'true') {
                $lines = [regex]::Split($t.failure.message,'(?m)\r?\n?$')
                foreach ($line in $lines) {
                    $line = [regex]::Replace($line, '\r\n|\r|\n', '')
                    if ($line -match '^\s*$') { continue; }
                    write-host -foreground $c $( "{0}{1}" -f @($(' '*$indent_size*2), $line) )
                }
            }
        }
    }
}

$n_total = [int]$results.'test-results'.total
$n_failures = [int]$results.'test-results'.failures
$n_passed = $n_total - $n_failures
$n_skipped = [int]$results.'test-results'.ignored

write-host -nonewline $("Total tests: {0} " -f $n_total)
if ($n_passed -gt 0) { write-host -nonewline $("Passed: {0} " -f $n_passed) -foreground green }
if ($n_failures -gt 0) { write-host -nonewline $("Failed: {0} " -f $n_failures) -foreground red }
if ($n_skipped -gt 0) { write-host -nonewline $("(Skipped: {0}) " -f $n_skipped) -foreground yellow }
write-host $("~ {0} " -f $(format-time $results.'test-results'.'test-suite'.time))
