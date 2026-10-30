using NAudio.Wave;
using SherpaOnnx;
using System.Threading.Channels;

namespace LocalMinutes.Core;

public sealed record Microphone(int Index,string Name);

public sealed class RecordingService
{
    private readonly PortableProfile profile;
    private readonly MeetingStore store;
    private readonly ModelManager models;
    private WaveInEvent? microphone;
    private Channel<byte[]>? queue;
    private Task? work;
    private Exception? captureError;
    private string? meetingId;
    private long frames;
    private DateTime started;
    public string? MeetingId=>meetingId;
    public bool IsActive=>microphone!=null;
    public TimeSpan Elapsed=>IsActive?DateTime.UtcNow-started:TimeSpan.Zero;
    public event Action<string>? TranscriptUpdated;
    public event Action<string>? Interrupted;

    public RecordingService(PortableProfile profile,MeetingStore store,ModelManager models)
    { this.profile=profile; this.store=store; this.models=models; }
    public static List<Microphone> Microphones()=>Enumerable.Range(0,WaveInEvent.DeviceCount).Select(i=>new Microphone(i,WaveInEvent.GetCapabilities(i).ProductName)).ToList();

    public async Task StartAsync(int device,CancellationToken cancellationToken=default)
    {
        if(IsActive) throw new InvalidOperationException("A recording is already active.");
        await models.VerifySpeechAsync(cancellationToken);
        // Initialization happens before capture starts. The model is owned by the processing worker until drained.
        var recognizer=await Task.Run(()=>OpenRecognizer(models.SpeechDirectory),cancellationToken);
        await StartCaptureAsync(device,recognizer);
    }

    public static OfflineRecognizer OpenRecognizer(string modelDirectory)
    {
        var config=new OfflineRecognizerConfig();
        config.FeatConfig.SampleRate=16000; config.FeatConfig.FeatureDim=80;
        config.ModelConfig.Transducer.Encoder=Path.Combine(modelDirectory,"encoder.int8.onnx");
        config.ModelConfig.Transducer.Decoder=Path.Combine(modelDirectory,"decoder.int8.onnx");
        config.ModelConfig.Transducer.Joiner=Path.Combine(modelDirectory,"joiner.int8.onnx");
        config.ModelConfig.Tokens=Path.Combine(modelDirectory,"tokens.txt");
        config.ModelConfig.ModelType="nemo_transducer"; config.ModelConfig.Provider="cpu"; config.ModelConfig.NumThreads=4;
        return new OfflineRecognizer(config);
    }

