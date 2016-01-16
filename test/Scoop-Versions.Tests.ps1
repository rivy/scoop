write-host -f darkyellow "[$(split-path -leaf $MyInvocation.MyCommand.Path)]"

. "$($MyInvocation.MyCommand.Path | Split-Path)\lib\Scoop-TestLib.ps1"
. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\lib\versions.ps1"

describe "versions" {
    it 'compares versions with integer-string mismatch' {
        $a = '1.8.9'
        $b = '1.8.5-1'
        $res = compare_versions $a $b

        $res | should be 1
    }

    it 'handles plain string version comparison to int version' {
        $a = 'latest'
        $b = '20150405'
        $res = compare_versions $a $b

        $res | should be 1
    }
}
