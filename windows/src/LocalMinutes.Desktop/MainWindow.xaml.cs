using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using LocalMinutes.Core;
using Microsoft.Win32;
using QRCoder;

namespace LocalMinutes.Desktop;

public partial class MainWindow : Window
{
    private readonly PortableProfile profile;
    private readonly MeetingStore store;
    private readonly ModelManager models;
    private readonly RecordingService recording;
    private readonly AudioPlayback playback=new();
    private readonly LocalIntelligence intelligence;
    private readonly SyncHost sync;
    private readonly DispatcherTimer notesTimer=new(){Interval=TimeSpan.FromMilliseconds(700)};
    private readonly DispatcherTimer clockTimer=new(){Interval=TimeSpan.FromSeconds(1)};
    private readonly CancellationTokenSource shutdown=new();
    private Meeting? selected;
    private GeneratedDocument? summary;
    private long noteRevision;
    private string savedNotes="";
    private bool loading;
    private bool busy;
    private bool closing;
    private bool summaryDirty;
    private string savedSummary="";
    private CancellationTokenSource? operationCancellation;
    private TaskCompletionSource? operationSettled;
    private ComboBox? summaryModels;
    private TextBlock? modelStatus;
    private TextBox? connectionCode;
    private Image? pairImage;
    private ComboBox? addresses;