    private async Task StartCaptureAsync(int device,OfflineRecognizer recognizer)
    {
        meetingId=WireJson.NewId(); frames=0; captureError=null;
        CafCaptureWriter writer;
        try
        {
            store.Create(new(meetingId,"Meeting "+DateTime.Now.ToString("dd MMM HH:mm"),WireJson.Now,"recording",0));
            writer=new CafCaptureWriter(profile.MeetingDirectory(meetingId),meetingId);
        }
        catch{recognizer.Dispose();store.FinishRecording(meetingId,0,"failed");throw;}
        queue=Channel.CreateBounded<byte[]>(new BoundedChannelOptions(600){SingleReader=true,SingleWriter=true,FullMode=BoundedChannelFullMode.Wait});
        var ownedQueue=queue; var ownedId=meetingId;
        // The worker writes originals before recognition. Queue exhaustion stops capture instead of dropping samples.
        work=Task.Run(async ()=>
        {
            using(recognizer) using(writer)
            {
                using var window=new MemoryStream(); int sequence=0;
                try
                {
                    await foreach(var bytes in ownedQueue.Reader.ReadAllAsync())
                    {
                        writer.Append(bytes); frames+=bytes.Length/2; window.Write(bytes);
                        if(window.Length>=160_000)
                        {
                            try { if(captureError==null)Decode(window,recognizer,ownedId,sequence++,frames); }
                            catch(Exception error) { captureError=error;try{microphone?.StopRecording();}catch{} }
                            window.SetLength(0);
                        }
                    }
                    if(window.Length>0&&captureError==null) Decode(window,recognizer,ownedId,sequence,frames);
                }
                catch(Exception error) { captureError=error; ownedQueue.Writer.TryComplete(); try { microphone?.StopRecording(); } catch { } }
                finally
                {
                    var manifest=writer.Finish(); store.FinishRecording(ownedId,manifest.TotalFrames,captureError==null?"completed":"interrupted");
                    if(captureError!=null)Interrupted?.Invoke("Recording stopped. Saved audio is retained; transcription may be incomplete.");
                }
            }
        });
        try
        {
            microphone=new WaveInEvent {DeviceNumber=device,WaveFormat=new WaveFormat(16000,16,1),BufferMilliseconds=100};
            microphone.DataAvailable+=(_,args)=>
            {
                var bytes=args.Buffer.AsSpan(0,args.BytesRecorded).ToArray();
                if(!ownedQueue.Writer.TryWrite(bytes)) { captureError=new IOException("Audio processing could not keep up. Recording stopped to protect saved audio."); microphone?.StopRecording(); }
            };
            microphone.RecordingStopped+=(_,args)=> { captureError??=args.Exception; ownedQueue.Writer.TryComplete(); };
            started=DateTime.UtcNow; microphone.StartRecording();
        }
        catch
        {
            captureError=new IOException("Microphone could not start."); ownedQueue.Writer.TryComplete();
            await work; microphone?.Dispose(); microphone=null; throw;
        }
    }
    private void Decode(MemoryStream window,OfflineRecognizer recognizer,string id,int sequence,long end)
    {
        var bytes=window.ToArray(); var samples=new float[bytes.Length/2];
        for(int i=0;i<samples.Length;i++) samples[i]=System.Buffers.Binary.BinaryPrimitives.ReadInt16LittleEndian(bytes.AsSpan(i*2,2))/32768f;
        using var stream=recognizer.CreateStream(); stream.AcceptWaveform(16000,samples); recognizer.Decode(stream);
        string text=stream.Result.Text.Trim();
        if(text.Length==0) return;
        store.Append(new(WireJson.NewId(),id,sequence,end-samples.Length,end,text,"parakeet-v3-onnx@"+ModelManager.SpeechRevision));
        TranscriptUpdated?.Invoke(text);
    }
    public async Task StopAsync()
    {
        if(microphone==null) return;
        try {microphone.StopRecording();if(work!=null) await work;}
        finally {microphone.Dispose();microphone=null;queue=null;work=null;}
        if(captureError!=null) throw new IOException("Recording saved with an interruption: "+captureError.Message,captureError);
    }

    public static int ReconcileInterrupted(PortableProfile profile,MeetingStore store)
    {
        int count=0;
        foreach(var meeting in store.Meetings().Where(x=>x.RecordingState=="recording"))
        {
            long samples=meeting.CapturedSampleCount;
            try {using var audio=new CafTimelineStream(profile.MeetingDirectory(meeting.Id));samples=Math.Max(samples,audio.Length/2);}
            catch(Exception error)when(error is IOException or System.Text.Json.JsonException){ }
            // Unclosed CAF tails remain untouched for recovery; only independently validated closed audio is counted.
            store.FinishRecording(meeting.Id,samples,"interrupted");count++;
        }
        return count;
    }
}

public sealed class AudioPlayback : IDisposable
{
    private WaveOutEvent? output;
    private RawSourceWaveStream? source;
    public void Play(string directory,long startSample=0)
    {
        Stop(); var timeline=new CafTimelineStream(directory);
        timeline.Position=Math.Clamp(startSample*2,0,timeline.Length);
        source=new RawSourceWaveStream(timeline,new WaveFormat(16000,16,1));
        output=new WaveOutEvent(); output.Init(source); output.Play();
    }
    public void Stop() { output?.Stop(); output?.Dispose(); output=null; source?.Dispose(); source=null; }
    public void Dispose()=>Stop();
}
