using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;

namespace LocalMinutes.Core;

public sealed record ContextWindow(int MaximumTokens,int MaximumOutputTokens,int? YarnOriginalContextTokens);
public sealed record ModelVariant(string Id,string Title,string Family,string Repository,string Revision,string FileName,long ByteCount,string Sha256,ContextWindow ContextWindow,string LicenseIdentifier,string LicenseURL)
{
    public string DisplayName=>$"{Family} · {Title} · {ByteCount/1_000_000:N0} MB";
}
public sealed record ModelFamily(string Id,string Title,List<ModelVariant> Variants);
public sealed record SummaryCatalog(int SchemaVersion,List<ModelFamily> Families);
public sealed record DownloadFile(string Name,long Bytes,string Sha256);

public sealed class ModelManager
{
    public const string SpeechRevision="2bda32ec70b097a55adaa07d9a7173915b43cc78";
    public const string SpeechRepository="csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8";
    public static readonly DownloadFile[] SpeechFiles=[
        new("encoder.int8.onnx",652184281,"acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247"),
        new("decoder.int8.onnx",11845275,"179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e"),
        new("joiner.int8.onnx",6355277,"3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3"),
        new("tokens.txt",93939,"d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d")];
    private readonly PortableProfile profile;
    private readonly SemaphoreSlim transfer=new(1,1);
    public IReadOnlyList<ModelVariant> SummaryModels {get;}
    public string SpeechDirectory=>Path.Combine(profile.ModelsRoot,"parakeet-v3-onnx");
    public string? SelectedSummaryId {get;private set;}
    public ModelVariant? SelectedSummary=>SummaryModels.FirstOrDefault(x=>x.Id==SelectedSummaryId);
    public bool SpeechPresent=>SpeechFiles.All(x=>File.Exists(Path.Combine(SpeechDirectory,x.Name)) && new FileInfo(Path.Combine(SpeechDirectory,x.Name)).Length==x.Bytes);
    private string SelectionPath=>Path.Combine(profile.Root,"model-selection.json");

