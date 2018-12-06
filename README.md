# .nuspec 生成器插件
VS 2017插件，为解决方案下的项目生成.nuspec文件。

## 安装
下载并安装 [NuspecMaker.vsix](dist/NuspecMaker.vsix).

## 使用

* 生成解决方案；
* 为需要nuget打包的项目配置包参数：.NETStandard项目都在.csproj中，.NFX项目在AssemblyInfo.cs项目中；
* 【工具】-> 【创建/更新 nuspec】；
* 首次运行时，会在解决方案根目录下创建配置文件【nuspec.config】，按需修改后，再次运行；

```js
{
  "Nuget": "e:\\tools\\nuget.exe", // nuget.exe 路径，若不配置，从解决方案根目录获取
  "Global": { // 解决方案所有项目的全局配置
    "authors": "作者",
    "owners": "所有者",
    "licenseUrl": "http://www.xxx.com/license.html",
    "projectUrl": "http://www.xxx.com/",
    "iconUrl": "http://www.xxx.com/icon.ico",
    "requireLicenseAcceptance": "false",
    "copyright": "Copyright @ 2018"
  },
  "Ignore": [ // 排除的项目，可以是项目名称、或者匹配项目路径的正则表达式。不区分大小写
    "[\\\\/]test[\\\\/]" // 忽略test目录下的项目
  ]
}

```
* nuget打包前，修改需要更新的项目的版本号。