using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using System;

namespace NuspecMaker
{
    internal static class CommandOutput
    {
        public static IVsOutputWindowPane Output;
        static CommandOutput()
        {
            IVsOutputWindow outWindow = Package.GetGlobalService(typeof(SVsOutputWindow)) as IVsOutputWindow;

            // Use e.g. Tools -> Create GUID to make a stable, but unique GUID for your pane.
            // Also, in a real project, this should probably be a static constant, and not a local variable
            Guid customGuid = new Guid("DFD14CBB-7964-4621-A051-13CC4C1B6C7B");
            string customTitle = "Nuspec 生成输出";
            outWindow.CreatePane(ref customGuid, customTitle, 1, 1);

            outWindow.GetPane(ref customGuid, out Output);

            Output.Activate(); // Brings this pane into view
        }

        public static void WriteLine(string message)
        {
            Output.OutputString(message + Environment.NewLine);
        }

        public static void WriteLine()
        {
            Output.OutputString(Environment.NewLine);
        }
    }
}