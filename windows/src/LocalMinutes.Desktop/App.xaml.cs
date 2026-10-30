using System.IO;
using System.Windows;
using LocalMinutes.Core;
using Microsoft.Win32;

namespace LocalMinutes.Desktop;

public partial class App : Application
{
    private PortableProfile? profile;
    private MeetingStore? store;
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        try
        {
            var dataRoot = Path.Combine(AppContext.BaseDirectory, "LocalMinutes.Data");
            var argument = Array.IndexOf(e.Args, "--data-directory");
            if (argument >= 0 && argument + 1 < e.Args.Length) dataRoot = Path.GetFullPath(e.Args[argument + 1]);
            bool preview=false;
            var selfCheck=Array.IndexOf(e.Args,"--self-check");
            if(selfCheck>=0&&(argument<0||selfCheck+1>=e.Args.Length))throw new ArgumentException("Self-check requires an isolated data directory and output file.");
#if DEBUG
            preview=e.Args.Contains("--preview");
            if(preview&&argument<0)throw new ArgumentException("Preview requires an explicit isolated data directory.");
#endif
            try { profile = new PortableProfile(dataRoot); }
            catch (UnauthorizedAccessException)
            {
                var chooser = new OpenFolderDialog { Title = "Choose a writable LocalMinutes data folder" };
                if (chooser.ShowDialog() != true) { Shutdown(); return; }
                profile = new PortableProfile(chooser.FolderName);
            }
            store = new MeetingStore(profile.DatabasePath);
            var window = new MainWindow(profile, store, preview||selfCheck>=0); MainWindow = window;
            if(selfCheck>=0)
            {
                var resultPath=Path.GetFullPath(e.Args[selfCheck+1]);
                Dispatcher.BeginInvoke(async()=>
                {
                    try {await window.SelfCheckAsync(resultPath);Shutdown();}
                    catch(Exception error){File.WriteAllText(resultPath,error.ToString());Shutdown(1);}
                });
                return;
            }
#if DEBUG
            if(preview)
            {
                window.ShowActivated=false;window.ShowInTaskbar=false;window.Left=-30000;window.Top=-30000;
                window.Loaded+=async(_,_)=>
                {
                    try{await window.RenderPreviewAsync(Path.Combine(dataRoot,"preview"));Shutdown();}
                    catch(Exception error){File.WriteAllText(Path.Combine(dataRoot,"preview-error.txt"),error.ToString());Shutdown(1);}
                };
            }
#endif
            window.Show();
        }
        catch (Exception error)
        {
            MessageBox.Show("LocalMinutes could not open its data. Another instance may already be using this folder.\n\n" + error.Message, "LocalMinutes", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }
    protected override void OnExit(ExitEventArgs e) { store?.Dispose(); profile?.Dispose(); base.OnExit(e); }
}
