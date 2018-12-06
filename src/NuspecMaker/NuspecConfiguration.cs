using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Xml;
using Formatting = Newtonsoft.Json.Formatting;

namespace NuspecMaker
{
    internal static class NuspecConfiguration
    {
        private static NuspecOption _nuspecOption;

        private const string ConfigFile = "nuspec.config";

        public static string SolutionRoot = string.Empty;

        private static string Nuget => string.IsNullOrEmpty(_nuspecOption.Nuget)
            ? Path.Combine(SolutionRoot, "nuget.exe")
            : _nuspecOption.Nuget;


        public static bool Load()
        {
            var configFilePath = Path.Combine(SolutionRoot, ConfigFile);
            if (File.Exists(configFilePath))
            {
                _nuspecOption = JsonConvert.DeserializeObject<NuspecOption>(File.ReadAllText(configFilePath));
            }
            else
            {
                // create default configuration file
                using (var writer = new StreamWriter(configFilePath, false, Encoding.UTF8))
                {
                    writer.WriteLine(JsonConvert.SerializeObject(new NuspecOption(), Formatting.Indented));
                }

                return false;
            }

            if (!File.Exists(Nuget))
            {
                throw new FileNotFoundException(Nuget);
            }

            return true;
        }

        private static void Spec(string projectPath)
        {
            var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    UseShellExecute = false,
                    FileName = Nuget,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    WorkingDirectory = projectPath,
                    Arguments = "spec -Force -NonInteractive"
                }
            };
            CommandOutput.WriteLine("开始调用nuget spec -Force -NonInteractive");
            process.Start();
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            if (process.ExitCode != 0)
            {
                throw new Exception($"nuget spec失败，项目：{projectPath}，结果：{output}");
            }
            CommandOutput.WriteLine("调用nuget spec完成");
        }

        /// <summary>
        /// 读取依赖
        /// </summary>
        /// <param name="projectPath"></param>
        /// <returns>{ "net471":{"NewtonSoft.Json" : "12.0.1"} }</returns>
        private static Dictionary<string, Dictionary<string, string>> GetDependencies(string projectPath)
        {
            // get dependencies from obj/project.assets.json
            var assets = Path.Combine(projectPath, "obj", "project.assets.json");
            if (!File.Exists(assets))
            {
                throw new FileNotFoundException(assets);
            }

            using (var reader = new StreamReader(assets))
            {
                var assetsJObject = JObject.Load(new JsonTextReader(reader));
                var frameworks = assetsJObject["project"]["frameworks"];
                var result = new Dictionary<string, Dictionary<string, string>>();
                foreach (var framework in frameworks.Children())
                {
                    foreach (var net in framework.Children())
                    {
                        var depends = new Dictionary<string, string>();
                        foreach (var pkg in net["dependencies"])
                        {
                            var pkgJProperty = pkg.ToObject<JProperty>();
                            var realPkg = pkg.First;
                            var target = realPkg["target"].Value<string>();
                            if (target == "Package")
                            {
                                // "version": "[12.0.1, )"
                                var version = realPkg["version"].Value<string>();
                                version = version.Substring(1, version.IndexOf(',') - 1);
                                depends.Add(pkgJProperty.Name, version);
                            }

                        }
                        var netJProperty = framework.ToObject<JProperty>();
                        result.Add(netJProperty.Name, depends);
                    }
                }

                return result;
            }
        }

        public static void Make(string projectName, string projectPath)
        {
            if (_nuspecOption.MatchIgnore(projectName, projectPath))
            {
                CommandOutput.WriteLine($"{projectName} 满足排除条件，跳过");
                return;
            }

            var nuspecFile = Path.Combine(projectPath, projectName + ".nuspec");
            var newNuspec = false;
            if (!File.Exists(nuspecFile))
            {
                CommandOutput.WriteLine($"{nuspecFile}不存在，开始生成");
                Spec(projectPath);
                newNuspec = true;
            }
            else
            {
                CommandOutput.WriteLine($"{nuspecFile}已经存在，开始更新依赖包");
            }

            var document = new XmlDocument();
            CommandOutput.WriteLine($"开始使用全局配置更新: {nuspecFile}");
            document.Load(nuspecFile);
            var metadata = document["package"]["metadata"];

            if (newNuspec)
            {
                CommandOutput.WriteLine("为新创建的nuspec文件，更新全局配置");
                var metadataNodes = document["package"]["metadata"].ChildNodes;
                foreach (XmlElement el in metadataNodes)
                {
                    if (_nuspecOption.Global.ContainsKey(el.LocalName))
                    {
                        el.InnerText = _nuspecOption.Global[el.LocalName];
                    }
                }
            }

            var dependList = metadata.GetElementsByTagName("dependencies");
            var pkgList = GetDependencies(projectPath);
            if (pkgList.Count == 0)
            {
                CommandOutput.WriteLine("没有第三方依赖包");
                if (dependList.Count != 0)
                {
                    metadata.RemoveChild(dependList[0]);
                }
            }
            else
            {
                XmlElement dependencies;
                if (dependList.Count == 0)
                {
                    dependencies = document.CreateElement("dependencies");
                }
                else
                {
                    dependencies = (XmlElement)dependList[0];
                    dependencies.RemoveAll();
                }

                foreach (var net in pkgList)
                {
                    var group = document.CreateElement("group");
                    group.SetAttribute("targetFramework", net.Key); // .NETStandard2.0

                    CommandOutput.WriteLine($"添加targetFramework：{net.Key}");
                    foreach (var nugetPkg in net.Value)
                    {
                        CommandOutput.WriteLine($"添加{nugetPkg.Key}到{net.Key}");
                        var dependency = document.CreateElement("dependency");
                        dependency.SetAttribute("id", nugetPkg.Key);
                        dependency.SetAttribute("version", nugetPkg.Value);
                        dependency.SetAttribute("exclude", "Build,Analyzers");
                        group.AppendChild(dependency);
                    }

                    dependencies.AppendChild(group);
                }

                metadata.AppendChild(dependencies);
            }

            document.Save(nuspecFile);
            CommandOutput.WriteLine("更新完成");
        }

    }
}