    public MainWindow(PortableProfile profile,MeetingStore store,bool preview=false)
    {
        this.profile=profile;this.store=store;LibraryExchange.Recover(profile,store);MeetingFiles.Recover(profile,store);
        models=new(profile);recording=new(profile,store,models);
        intelligence=new(profile,store,models,Path.Combine(AppContext.BaseDirectory,"runtimes","llama"));
        sync=new(profile,store,()=>!busy&&!recording.IsActive);
        InitializeComponent();
        var recoveredCount=RecordingService.ReconcileInterrupted(profile,store);
        if(recoveredCount>0)StatusText.Text=$"Found {recoveredCount} interrupted recording(s). Original files and completed transcript segments are retained.";
        sync.PreparingImport=()=>Dispatcher.InvokeAsync(()=>{if(busy||recording.IsActive)throw new InvalidOperationException("Library is busy.");FlushDrafts();busy=true;MeetingsPage.IsEnabled=false;}).Task;
        sync.ImportFinished=()=>Dispatcher.BeginInvoke(()=>{busy=false;MeetingsPage.IsEnabled=true;});
        DeviceName.Text=profile.Identity.DeviceName;DeviceId.Text=$"Device {profile.Identity.ReplicaId[..8]}\nInstance {profile.RunId[..8]} · Portable";StoragePath.Text=profile.Root;
        notesTimer.Tick+=(_,_)=>{notesTimer.Stop();Try(FlushNotes);};
        clockTimer.Tick+=(_,_)=>{RecordingTimer.Text=recording.Elapsed.ToString(@"hh\:mm\:ss");};clockTimer.Start();
        SummaryText.TextChanged+=(_,_)=>{if(!loading)summaryDirty=SummaryText.Text!=savedSummary;};
        recording.TranscriptUpdated+=text=>Dispatcher.BeginInvoke(()=>LiveTranscript.AppendText(text+"\n"));
        recording.Interrupted+=text=>Dispatcher.BeginInvoke(()=>{RecordingState.Text=text;StatusText.Text=text;RecordButton.Content="Finish interrupted recording";});
        sync.Status+=text=>Dispatcher.BeginInvoke(()=>{SyncStatus.Text=text;StatusText.Text=text;if(sync.ConnectedPhone!=null&&connectionCode!=null&&pairImage!=null){connectionCode.Clear();connectionCode.Visibility=Visibility.Collapsed;pairImage.Source=null;pairImage.Visibility=Visibility.Collapsed;}});
        sync.Imported+=()=>Dispatcher.BeginInvoke(()=>{ReloadMeetings(selected?.Id);StatusText.Text="Library received. Models and device settings are unchanged.";});
        MicrophoneList.ItemsSource=RecordingService.Microphones();MicrophoneList.DisplayMemberPath="Name";MicrophoneList.SelectedIndex=0;
        BuildModelControls();BuildSyncControls();ReloadMeetings();ShowPage(MeetingsPage);
        if(!preview)Loaded+=(_,_)=>Try(()=>sync.Start());
    }
    private void Try(Action action)
    {try{action();}catch(Exception error){Report(error);}}
    private void Report(Exception error)
    {StatusText.Text=error.Message;MessageBox.Show(this,error.Message,"LocalMinutes",MessageBoxButton.OK,MessageBoxImage.Warning);}
    private async Task Work(Func<CancellationToken,Task> action)
    {
        if(busy){StatusText.Text="Wait for the current operation to finish.";return;}
        try
        {
            FlushDrafts();busy=true;MeetingsPage.IsEnabled=false;operationSettled=new(TaskCreationOptions.RunContinuationsAsynchronously);
            operationCancellation=CancellationTokenSource.CreateLinkedTokenSource(shutdown.Token);
            await action(operationCancellation.Token);
        }
        catch(OperationCanceledException){StatusText.Text="Operation cancelled. Saved data is retained.";}
        catch(Exception error){Report(error);}
        finally{busy=false;MeetingsPage.IsEnabled=true;operationCancellation?.Dispose();operationCancellation=null;UpdateModelStatus();operationSettled?.TrySetResult();operationSettled=null;}
    }
    private void ShowPage(UIElement page)
    {
        Try(()=>{FlushDrafts();foreach(var item in new UIElement[]{MeetingsPage,RecordPage,SyncPage,SettingsPage})item.Visibility=item==page?Visibility.Visible:Visibility.Collapsed;
            foreach(var (button,target) in new[]{(MeetingsNav,(UIElement)MeetingsPage),(RecordNav,RecordPage),(SyncNav,SyncPage),(SettingsNav,SettingsPage)})
            {if(target==page){button.SetResourceReference(BackgroundProperty,"SelectionBrush");button.SetResourceReference(ForegroundProperty,"AccentBrush");}else{button.Background=Brushes.Transparent;button.SetResourceReference(ForegroundProperty,"InkBrush");}}
        });
    }
    private void ShowMeetings(object sender,RoutedEventArgs e)=>ShowPage(MeetingsPage);
    private void ShowRecord(object sender,RoutedEventArgs e)=>ShowPage(RecordPage);
    private void ShowSync(object sender,RoutedEventArgs e)
    {if(addresses!=null){addresses.ItemsSource=SyncHost.LocalAddresses();addresses.SelectedIndex=0;}ShowPage(SyncPage);}
    private void ShowSettings(object sender,RoutedEventArgs e)=>ShowPage(SettingsPage);
    private void SearchChanged(object sender,TextChangedEventArgs e){if(IsInitialized&&!loading)Try(()=>ReloadMeetings(selected?.Id));}
    private void ReloadMeetings(string? id=null)
    {
        loading=true;
        try{var meetings=store.Meetings(SearchBox.Text);MeetingList.ItemsSource=meetings;MeetingCount.Text=$"{meetings.Count} meetings";MeetingList.SelectedItem=meetings.FirstOrDefault(x=>x.Id==id);}
        finally{loading=false;}
        LoadMeeting(MeetingList.SelectedItem as Meeting);
    }
    private void MeetingSelected(object sender,SelectionChangedEventArgs e)
    {
        if(loading||!IsInitialized)return;
        Try(()=>{FlushDrafts();LoadMeeting(MeetingList.SelectedItem as Meeting);});
    }
    private void LoadMeeting(Meeting? meeting)
    {
        loading=true;
        try
        {
            playback.Stop();selected=meeting;
            EmptyMeeting.Visibility=meeting==null?Visibility.Visible:Visibility.Collapsed;MeetingDetail.Visibility=meeting==null?Visibility.Collapsed:Visibility.Visible;
            if(meeting==null)return;
            MeetingTitle.Text=meeting.Title;MeetingMetadata.Text=meeting.DateLabel+" · "+meeting.DurationLabel;
            var note=store.Note(meeting.Id);noteRevision=note?.EditRevision??0;savedNotes=note?.Text??"";NotesText.Text=savedNotes;NotesState.Text="Saved on this device";
            summary=store.PreferredSummary(meeting.Id);savedSummary=summary?.EditedText??"";SummaryText.Text=savedSummary;summaryDirty=false;
            SummaryText.IsReadOnly=summary==null;
            TranscriptSearch.Text="";RefreshTranscript();AnswersList.ItemsSource=store.Documents(meeting.Id).Where(x=>x.Kind=="question_answer").ToList();
            PlaybackStatus.Text="Original recording";
        }
        finally{loading=false;}
    }
    private void NewMeeting(object sender,RoutedEventArgs e)=>Try(()=>
    {
        if(recording.IsActive)throw new InvalidOperationException("Finish the active recording first.");
        FlushDrafts();var title=Prompt("New meeting","Meeting title","New meeting");if(title==null)return;
        var id=WireJson.NewId();store.Create(new(id,title,WireJson.Now,"completed",0));ReloadMeetings(id);ShowPage(MeetingsPage);ContentTabs.SelectedIndex=2;
    });
    private void NotesChanged(object sender,TextChangedEventArgs e)
    {if(loading||selected==null)return;NotesState.Text="Saving…";notesTimer.Stop();notesTimer.Start();}
    private void FlushNotes()
    {
        notesTimer.Stop();if(selected==null||NotesText.Text==savedNotes)return;
        var note=store.SaveNote(selected.Id,NotesText.Text,noteRevision);noteRevision=note.EditRevision;savedNotes=note.Text;NotesState.Text="Saved on this device";
    }
    private void FlushDrafts()
    {FlushNotes();if(summaryDirty&&summary!=null){summary=store.SaveDocumentEdit(summary,SummaryText.Text);savedSummary=summary.EditedText;summaryDirty=false;}}
    private void SaveSummary(object sender,RoutedEventArgs e)=>Try(()=>{FlushDrafts();StatusText.Text="Summary edit saved.";});
    private void ContentTabChanged(object sender,SelectionChangedEventArgs e){if(e.Source==ContentTabs&&!loading&&IsInitialized)Try(FlushDrafts);}
    private sealed record TranscriptRow(TranscriptSegment Segment)
    {public string Text=>Segment.Text;public string Timestamp=>TimeSpan.FromSeconds(Segment.StartSample/16000d).ToString(@"hh\:mm\:ss");}
    private void RefreshTranscript()
    {if(selected!=null)TranscriptList.ItemsSource=store.Transcript(selected.Id).Where(x=>x.Text.Contains(TranscriptSearch.Text,StringComparison.OrdinalIgnoreCase)).Select(x=>new TranscriptRow(x)).ToList();}
    private void TranscriptSearchChanged(object sender,TextChangedEventArgs e){if(IsInitialized)Try(RefreshTranscript);}
    private void TranscriptSeek(object sender,MouseButtonEventArgs e)=>Try(()=>{if(selected!=null&&TranscriptList.SelectedItem is TranscriptRow row){EnsurePlayback();playback.Play(profile.MeetingDirectory(selected.Id),row.Segment.StartSample);PlaybackStatus.Text="Playing from "+row.Timestamp;}});
    private void EnsurePlayback(){if(recording.IsActive)throw new InvalidOperationException("Stop recording before playing audio.");}
    private void PlayAudio(object sender,RoutedEventArgs e)=>Try(()=>{if(selected==null)return;EnsurePlayback();playback.Play(profile.MeetingDirectory(selected.Id));PlaybackStatus.Text="Playing original audio";});
    private void StopAudio(object sender,RoutedEventArgs e){playback.Stop();PlaybackStatus.Text="Stopped";}
    private void MeetingMenu(object sender,RoutedEventArgs e)
    {
        var menu=new ContextMenu();
        void Item(string title,Action action){var item=new MenuItem{Header=title};item.Click+=(_,_)=>Try(action);menu.Items.Add(item);}
        Item("Rename",()=>{if(selected==null)return;FlushDrafts();var title=Prompt("Rename meeting","Meeting title",selected.Title);if(title!=null){store.Rename(selected.Id,title);ReloadMeetings(selected.Id);}});
        Item("Export meeting text",()=>{if(selected==null)return;FlushDrafts();var text=selected.Title+"\n"+selected.DateLabel+"\n\nNotes\n"+savedNotes+"\n\nTranscript\n"+string.Join("\n\n",store.Transcript(selected.Id).Select(x=>x.Text))+"\n\n"+savedSummary;SaveText(text,"meeting.md");});
        Item("Delete summaries",()=>{if(selected==null)return;if(MessageBox.Show(this,"Delete this meeting's saved summaries? Audio, notes, transcript and answers remain.","Delete summaries",MessageBoxButton.OKCancel,MessageBoxImage.Warning)==MessageBoxResult.OK){store.DeleteSummaries(selected.Id);LoadMeeting(selected);}});
        Item("Delete meeting",()=>{if(selected==null)return;if(recording.IsActive)throw new InvalidOperationException("Finish recording first.");if(MessageBox.Show(this,"Delete this meeting and its audio on this PC? A copy on your iPhone is not deleted and can return on the next send.","Delete meeting",MessageBoxButton.OKCancel,MessageBoxImage.Warning)!=MessageBoxResult.OK)return;playback.Stop();MeetingFiles.Delete(profile,store,selected.Id);ReloadMeetings();});
        menu.PlacementTarget=(Button)sender;menu.IsOpen=true;
    }
    private void SaveText(string text,string name)
    {var dialog=new SaveFileDialog{FileName=name,Filter="Markdown|*.md|Text|*.txt"};if(dialog.ShowDialog(this)==true)File.WriteAllText(dialog.FileName,text,new UTF8Encoding(false));}
    private void ExportSummary(object sender,RoutedEventArgs e)=>Try(()=>{FlushDrafts();SaveText(SummaryText.Text,"summary.md");});
    private void SummarySources(object sender,RoutedEventArgs e)=>Try(()=>{if(summary!=null)ShowSources(summary);});
    private void AnswerSources(object sender,RoutedEventArgs e)=>Try(()=>{if(((Button)sender).DataContext is GeneratedDocument document)ShowSources(document);});
    private void EditAnswer(object sender,RoutedEventArgs e)=>Try(()=>
    {
        if(((Button)sender).DataContext is not GeneratedDocument document)return;FlushDrafts();
        var editor=new Window{Owner=this,Title="Edit saved answer",Width=640,Height=480,WindowStartupLocation=WindowStartupLocation.CenterOwner};
        var layout=new DockPanel{Margin=new Thickness(24)};var save=new Button{Content="Save answer",Margin=new Thickness(0,16,0,0),HorizontalAlignment=HorizontalAlignment.Right};DockPanel.SetDock(save,Dock.Bottom);layout.Children.Add(save);
        var text=new TextBox{Text=document.EditedText,AcceptsReturn=true,TextWrapping=TextWrapping.Wrap,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};layout.Children.Add(text);editor.Content=layout;
        save.Click+=(_,_)=>{try{store.SaveDocumentEdit(document,text.Text);editor.DialogResult=true;}catch(Exception error){MessageBox.Show(editor,error.Message,"Could not save answer");}};
        if(editor.ShowDialog()==true&&selected!=null)AnswersList.ItemsSource=store.Documents(selected.Id).Where(x=>x.Kind=="question_answer").ToList();
    });
    private void ShowSources(GeneratedDocument document)
    {
        var citations=DocumentEvidence.Read(document,store.Transcript(document.MeetingId));
        var window=new Window{Owner=this,Title="Original sources",Width=720,Height=520,WindowStartupLocation=WindowStartupLocation.CenterOwner};
        var layout=new DockPanel{Margin=new Thickness(24)};var button=new Button{Content="Play selected source",Margin=new Thickness(0,16,0,0),HorizontalAlignment=HorizontalAlignment.Left};DockPanel.SetDock(button,Dock.Bottom);layout.Children.Add(button);
        var list=new ListBox{ItemsSource=citations,DisplayMemberPath="Label"};layout.Children.Add(list);window.Content=layout;
        if(citations.Count==0){layout.Children.Remove(list);layout.Children.Add(new TextBlock{Text="This document has no verifiable saved source references."});button.IsEnabled=false;}
        button.Click+=(_,_)=>Try(()=>{if(list.SelectedItem is DocumentCitation citation){EnsurePlayback();playback.Play(profile.MeetingDirectory(document.MeetingId),citation.StartSample);}});
        window.ShowDialog();
    }
    private async void GenerateSummary(object sender,RoutedEventArgs e)=>await Generate(null);
    private async void AskMeeting(object sender,RoutedEventArgs e)
    {if(string.IsNullOrWhiteSpace(QuestionText.Text)){StatusText.Text="Enter a question about this meeting.";return;}await Generate(QuestionText.Text.Trim());}
    private async Task Generate(string? question)
    {
        if(selected==null)return;var meeting=selected;
        if(recording.IsActive){StatusText.Text="Stop recording before generation.";return;}
        await Work(async token=>{await intelligence.GenerateAsync(meeting,question,new Progress<string>(value=>StatusText.Text=value),token);LoadMeeting(meeting);StatusText.Text="Generated document saved with source references.";});
    }
    private async void ToggleRecording(object sender,RoutedEventArgs e)
    {
        if(busy){StatusText.Text="Wait for the current operation to finish.";return;}
        if(recording.IsActive)
        {
            await Work(async _=>{RecordButton.IsEnabled=false;RecordingState.Text="Saving and finishing transcription…";await recording.StopAsync();ReloadMeetings(recording.MeetingId);RecordingState.Text="Recording saved";});
        }
        else if(MicrophoneList.SelectedItem is Microphone microphone)
        {
            await Work(async token=>{playback.Stop();RecordingState.Text="Preparing microphone and speech model…";LiveTranscript.Clear();await recording.StartAsync(microphone.Index,token);RecordingState.Text="Recording · Original audio is saved locally";});
        }
        else StatusText.Text="Choose an available microphone.";
        RecordButton.IsEnabled=true;RecordButton.Content=recording.IsActive?"Stop recording":"Start recording";
    }
    private void OpenRecording(object sender,RoutedEventArgs e)=>Try(()=>{ReloadMeetings(recording.MeetingId);ShowPage(MeetingsPage);});
    private async void ImportBackup(object sender,RoutedEventArgs e)
    {
        if(recording.IsActive){StatusText.Text="Stop recording before importing.";return;}
        var dialog=new OpenFolderDialog{Title="Choose an iPhone .localminutesbackup or LocalMinutes exchange folder"};if(dialog.ShowDialog(this)!=true)return;
        if(MessageBox.Show(this,"Incoming edits replace matching local edits. Receiver-only meetings are kept. Continue?","Import library",MessageBoxButton.OKCancel)!=MessageBoxResult.OK)return;
        await Work(async token=>
        {
            var staging=Path.Combine(profile.Root,"imports",WireJson.NewId());
            var source=File.Exists(Path.Combine(dialog.FolderName,"records.jsonl"))?dialog.FolderName:await Task.Run(()=>IosBackupReader.ConvertToExchange(dialog.FolderName,staging,WireJson.NewId()),token);
            var receipt=await Task.Run(()=>LibraryExchange.Apply(profile,store,source),token);ReloadMeetings();StatusText.Text=$"Imported {receipt.Meetings} meeting records. Local models were not changed.";
        });
    }
    private async void ExportBackup(object sender,RoutedEventArgs e)
    {
        if(recording.IsActive){StatusText.Text="Stop recording before exporting.";return;}
        var dialog=new OpenFolderDialog{Title="Choose a parent folder for the exported library"};if(dialog.ShowDialog(this)!=true)return;
        await Work(async token=>{var target=Path.Combine(dialog.FolderName,"LocalMinutes-"+DateTime.Now.ToString("yyyyMMdd-HHmmss")+".lmtransfer");await Task.Run(()=>LibraryExchange.Create(profile,store,target),token);StatusText.Text="Exported library to "+target;});
    }
    private void OpenDataFolder(object sender,RoutedEventArgs e)=>Try(()=>Process.Start(new ProcessStartInfo("explorer.exe"){ArgumentList={profile.Root},UseShellExecute=false}));
    private void BuildModelControls()
    {
        summaryModels=new ComboBox{ItemsSource=models.SummaryModels,DisplayMemberPath="DisplayName",Padding=new Thickness(10),Margin=new Thickness(0,0,0,16)};
        summaryModels.SelectedItem=models.SelectedSummary??models.SummaryModels[0];ModelControls.Children.Add(summaryModels);
        var row=new WrapPanel();ModelControls.Children.Add(row);
        void Button(string label,Func<Task> action){var button=new Button{Content=label,Margin=new Thickness(0,0,8,8)};button.Click+=async(_,_)=>await action();row.Children.Add(button);}
        Button("Download summary model",async()=>{if(summaryModels.SelectedItem is ModelVariant model)await Work(token=>models.DownloadSummaryAsync(model,new Progress<string>(x=>StatusText.Text=x),token));});
        Button("Equip selected",()=>{Try(()=>{if(summaryModels.SelectedItem is ModelVariant model)models.Select(model);UpdateModelStatus();});return Task.CompletedTask;});
        Button("Download Parakeet v3",()=>Work(token=>models.DownloadSpeechAsync(new Progress<string>(x=>StatusText.Text=x),token)));
        Button("Remove selected summary model",async()=>{if(recording.IsActive){StatusText.Text="Finish recording first.";return;}if(summaryModels.SelectedItem is ModelVariant model)await Work(token=>models.RemoveSummaryAsync(model,token));});
        Button("Remove speech model",async()=>{if(recording.IsActive){StatusText.Text="Finish recording first.";return;}await Work(token=>models.RemoveSpeechAsync(token));});
        Button("Cancel current task",()=>{operationCancellation?.Cancel();return Task.CompletedTask;});
        modelStatus=new TextBlock{Margin=new Thickness(0,8,0,0)};ModelControls.Children.Add(modelStatus);UpdateModelStatus();
        if(intelligence.GpuRuntimeAvailable)
        {
            var gpu=new CheckBox{Content="Use NVIDIA GPU for summaries and answers",IsChecked=intelligence.UseGpu,Margin=new Thickness(0,16,0,0)};
            gpu.Checked+=(_,_)=>intelligence.UseGpu=true;gpu.Unchecked+=(_,_)=>intelligence.UseGpu=false;ModelControls.Children.Add(gpu);
        }
    }
    private void UpdateModelStatus()
    {if(modelStatus!=null)modelStatus.Text=$"Speech: {(models.SpeechPresent?"Parakeet v3 available":"download required")}\nSummaries: {models.SelectedSummary?.DisplayName??"no model equipped"}";}
    private void BuildSyncControls()
    {
        addresses=new ComboBox{ItemsSource=SyncHost.LocalAddresses(),Padding=new Thickness(10),Margin=new Thickness(0,0,0,12)};addresses.SelectedIndex=0;SyncControls.Children.Add(addresses);
        var row=new WrapPanel();SyncControls.Children.Add(row);
        var send=new Button{Content="Sync PC library to iPhone",Style=(Style)FindResource("PrimaryButton")};send.Click+=async(_,_)=>
        {
            if(busy||recording.IsActive){StatusText.Text="Finish recording or generation before syncing.";return;}
            await Work(sync.QueueSendAsync);
        };row.Children.Add(send);
        var pair=new Button{Content="Pair an iPhone"};pair.Click+=(_,_)=>Try(()=>
        {
            if(addresses.SelectedItem is not string address)throw new InvalidOperationException("Connect this PC to your local Wi-Fi network.");
            var invitation=sync.Invite(address);var code="localminutes://pair/"+Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(invitation,WireJson.Options));connectionCode!.Text=code;
            var bytes=PngByteQRCodeHelper.GetQRCode(code,QRCodeGenerator.ECCLevel.Q,6);using var stream=new MemoryStream(bytes);var bitmap=new BitmapImage();bitmap.BeginInit();bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.StreamSource=stream;bitmap.EndInit();pairImage!.Source=bitmap;
            pairImage.Visibility=Visibility.Visible;connectionCode.Visibility=Visibility.Visible;
            SyncStatus.Text="Scan this invitation in LocalMinutes on iPhone. It expires in five minutes.";
        });row.Children.Add(pair);
        var forget=new Button{Content="Forget paired devices"};forget.Click+=(_,_)=>Try(()=>{if(MessageBox.Show(this,"Forget all paired devices? They must pair again before syncing.","Forget devices",MessageBoxButton.OKCancel)==MessageBoxResult.OK)sync.ForgetPeers();});row.Children.Add(forget);
        var cancel=new Button{Content="Cancel PC send"};cancel.Click+=(_,_)=>Try(sync.CancelPendingSend);row.Children.Add(cancel);
        pairImage=new Image{Width=240,Height=240,HorizontalAlignment=HorizontalAlignment.Left,Margin=new Thickness(0,20,0,8),Visibility=Visibility.Collapsed};SyncControls.Children.Add(pairImage);
        connectionCode=new TextBox{IsReadOnly=true,TextWrapping=TextWrapping.Wrap,MaxHeight=100,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,Visibility=Visibility.Collapsed};SyncControls.Children.Add(connectionCode);
        SyncControls.Children.Add(new TextBlock{Text="If discovery is blocked, the invitation uses the selected local address. Allow LocalMinutes through Windows Firewall on your Private network.",Margin=new Thickness(0,14,0,0)});
    }
    private void ThemeChanged(object sender,RoutedEventArgs e)
    {
        if(!IsInitialized)return;bool dark=DarkMode.IsChecked==true;
        foreach(var (key,color) in new[]{("PageBrush",dark?"#111216":"#F5F5F7"),("SurfaceBrush",dark?"#1C1E24":"#FFFFFF"),("InkBrush",dark?"#F2F3F5":"#202126"),("SecondaryBrush",dark?"#B2B5BF":"#656976"),("AccentBrush",dark?"#70ADFF":"#0065D4"),("SelectionBrush",dark?"#243752":"#E8F1FF")})Application.Current.Resources[key]=new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
    }
    private string? Prompt(string title,string label,string value)
    {
        var window=new Window{Owner=this,Title=title,Width=460,Height=210,WindowStartupLocation=WindowStartupLocation.CenterOwner,ResizeMode=ResizeMode.NoResize};
        var panel=new StackPanel{Margin=new Thickness(24)};panel.Children.Add(new TextBlock{Text=label});var input=new TextBox{Text=value,Margin=new Thickness(0,12,0,16)};panel.Children.Add(input);var save=new Button{Content="Save",IsDefault=true,HorizontalAlignment=HorizontalAlignment.Right};save.Click+=(_,_)=>{if(!string.IsNullOrWhiteSpace(input.Text)){window.DialogResult=true;}};panel.Children.Add(save);window.Content=panel;window.Loaded+=(_,_)=>{input.Focus();input.SelectAll();};return window.ShowDialog()==true?input.Text.Trim():null;
    }
    private async void WindowClosing(object? sender,CancelEventArgs e)
    {
        if(closing)return;
        e.Cancel=true;
        if(recording.IsActive&&MessageBox.Show(this,"Stop and save the active recording before closing?","Close LocalMinutes",MessageBoxButton.OKCancel)!=MessageBoxResult.OK)return;
        try
        {
            FlushDrafts();shutdown.Cancel();operationCancellation?.Cancel();if(operationSettled!=null)await operationSettled.Task;
            await recording.StopAsync();await sync.DisposeAsync();playback.Dispose();notesTimer.Stop();clockTimer.Stop();closing=true;Close();
        }
        catch(Exception error){Report(error);}
    }

    public async Task SelfCheckAsync(string resultPath)
    {
        if(store.Meetings().Count!=0)throw new InvalidOperationException("Self-check requires an empty isolated profile.");
        foreach(var library in new[]{"onnxruntime.dll","sherpa-onnx-c-api.dll"})
        {var handle=System.Runtime.InteropServices.NativeLibrary.Load(Path.Combine(AppContext.BaseDirectory,library));System.Runtime.InteropServices.NativeLibrary.Free(handle);}
        var executable=Path.Combine(AppContext.BaseDirectory,"runtimes","llama","llama-completion.exe");
        using var process=Process.Start(new ProcessStartInfo(executable){ArgumentList={"--version"},UseShellExecute=false,CreateNoWindow=true,RedirectStandardError=true,RedirectStandardOutput=true})??throw new IOException("Native runtime failed to start.");
        var output=process.StandardOutput.ReadToEndAsync();var errors=process.StandardError.ReadToEndAsync();await process.WaitForExitAsync();
        var version=(await output)+(await errors);if(process.ExitCode!=0||!version.Contains("11900",StringComparison.Ordinal))throw new IOException("Pinned llama.cpp runtime failed its version check.");
        var root=(FrameworkElement)Content;root.Measure(new Size(1440,900));root.Arrange(new Rect(0,0,1440,900));root.UpdateLayout();
        var report=new{passed=true,framework=Environment.Version.ToString(),runtimeDirectory=System.Runtime.InteropServices.RuntimeEnvironment.GetRuntimeDirectory(),bundledRuntime=File.Exists(Path.Combine(AppContext.BaseDirectory,"coreclr.dll")),summaryModels=models.SummaryModels.Count,speechRuntimeLoaded=true,gpuRuntimeAvailable=intelligence.GpuRuntimeAvailable,gpuEnabled=intelligence.UseGpu,nativeVersion=version.Trim(),layoutWidth=root.ActualWidth,layoutHeight=root.ActualHeight};
        File.WriteAllText(resultPath,JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true}));
        await sync.DisposeAsync();playback.Dispose();notesTimer.Stop();clockTimer.Stop();closing=true;Close();
    }

