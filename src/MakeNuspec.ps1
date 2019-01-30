############################################################################
###                                                                      ###
###                    CREATE OR UPDATE .nusepc                          ###
###                                                     By Yang Chao     ###
############################################################################

param (
    [string]$nuget = "e:\tools\nuget.exe",
    [string]$authors = "Eson",
    [string]$owners = "Eson",
    [string]$licenseUrl = "http://share.yx.com/license.html",
    [string]$projectUrl = "http://tfs:8080/",
    [string]$iconUrl = "http://share.yx.com/nuget.png",
    [string]$copyright = "Copyright @ 2019",
    [string]$requireLicenseAcceptance = "false",
    [string]$ignore = "Test",
    [bool]$ignoreError = $false,
    [string]$slnRoot = "D:\201807_Core\Core\Lib\Lib.Base",
    [string]$pushSource = "http://tfs:8088/nuget",
    [string]$apiKey = "yx1234",
    [string]$ignoreLowerVersion = $true
)

if ($apiKey -eq "")
{
    "@@ No NuGet server api key provided - so not pushing anything up."
    exit 1
}

# 忽略项
$splitChars = ",", " "
$allIgnores = $ignore.Split($splitChars, [StringSplitOptions]::RemoveEmptyEntries)
$ignoreList = $allIgnores | where { -not $_.StartsWith("!") }
$notIgnoreList = $allIgnores | where { $_.StartsWith("!") }

function MatchIgnore($csproj)
{
    foreach($i in $notIgnoreList)
    {
        $notIgnore = $i.SubString(1)
        if(($csproj -match $notIgnore) -or ($csproj -like $notIgnore))
        {
            return $false
        }
    }

    foreach($i in $ignoreList)
    {
        if(($csproj -match $i) -or ($csproj -like $i))
        {
            return $true
        }
    }
    return $false
}

function FindNuget()
{
    if ($nuget -eq "")
    {
        $nuget = Join-Path $slnRoot "nuget.exe"
    }

    if(!(Test-Path $nuget))
    {
        throw "$nuget 不存在"
    }
}

function CreateNuspec($projectPath)
{
    Write-Host "开始调用nuget spec -Force -NonInteractive"
    Start-Process -FilePath $nuget -WorkingDirectory $projectPath -ArgumentList @("spec -Force -NonInteractive") -NoNewWindow -Wait
}

function Get-ObjectMembers {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        [PSCustomObject]$obj
    )
    $obj | Get-Member -MemberType NoteProperty | ForEach-Object {
        $key = $_.Name
        [PSCustomObject]@{Key = $key; Value = $obj."$key"}
    }
}

function GetDependencies($projectPath) 
{
    $assets = [System.IO.Path]::Combine($projectPath,"obj","project.assets.json")
    if(!(Test-Path $assets))
    {
        Write-Host "$assets 不存在，忽略"
        return
    }
    $assetsJObject = Get-Content -Raw -Path $assets | ConvertFrom-Json
    
    [hashtable]$depends = @{}

    $assetsJObject.projectFileDependencyGroups | Get-ObjectMembers | foreach {
        $frameMatch = [Regex]::Match($_.Key, '(?<frame>.*),Version=(?<version>.*)')
        if([Regex]::IsMatch($_.Key, '.*,Version=v.*'))
        {
            $framework = $_.Key.Replace(',Version=v', '')
            [hashtable]$packages = @{}

            foreach($p in $_.Value)
            {
                $packageMatch = [Regex]::Match($p, '(?<name>.+) >= (((?<min>.+) <= (?<max>.+))|(?<min1>.+))');
                if($packageMatch.Success)
                {
                    $name = $packageMatch.Groups['name'].Value
                    if($packageMatch.Groups['min'].Success)
                    {
                        $packages[$name] = '[' + $packageMatch.Groups['min'].Value + ',' + $packageMatch.Groups['max'].Value + ']'
                    }
                    else
                    {
                        $packages[$name] = $packageMatch.Groups['min1'].Value
                    }
                }
            }
            
            $depends[$framework] = $packages
        }
    }    

    return $depends
}

function GetVersion($projectName, $projectPath)
{
    # 先找AssemblyInfo.cs
    $assemblyInfo = [System.IO.Path]::Combine($projectPath, "Properties", "AssemblyInfo.cs")
    if(Test-Path $assemblyInfo)
    {
        foreach($line in (Get-Content $assemblyInfo))
        {
            if($line.StartsWith("[assembly: AssemblyVersion("))
            {
                $version = $line.Substring(28, $line.Length - 31)
                return $version
            }
        }
    }
    else 
    {
        # 再找 .csproj
        $csproj = [System.IO.Path]::Combine($projectPath, $projectName + ".csproj")

        foreach($line in (Get-Content $csproj | where { $_ -match "<Version>.*</Version>" }))
        {
            $line = $line.Trim()
            $version = $line.Trim().Substring(9, $line.Length - 19)
            return $version
        }
    }
    return "1.0.0"
}

