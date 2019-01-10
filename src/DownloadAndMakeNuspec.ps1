$nuget = Join-Path "$(Agent.ToolsDirectory)" "NuGet\4.9.1\x64\nuget.exe"
$authors = "四川译讯信息科技有限公司"
$owners = "四川译讯信息科技有限公司"
$licenseUrl = "http://share.yx.com/license.html"
$projectUrl = "http://tfs:8080/"
$iconUrl = "http://share.yx.com/nuget.png"
$copyright = "Copyright@2019,四川译讯信息科技有限公司"
$requireLicenseAcceptance = "false"
$ignore = "MigrationBackup"
$ignoreError = $false
$slnRoot = "$(Build.SourcesDirectory)"

Invoke-WebRequest -Uri http://share.yx.com/MakeNuspec.ps1 -OutFile MakeNuspec.ps1

$argumentList = "-nuget `"$nuget`"  -authors `"$authors`" -owners `"$owners`" -licenseUrl `"$licenseUrl`" -projectUrl `"$projectUrl`" -iconUrl `"$iconUrl`" -copyright `"$copyright`" -requireLicenseAcceptance `"$requireLicenseAcceptance `" -ignore `"$ignore `" -slnRoot `"$slnRoot`""
powershell .\MakeNuspec.ps1 $argumentList
