############################################################################
###                                                                      ###
###                    CREATE OR UPDATE .nusepc                          ###
###                                                     By Yang Chao     ###
############################################################################

param (
    [string]$nuget = "e:\tools\nuget.exe",
    [string]$authors = "四川译讯信息科技有限公司",
    [string]$owners = "四川译讯信息科技有限公司",
    [string]$licenseUrl = "http://share.yx.com/license.html",
    [string]$projectUrl = "http://tfs:8080/",
    [string]$iconUrl = "http://share.yx.com/nuget.png",
    [string]$copyright = "Copyright @ 2019",
    [string]$requireLicenseAcceptance = "false",
    [string]$ignore = "MigrationBackup,Test",
    [bool]$ignoreError = $false,
    [string]$slnRoot = "D:\201807_Lib\Lib\",
    [string]$pushSource = "http://tfs:8088/nuget",
    [string]$ignoreLowerVersion = $true
)

# 忽略项
$splitChars = ",", " "
$ignoreList = $ignore.Split($splitChars, [StringSplitOptions]::RemoveEmptyEntries)

function MatchIgnore($projectName, $projectPath)
{
    foreach($i in $ignoreList)
    {
        if ($i -eq $projectName )
        {
            return $true
        }
        if ([System.Text.RegularExpressions.Regex]::IsMatch($projectPath, ".*$i.*", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
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
    $assets = [IO.Path]::Combine($projectPath,"obj","project.assets.json")
    if(!(Test-Path $assets))
    {
        Write-Host "$assets 不存在，忽略"
        return
    }
    $assetsJObject = Get-Content -Raw -Path $assets | ConvertFrom-Json
    
    [hashtable]$depends = @{}
    $assetsJObject.project.frameworks | Get-ObjectMembers | foreach {
        if($_.Value.dependencies) 
        {
            $net = $_.Key
            [hashtable]$packages = @{}
            $_.Value.dependencies | foreach {
                $_ | Get-ObjectMembers | foreach {
                    $pkg = $_.Key
                    if($_.Value.target -eq "Package") {
                        $version = $_.Value.version.Substring(1, $_.Value.version.IndexOf(',') - 1)
                        $packages[$pkg]=$version
                    }
                }
            }
            $depends[$net] = $packages
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

function Make($projectName, $projectPath)
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
        return
    }

    $newNuspec = $false

    if(!(Test-Path $nuspecFile -PathType Leaf))
    {
        Write-Host "$nuspecFile 不存在，开始生成"
        CreateNuspec $projectPath
        $newNuspec = $true
    }

    $document = [xml](Get-Content $nuspecFile -Encoding UTF8)
    $metadata = $document.SelectSingleNode("/package/metadata")
    if($newNuspec) 
    {
         Write-Host "开始使用全局配置更新：$nuspecFile"
         $metadata.authors = $authors
         $metadata.owners = $owners
         $metadata.license = $licenseUrl
         $metadata.projectUrl = $projectUrl
         $metadata.iconUrl = $iconUrl
         $metadata.copyright = $copyright
         $metadata.requireLicenseAcceptance = $requireLicenseAcceptance
         
    }
   
    Write-Host "开始更新版本：$newVersion"
    $metadata.id = $projectName
    $metadata.title = $projectName
    $metadata.version = $newVersion
    if($metadata.description -eq "`$description`$")
    {
        $metadata.description = $projectName
    }
    if(($metadata.releaseNotes -eq "Summary of changes made in this release of the package.") -or ($metadata.releaseNotes -eq "`$description`$"))
    {
        $metadata.releaseNotes = $projectName
    }
    
    Write-Host "开始更新依赖包"
    $dependencies = $metadata.SelectSingleNode("dependencies")
    $pkgList = GetDependencies $projectPath
    if($pkgList.Count -eq 0 )
    {
        Write-Host "没有第三方依赖包"
        if($dependencies)
        {
            $metadata.RemoveChild($dependencies)
        }
        $document.Save($nuspecFile)
        return
    }
    if(-NOT $dependencies)
    {
        $metadata.AppendChild($document.CreateElement("dependencies")) > $null
        $dependencies = $metadata.SelectSingleNode("dependencies")
    }
    else
    {
        $dependencies.RemoveAll()
    }

    foreach($net in $pkgList.Keys)
    {
        $group = $document.CreateElement("group")
        $group.SetAttribute("targetFramework", $net); # .NETStandard2.0
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
	if ($serverReply.StartsWith($nupkgName))
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
        
        if((MatchIgnore $projectName $projectPath)) 
        {
            Write-Host "$_ 满足排除条件，跳过"
        }
        else
        {
            Make $projectName $projectPath
        }
        $i++
        Write-Host
    }
    
    Write-Host "更新完成"
}

Run