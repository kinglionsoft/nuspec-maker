﻿############################################################################
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
    [string]$ignore = "MigrationBackup",
    [bool]$ignoreError = $false,
    [string]$slnRoot = ""
)

$ignoreList = $ignore.Split(';');

function MatchIgnore($projectName, $projectPath)
{
    foreach($i in $ignoreList)
    {
        if ($i -eq $projectName )
        {
            return $true
        }

        if ($projectPath -match $i)
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
    $assetsJObject = Get-Content -Raw -Path $assets | ConvertFrom-Json
    
    [hashtable]$depends = @{}
    $assetsJObject.project.frameworks | Get-ObjectMembers | foreach {
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
            $version = $line.Substring(10, $line.Length - 20)
            return $version
        }
    }
    return "1.0.0"
}

function Make($projectName, $projectPath)
{
    $nuspecFile = [System.IO.Path]::Combine($projectPath, $projectName+ ".nuspec");
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
         $metadata.licenseUrl = $licenseUrl
         $metadata.projectUrl = $projectUrl
         $metadata.iconUrl = $iconUrl
         $metadata.copyright = $copyright
         $metadata.requireLicenseAcceptance = $requireLicenseAcceptance
         if($metadata.releaseNotes -eq "Summary of changes made in this release of the package.")
         {
            $metadata.releaseNotes = "`$description`$"
         }
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
        Write-Host "更新完成"
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