function TryMake($projectName, $projectPath)
{
    $nuspecFile = [System.IO.Path]::Combine($projectPath, $projectName+ ".nuspec");
    $newVersion = GetVersion $projectName $projectPath

    if(!(ValidateVersion $projectName $newVersion))
    {
        Write-Host "当前版本不高于服务器版本，放弃"
        if(Test-Path $nuspecFile)
        {
            Write-Host "删除 $nuspecFile"
            Remove-Item $nuspecFile
        }
        return $false
    }

    $newNuspec = $false

    if(!(Test-Path $nuspecFile -PathType Leaf))
    {
        Write-Host "$nuspecFile 不存在，开始生成"
        CreateNuspec $projectPath
        $newNuspec = $true
    }

    $document = [xml](Get-Content $nuspecFile -Encoding UTF8)
    $metadata = $document.SelectSingleNode("/*[name()='package']/*[name()='metadata']")
    if($newNuspec) 
    {
         Write-Host "开始使用全局配置更新：$nuspecFile"
         $metadata.authors = $authors
         $metadata.owners = $owners
         $metadata.licenseUrl = $licenseUrl
         $metadata.projectUrl = $projectUrl
         $metadata.iconUrl = $iconUrl
         $metadata.copyright = $copyright
         $metadata.requireLicenseAcceptance = $requireLicenseAcceptance         
    }
   
    Write-Host "开始更新版本：$newVersion"
    $metadata.id = $projectName
    if(-NOT $metadata.title)
    {
         $title = $document.CreateElement("title")
         $title.InnerText = $projectName
         $metadata.AppendChild($title) > $null
    }
    elseif($metadata.title.InnerText)
    {
        $metadata.title.InnerText = $projectName
    }
    else
    {
        $metadata.title = $projectName
    }
    $metadata.version = $newVersion
    if($metadata.description -eq "`$description`$")
    {
        $metadata.description = $projectName
    }
    if(($metadata.releaseNotes -eq "Summary of changes made in this release of the package.") -or ($metadata.releaseNotes -eq "`$description`$"))
    {
        $metadata.releaseNotes = $projectName
    }
    if($metadata.tags -eq "Tag1 Tag2")
    {
        $metadata.RemoveChild($metadata.SelectSingleNode("*[name()='tags']"))
    }
    
    Write-Host "开始更新依赖包"
    $dependencies = $metadata.SelectSingleNode("*[name()='dependencies']")
    $pkgList = GetDependencies $projectPath
    if($pkgList.Count -eq 0 )
    {
        Write-Host "没有第三方依赖包"
        if($dependencies)
        {
            $metadata.RemoveChild($dependencies)
        }
        $document.Save($nuspecFile)
        return $true
    }
    if(-NOT $dependencies)
    {
        $metadata.AppendChild($document.CreateElement("dependencies")) > $null
        $dependencies = $metadata.SelectSingleNode("*[name()='dependencies']")
    }
    else
    {
        $dependencies.RemoveAll()
    }

    foreach($net in $pkgList.Keys)
    {
        $group = $document.CreateElement("group")
        $frame = $net
        $group.SetAttribute("targetFramework", $frame); # .NETStandard2.0
        foreach($pkg in $pkgList[$net].Keys)
        {
            Write-Host "添加 $pkg"
            $dependency = $document.CreateElement("dependency")
            $dependency.SetAttribute("id", $pkg)
            $dependency.SetAttribute("version", $pkgList[$net][$pkg])
            $dependency.SetAttribute("exclude", "Build,Analyzers")
            $group.AppendChild($dependency) > $null
        }
        $dependencies.AppendChild($group) > $null
    }     
    
    $document.Save($nuspecFile)
    return $true
}

