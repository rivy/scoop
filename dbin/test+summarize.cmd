@powershell -c "invoke-pester -show none -script %~dp0\..\test -excludetag disabled -outputfile '%~dp0\..\test\#TestResults.xml' -outputformat NUnitXML"
@powershell -c "%~dp0\..\test\bin\summarize-results.ps1 '%~dp0\..\test\#TestResults.xml'"
