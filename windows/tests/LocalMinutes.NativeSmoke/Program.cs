using LocalMinutes.Core;
using NAudio.Wave;
using Makaretu.Dns;

try
{
if(args.Length==1&&args[0]=="discovery")
{
    var id=WireJson.NewId();var seen=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
    using var browser=new MulticastService();
    browser.AnswerReceived+=(_,message)=>{if(message.Message.Answers.OfType<PTRRecord>().Any(x=>x.DomainName.ToString().Contains(id,StringComparison.OrdinalIgnoreCase)))seen.TrySetResult();};
    browser.Start();using var advertisement=new LocalAdvertisement(id,49190);
    using var deadline=new CancellationTokenSource(TimeSpan.FromSeconds(12));
    while(!seen.Task.IsCompleted){browser.SendQuery("_localminutes._tcp.local");await Task.WhenAny(seen.Task,Task.Delay(500,deadline.Token));deadline.Token.ThrowIfCancellationRequested();}
    Console.WriteLine("PASS: local DNS-SD query discovered this app's advertised instance.");return 0;
}
if(args.Length==3&&args[0]=="speech")
{
    using var speechProfile=new PortableProfile(Path.GetFullPath(args[1]));var speechModels=new ModelManager(speechProfile);
    using var deadline=new CancellationTokenSource(TimeSpan.FromMinutes(20));
    Console.WriteLine("Downloading or verifying the pinned Parakeet model pack…");
    await speechModels.DownloadSpeechAsync(null,deadline.Token);await speechModels.VerifySpeechAsync(deadline.Token);
    using var reader=new WaveFileReader(Path.GetFullPath(args[2]));
    if(reader.WaveFormat.SampleRate!=16000||reader.WaveFormat.BitsPerSample!=16||reader.WaveFormat.Channels!=1)throw new InvalidDataException("Expected a synthetic 16 kHz mono PCM fixture.");
    var pcm=new byte[checked((int)reader.Length)];reader.ReadExactly(pcm);var samples=new float[pcm.Length/2];
    for(int i=0;i<samples.Length;i++)samples[i]=System.Buffers.Binary.BinaryPrimitives.ReadInt16LittleEndian(pcm.AsSpan(i*2,2))/32768f;
    using var recognizer=RecordingService.OpenRecognizer(speechModels.SpeechDirectory);using var stream=recognizer.CreateStream();stream.AcceptWaveform(16000,samples);recognizer.Decode(stream);
    var transcript=stream.Result.Text;Console.WriteLine(transcript);
    if(!transcript.Contains("Friday",StringComparison.OrdinalIgnoreCase)||!transcript.Contains("Thursday",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Synthetic speech was not recognized correctly.");
    Console.WriteLine("PASS: actual pinned Parakeet native runtime recognized the synthetic speech fixture.");return 0;
}
if(args.Length is not (3 or 4))throw new ArgumentException("Usage: NativeSmoke <verified-model.gguf> <llama-runtime-folder> <test-data-parent> [--gpu]");
var data=Path.Combine(Path.GetFullPath(args[2]),Guid.NewGuid().ToString("N"));
using var profile=new PortableProfile(data);using var store=new MeetingStore(profile.DatabasePath);var models=new ModelManager(profile);
var model=models.SummaryModels.Single(x=>x.Id=="qwen2.5-0.5b-instruct-q4_k_m");Directory.CreateDirectory(Path.GetDirectoryName(models.SummaryPath(model))!);
File.Copy(Path.GetFullPath(args[0]),models.SummaryPath(model));await models.VerifySummaryAsync(model);models.Select(model);
var meeting=new Meeting(WireJson.NewId(),"Synthetic release review",1700000000,"completed",64000);store.Create(meeting);
var rows=new[]{"Maya said the release date is Friday, provided the audio recovery tests pass.","Leo will run the recovery tests on Thursday and report the results to Maya.","The team agreed to keep microphone-only recording in the first Windows release.","The customer confirmed that syncing should copy updates without deleting meetings on the receiving device."};
for(int i=0;i<rows.Length;i++)store.Append(new(WireJson.NewId(),meeting.Id,i,i*16000,(i+1)*16000,rows[i],"synthetic-fixture"));
var engine=new LocalIntelligence(profile,store,models,Path.GetFullPath(args[1]));
engine.UseGpu=args.Length==4&&args[3]=="--gpu";
if(engine.UseGpu&&!engine.GpuRuntimeAvailable)throw new InvalidOperationException("GPU smoke test requires the CUDA runtime.");
using var timeout=new CancellationTokenSource(TimeSpan.FromMinutes(5));
var summary=await engine.GenerateAsync(meeting,null,new Progress<string>(Console.WriteLine),timeout.Token);
if(!summary.EditedText.Contains("Overview")||!summary.EditedText.Contains("Minutes of Meetings"))throw new InvalidDataException("Missing summary sections.");
Console.WriteLine(summary.EditedText);
var answer=await engine.GenerateAsync(meeting,"When will Leo run the recovery tests?",new Progress<string>(Console.WriteLine),timeout.Token);
Console.WriteLine(answer.EditedText);
if(!answer.EditedText.Contains("Thursday",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("The synthetic answer did not select the supported evidence.");
Console.WriteLine("PASS: actual pinned llama.cpp model generated and persisted a summary and grounded answer.");
File.Delete(models.SummaryPath(model));
return 0;
}
catch(Exception error)
{
    Console.Error.WriteLine(error);
    return 1;
}
