using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using Newtonsoft.Json;

namespace NuspecMaker
{
    public sealed class NuspecOption
    {
        /// <summary>
        /// nuget.exe 路径，若不配置，从解决方案根目录获取
        /// </summary>
        public string Nuget { get; set; } = string.Empty;

        /// <summary>
        /// 解决方案所有项目的全局配置
        /// </summary>
        public Dictionary<string, string> Global { get; set; } = new Dictionary<string, string>
        {
            {"authors", "作者"},
            {"owners", "所有者" },
            {"licenseUrl","http://www.xxx.com/license.html" },
            {"projectUrl", "http://www.xxx.com/" },
            {"iconUrl", "http://www.xxx.com/icon.ico" },
            {"requireLicenseAcceptance", "false" },
            {"copyright", "Copyright @ 2018" }
        };

        /// <summary>
        /// 排除的项目，可以是项目名称、或者匹配项目路径的正则表达式。不区分大小写
        /// </summary>
        public string[] Ignore { get; set; } =
        {
            @"[\\/]test[\\/]"
        };

        public bool MatchIgnore(string projectName, string projectPath)
        {
            return Ignore.Any(rule => 
                string.Compare(projectName, rule, StringComparison.InvariantCultureIgnoreCase) == 0 
                || Regex.IsMatch(projectPath, $".*{rule}.*", RegexOptions.IgnoreCase));
        }
    }
}