#if DEBUG
    public async Task RenderPreviewAsync(string destination)
    {
        if(store.Meetings().Count!=0)throw new InvalidOperationException("Preview refuses a nonempty library.");
        Directory.CreateDirectory(destination);
        var meeting=new Meeting(WireJson.NewId(),"Product review",WireJson.Now,"completed",32832000);store.Create(meeting);
        store.SaveNote(meeting.Id,"Synthetic preview notes. Check recovery behavior and the local transfer flow before release.",0);
        store.CreateDocument(new(WireJson.NewId(),meeting.Id,"summary","{}",null,"Overview\n\n• The team reviewed the meeting capture flow and discussed release readiness.\n\nMinutes of Meetings\n\n• Preserve notes when switching between meetings.\n\n• Make device-to-device transfers explicit.\n\n• Test original audio, interruptions and source citations on both devices.",0,"synthetic","preview",WireJson.Now,WireJson.Now));
        store.Create(new(WireJson.NewId(),"Design critique",WireJson.Now-3600,"completed",21120000));
        store.Create(new(WireJson.NewId(),"Weekly planning",WireJson.Now-86400,"completed",45120000));
        ReloadMeetings(meeting.Id);
        async Task Capture(string name)
        {
            await Dispatcher.InvokeAsync(()=>{},DispatcherPriority.ApplicationIdle);
            var visual=(FrameworkElement)Content;visual.UpdateLayout();
            var image=new RenderTargetBitmap((int)Math.Ceiling(visual.ActualWidth),(int)Math.Ceiling(visual.ActualHeight),96,96,PixelFormats.Pbgra32);image.Render(visual);
            var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(image));using var file=File.Create(Path.Combine(destination,name+".png"));encoder.Save(file);
        }
        await Capture("meetings");ShowPage(SyncPage);await Capture("sync");ShowPage(SettingsPage);await Capture("settings");
        DarkMode.IsChecked=true;ShowPage(MeetingsPage);await Capture("meetings-dark");
        Width=1280;Height=800;DarkMode.IsChecked=false;await Capture("meetings-1280");
        await sync.DisposeAsync();playback.Dispose();notesTimer.Stop();clockTimer.Stop();closing=true;Close();
    }
#endif
}
