using EnvDTE;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using System;
using System.ComponentModel.Design;
using System.IO;
using Task = System.Threading.Tasks.Task;

namespace NuspecMaker
{
    /// <summary>
    /// Command handler
    /// </summary>
    internal sealed class MakeNuspecCommand
    {
        /// <summary>
        /// Command ID.
        /// </summary>
        public const int CommandId = 0x0100;

        /// <summary>
        /// Command menu group (command set GUID).
        /// </summary>
        public static readonly Guid CommandSet = new Guid("9a5ca373-62cd-4d5d-b75b-15dbf4a9aa10");

        /// <summary>
        /// VS Package that provides this command, not null.
        /// </summary>
        private readonly AsyncPackage package;

        /// <summary>
        /// Initializes a new instance of the <see cref="MakeNuspecCommand"/> class.
        /// Adds our command handlers for menu (commands must exist in the command table file)
        /// </summary>
        /// <param name="package">Owner package, not null.</param>
        /// <param name="commandService">Command service to add command to, not null.</param>
        private MakeNuspecCommand(AsyncPackage package, OleMenuCommandService commandService)
        {
            this.package = package ?? throw new ArgumentNullException(nameof(package));
            commandService = commandService ?? throw new ArgumentNullException(nameof(commandService));

            var menuCommandID = new CommandID(CommandSet, CommandId);
            var menuItem = new MenuCommand(this.Execute, menuCommandID);
            commandService.AddCommand(menuItem);
        }

        /// <summary>
        /// Gets the instance of the command.
        /// </summary>
        public static MakeNuspecCommand Instance
        {
            get;
            private set;
        }

        /// <summary>
        /// Gets the service provider from the owner package.
        /// </summary>
        private Microsoft.VisualStudio.Shell.IAsyncServiceProvider ServiceProvider
        {
            get
            {
                return this.package;
            }
        }

        /// <summary>
        /// Initializes the singleton instance of the command.
        /// </summary>
        /// <param name="package">Owner package, not null.</param>
        public static async Task InitializeAsync(AsyncPackage package)
        {
            // Switch to the main thread - the call to AddCommand in MakeNuspecCommand's constructor requires
            // the UI thread.
            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync(package.DisposalToken);

            OleMenuCommandService commandService = await package.GetServiceAsync((typeof(IMenuCommandService))) as OleMenuCommandService;
            Instance = new MakeNuspecCommand(package, commandService);
        }

        /// <summary>
        /// This function is the callback used to execute the command when the menu item is clicked.
        /// See the constructor to see how the menu item is associated with this function using
        /// OleMenuCommandService service and MenuCommand class.
        /// </summary>
        /// <param name="sender">Event sender.</param>
        /// <param name="e">Event args.</param>
        private void Execute(object sender, EventArgs e)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            CommandOutput.Output.Clear();
            CommandOutput.WriteLine("开始更新.nuspec文件");
            CommandOutput.WriteLine();
            try
            {
                ThreadHelper.JoinableTaskFactory.Run(RunAsync);
                CommandOutput.WriteLine("创建/更新 .nuspec 完成");
            }
            catch (Exception ex)
            {
                CommandOutput.WriteLine($"操作失败：{ex.Message}");
            }
        }

        #region Nuspec Generator

        private async Task RunAsync()
        {
            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
            DTE dte = (DTE)await this.ServiceProvider.GetServiceAsync(typeof(DTE));
            if (dte.Solution == null || dte.Solution.Projects.Count == 0)
            {
                return;
            }

            var solutionRoot = Path.GetDirectoryName(dte.Solution.FullName);
            NuspecConfiguration.SolutionRoot = solutionRoot;
            if (!NuspecConfiguration.Load())
            {
                CommandOutput.WriteLine("首次运行，已在解决方案根目录创建 nuspec.config，请更新全局配置后再次运行。");
                return;
            }
            var count = dte.Solution.Projects.Count;
            for (var i = 1; i <= count; i++)
            {
                var pj = dte.Solution.Projects.Item(i);
                var name = pj.Name;
                var fullName = pj.FullName;

                CommandOutput.WriteLine($"{i}/{count}: 开始更新项目{name}");
                NuspecConfiguration.Make(name, fullName);
                CommandOutput.WriteLine();
            }
        }

        #endregion
    }
}