    public ModelManager(PortableProfile profile)
    {
        this.profile=profile;
        using var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("LocalMinutes.Core.Resources.SummaryCatalog.json")!;
        var catalog=JsonSerializer.Deserialize<SummaryCatalog>(stream,WireJson.Options) ?? throw new InvalidDataException("Missing model catalog.");
        SummaryModels=catalog.Families.SelectMany(x=>x.Variants).ToList();
        if(File.Exists(SelectionPath)) SelectedSummaryId=JsonSerializer.Deserialize<string>(File.ReadAllBytes(SelectionPath));
    }
    public string SummaryPath(ModelVariant model)=>Path.Combine(profile.ModelsRoot,model.Id,model.FileName);
    public bool IsPresent(ModelVariant model)=>File.Exists(SummaryPath(model)) && new FileInfo(SummaryPath(model)).Length==model.ByteCount;
    public void Select(ModelVariant model)
    {
        if(!IsPresent(model)) throw new InvalidOperationException("Download the model first.");
        SafeFiles.WriteAtomic(SelectionPath,JsonSerializer.SerializeToUtf8Bytes(model.Id)); SelectedSummaryId=model.Id;
    }
    public async Task VerifySpeechAsync(CancellationToken token=default)
    { foreach(var file in SpeechFiles) await VerifyAsync(Path.Combine(SpeechDirectory,file.Name),file,token); }
    public Task VerifySummaryAsync(ModelVariant model,CancellationToken token=default)=>VerifyAsync(SummaryPath(model),new(model.FileName,model.ByteCount,model.Sha256),token);
    public async Task DownloadSummaryAsync(ModelVariant model,IProgress<string>? progress,CancellationToken token)
    {
        await transfer.WaitAsync(token);
        try { await DownloadAsync(model.Repository,model.Revision,Path.GetDirectoryName(SummaryPath(model))!,new(model.FileName,model.ByteCount,model.Sha256),progress,token); }
        finally { transfer.Release(); }
    }
    public async Task DownloadSpeechAsync(IProgress<string>? progress,CancellationToken token)
    {
        await transfer.WaitAsync(token);
        try { foreach(var file in SpeechFiles) await DownloadAsync(SpeechRepository,SpeechRevision,SpeechDirectory,file,progress,token); }
        finally { transfer.Release(); }
    }
    public async Task RemoveSummaryAsync(ModelVariant model,CancellationToken token)
    {
        await transfer.WaitAsync(token);
        try
        {
            var directory=Path.GetDirectoryName(SummaryPath(model))!;
            if(Directory.Exists(directory))foreach(var name in new[]{model.FileName,model.FileName+".partial"})
            {var path=SafeFiles.Resolve(directory,name);if(File.Exists(path))File.Delete(path);}
            if(SelectedSummaryId==model.Id){SelectedSummaryId=null;SafeFiles.WriteAtomic(SelectionPath,JsonSerializer.SerializeToUtf8Bytes<string?>(null));}
        }
        finally{transfer.Release();}
    }
    public async Task RemoveSpeechAsync(CancellationToken token)
    {
        await transfer.WaitAsync(token);
        try{if(Directory.Exists(SpeechDirectory))foreach(var file in SpeechFiles)foreach(var name in new[]{file.Name,file.Name+".partial"}){var path=SafeFiles.Resolve(SpeechDirectory,name);if(File.Exists(path))File.Delete(path);}}
        finally{transfer.Release();}
    }
    private static async Task VerifyAsync(string path,DownloadFile file,CancellationToken token)
    {
        SafeFiles.RequireRegularTree(Path.GetDirectoryName(path)!);
        if(!File.Exists(path) || (File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0 || new FileInfo(path).Length!=file.Bytes || await SafeFiles.HashAsync(path,token)!=file.Sha256)
            throw new InvalidDataException("Model is missing or failed verification. Download it again in Settings.");
    }
    private static async Task DownloadAsync(string repository,string revision,string directory,DownloadFile file,IProgress<string>? progress,CancellationToken token)
    {
        SafeFiles.RequireRegularTree(directory); Directory.CreateDirectory(directory);
        var target=SafeFiles.Resolve(directory,file.Name);
        if(File.Exists(target)) { try { await VerifyAsync(target,file,token); progress?.Report(file.Name+" verified"); return; } catch(InvalidDataException) { } }
        var drive=new DriveInfo(Path.GetPathRoot(directory)!);
        if(drive.AvailableFreeSpace<file.Bytes+100_000_000) throw new IOException("Not enough disk space for this model.");
        var temporary=SafeFiles.Resolve(directory,file.Name+".partial");
        // Fixed publisher URLs contain only public artifact identifiers, never meeting data.
        using var http=new HttpClient {Timeout=TimeSpan.FromHours(4)};
        using var response=await http.GetAsync($"https://huggingface.co/{repository}/resolve/{revision}/{file.Name}",HttpCompletionOption.ResponseHeadersRead,token);
        response.EnsureSuccessStatusCode();
        if(response.RequestMessage?.RequestUri?.Scheme!="https" || response.Content.Headers.ContentLength is long length && length!=file.Bytes) throw new InvalidDataException("Unexpected model response.");
        await using var source=await response.Content.ReadAsStreamAsync(token);
        try
        {
            if(File.Exists(temporary))File.Delete(temporary);
            await using(var destination=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None,131072,true))
            {
                var buffer=new byte[131072]; long received=0;var clock=System.Diagnostics.Stopwatch.StartNew();long lastReport=0;
                while(true)
                {
                    int count=await source.ReadAsync(buffer,token); if(count==0) break;
                    received=checked(received+count); if(received>file.Bytes) throw new InvalidDataException("Oversized model download.");
                    await destination.WriteAsync(buffer.AsMemory(0,count),token);
                    if(clock.ElapsedMilliseconds-lastReport>=100||received==file.Bytes)
                    {progress?.Report($"Downloading {file.Name}: {received/1_000_000:N0} / {file.Bytes/1_000_000:N0} MB");lastReport=clock.ElapsedMilliseconds;}
                }
                if(received!=file.Bytes) throw new InvalidDataException("Incomplete model download.");
                destination.Flush(true);
            }
            progress?.Report("Verifying "+file.Name); await VerifyAsync(temporary,file,token);
            File.Move(temporary,target,true);
        }
        finally { if(File.Exists(temporary)) File.Delete(temporary); }
    }
}
