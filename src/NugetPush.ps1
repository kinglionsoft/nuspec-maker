############################################################################
###                                                                      ###
###                    CREATE OR UPDATE .nusepc                          ###
###                                                     By Yang Chao     ###
############################################################################
### 
### <PropertyGroup Condition="'$(PublishDocumentationFile)' == ''">
###     <GenerateDocumentationFile>true</GenerateDocumentationFile>
###     <PublishDocumentationFile Condition="'$(GenerateDocumentationFile)' == 'true'">true</PublishDocumentationFile>
### </PropertyGroup>
###  
### <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='Release|AnyCPU'">
###     <GeneratePackageOnBuild>true</GeneratePackageOnBuild>
### </PropertyGroup>

param (
    [string]$nuget = "e:\tools\nuget.exe",
    [string]$ignore = "Test,!LibStandard",
    [string]$pkgPath = "D:\test\NugetTest\LibStandard\",
    [string]$pushSource = "http://tfs:8088/nuget",
    [string]$apiKey = "yx1234"
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
        $nuget = Join-Path $pkgPath "nuget.exe"
    }

    if(!(Test-Path $nuget))
    {
        throw "$nuget 不存在"
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

function Push($nupkg)
{
    &$nuget push $nupkg -Source $pushSource -apiKey $apiKey 
}

function Run()
{
    FindNuget

    if(!(Test-Path $pkgPath))
    {
        throw "$pkgPath 不存在"
    }

    $projects = Get-ChildItem -Path $pkgPath -Include *.nupkg -Recurse | where { $_.FullName -notmatch 'packages'}
    if(-not $projects)
    {
        Write-Host "$pkgPath 目录下没有找到包文件(*.nupkg)"
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
        Write-Host "$i/$count : 开始发布包$_"
        $nupkg =  $_.FullName
        if((MatchIgnore $nupkg)) 
        {
            Write-Host "$_ 满足排除条件，跳过"
        }
        else
        {   
            $pkgFileName = [System.IO.Path]::GetFileNameWithoutExtension($nupkg)

            $pkgMatch = [Regex]::Match($pkgFileName, '\.\d')
            $pkgName = $pkgFileName.SubString(0, $pkgMatch.Index)
            $pkgVersion = $pkgFileName.SubString($pkgMatch.Index + $pkgMatch.Length - 1)       

            if(ValidateVersion $pkgName $pkgVersion)         
            {
                Push $nupkg
            }
            else
            {
                Write-Host "$pkgName 不高于服务器版本，跳过"
            }
        }
        $i++
        Write-Host
    }
    
    Write-Host "更新完成"
}

Run