function MapFramework($net)
{
    switch($net)
    {        
        "netstandard1.0" { ".NETStandard1.0" }
        "netstandard1.1" { ".NETStandard1.1" }
        "netstandard1.2" { ".NETStandard1.2" }
        "netstandard1.3" { ".NETStandard1.3" }
        "netstandard1.4" { ".NETStandard1.4" }
        "netstandard1.5" { ".NETStandard1.5" }
        "netstandard1.6" { ".NETStandard1.6" }
        "netstandard2.0" { ".NETStandard2.0" }
        "netcoreapp1.0"  { ".NETCoreApp1.0" }
        "netcoreapp1.1"  { ".NETCoreApp1.1" }
        "netcoreapp2.0"  { ".NETCoreApp2.0" }
        "netcoreapp2.1"  { ".NETCoreApp2.1" }
        "netcoreapp2.2"  { ".NETCoreApp2.2" }
        "netcoreapp3.0"  { ".NETCoreApp3.0" }
        "net45"          { ".NETFramework4.5" }
        "net451"         { ".NETFramework4.5.1" }
        "net452"         { ".NETFramework4.5.2" }
        "net46"          { ".NETFramework4.6" }
        "net461"         { ".NETFramework4.6.1" }
        "net462"         { ".NETFramework4.6.2" }
        "net471"         { ".NETFramework4.7.1" }
        "net472"         { ".NETFramework4.7.2" }
    }

    return $net
}

function GetAllProjects()
{
    if(!(Test-Path $slnRoot))
    {
        throw "$slnRoot 不存在"
    }
}

# 检查包是否需要上传：版本未更新则不上传
function ValidateVersion($nupkgName, $nupkgVersion)
{	
	Write-Host  "Current package is $nupkgName with version $nupkgVersion"
	$serverReply = &$nuget list -Source $pushSource $nupkgName
	Write-Host "Server replies:  $serverReply"
	if ($serverReply.StartsWith($nupkgName+' '))
	{
		$serverVersion = $serverReply.Split(' ')[1];
		Write-Host "Server version is $serverVersion"
		$c = CompareVersion -a $nupkgVersion -b $serverVersion 
		if ($c -eq 1)
		{
			return $true
		}
		return $false
	}		
	return $true
}

function CompareVersion($a, $b)
{
	$va = $a.Split('.')
	$vb = $b.Split('.')
	$length = $va.Length
	if ($vb.Length -gt $length)
	{
		$length = $b.Length
	}
	for ($i=0; $i -lt $length; $i++)
	{
		if ($i -ge $va.Length -and $i -lt $vb.Length)
		{
			# a < b
			return -1 
		}
		
		if ($i -ge $vb.Length -and $i -lt $va.Length)
		{
			# a > b
			return 1
		}
		$ai = [int]$va[$i]
		$bi = [int]$vb[$i]
		if ($ai -lt $bi)
		{
			return -1
		}
		
		if ($ai -gt $bi)
		{
			return 1
		}
    }
	# a = b
	return 0
}

function Pack($projectName, $projectPath)
{
    Write-Host "开始打包：$projectName"    
    $csproj =  [System.IO.Path]::Combine($projectPath, $projectName+ ".csproj");
    $output = &$nuget pack $csproj -Properties Configuration=Release -OutputDirectory $projectPath -ForceEnglishOutput -NonInteractive
    
    $pkg = ""
    foreach($line in $output)
    {
        Write-Host $line

        # Successfully created package 'D:\201807_Core\Core\Lib\Lib.Log\Lib.Log.1.1.0.nupkg'.
        if($line.Contains("Successfully created package"))
        {
            $pkg = $line.Substring(30, $line.Length - 32); 
        }
    }
    
    return $pkg;
}

function Push($nupkg)
{
    &$nuget push $nupkg -Source $pushSource -apiKey $apiKey 
}

function Run()
{
    FindNuget

    if(!(Test-Path $slnRoot))
    {
        throw "$slnRoot 不存在"
    }

    $projects = Get-ChildItem -Path $slnRoot -Include *.csproj -Recurse
    if(-not $projects)
    {
        Write-Host "$slnRoot 目录下没有找到项目文件(*.csproj)"
        return
    }

    if($projects -is [array])
    {
        $count = $projects.Length
    }
    else
    {
        $count = 1
    }

    $i = 1
    foreach($_ in $projects)
    {   
        Write-Host "$i/$count : 开始更新项目$_"
        $projectName = [System.IO.Path]::GetFileNameWithoutExtension($_)
        $projectPath = $_.DirectoryName
        
        if((MatchIgnore $_.FullName)) 
        {
            Write-Host "$_ 满足排除条件，跳过"
        }
        elseif(!(Test-Path ([IO.Path]::Combine($projectPath,"obj","project.assets.json"))))
        {
             Write-Host "project.assets.json 不存在，未生成项目，跳过"
        }
        elseif(TryMake $projectName $projectPath)
        {            
            $nupkg = Pack $projectName $projectPath 
            if($nupkg -ne "")         
            {
                Push $nupkg
            }
        }
        $i++
        Write-Host
    }
    
    Write-Host "更新完成"
}

Run