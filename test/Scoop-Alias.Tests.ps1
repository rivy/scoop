write-host -f darkyellow "[$(split-path -leaf $MyInvocation.MyCommand.Path)]"

. "$($MyInvocation.MyCommand.Path | Split-Path | Split-Path)\libexec\scoop-alias.ps1" | out-null

describe "add_alias" {
  mock shimdir { "TestDrive:\shim" }
  mock set_config { }
  mock get_config { @{} }

  $shimdir = shimdir
  mkdir $shimdir

  context "alias doesn't exist" {
    it "creates a new alias" {
      $alias_file = "$shimdir\scoop-rm.ps1"
      $alias_file | should not exist

      add_alias "rm" '"hello, world!"'
      & $alias_file | should be "hello, world!" ## aka: invoke-expression $alias_file | should be "hello, world!"
    }
  }

  context "alias exists" {
    it "does not change existing alias" {
      $alias_file = "$shimdir\scoop-rm.ps1"
      new-item $alias_file -type file
      $alias_file | should exist

      add_alias "rm" "test"
      $alias_file | should FileContentMatch ""
    }
  }
}

describe "rm_alias" {
  mock shimdir { "TestDrive:\shim" }
  mock set_config { }
  mock get_config { @{} }

  $shimdir = shimdir
  mkdir $shimdir

  context "alias exists" {
    it "removes an existing alias" {
      $alias_file = "$shimdir\scoop-rm.ps1"
      add_alias "rm" '"hello, world!"'

      $alias_file | should exist
      mock get_config { @(@{"rm" = "scoop-rm"}) }

      rm_alias "rm"
      $alias_file | should not exist
    }
  }
}
