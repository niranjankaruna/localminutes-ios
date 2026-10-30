using System.Buffers.Binary;
using System.Text;
using System.Text.Json;
using LocalMinutes.Core;
using Xunit;

namespace LocalMinutes.Tests;

public sealed class CoreTests : IDisposable
{
    private readonly string root=Path.Combine(AppContext.BaseDirectory,"test-data",Guid.NewGuid().ToString("N"));
    public CoreTests()=>Directory.CreateDirectory(root);
    private PortableProfile Profile(string name)=>new(Path.Combine(root,name));
    private static Meeting NewMeeting(string title="Review")=>new(WireJson.NewId(),title,1_700_000_000,"completed",0);
    [Fact] public void IdentitySurvivesRestartButRunIdentityChanges()
    {
        string device,run;
        using(var profile=Profile("identity")){device=profile.Identity.ReplicaId;run=profile.RunId;Assert.Throws<IOException>(()=>Profile("identity"));}
        using var next=Profile("identity");Assert.Equal(device,next.Identity.ReplicaId);Assert.NotEqual(run,next.RunId);
    }
    [Fact] public void NotesRejectStaleSavesAndKeepAnExplicitEmptyValue()
    {
        using var profile=Profile("notes");using var store=new MeetingStore(profile.DatabasePath);var meeting=NewMeeting();store.Create(meeting);
        var note=store.SaveNote(meeting.Id,"first",0);Assert.Throws<InvalidOperationException>(()=>store.SaveNote(meeting.Id,"stale",0));
        store.SaveNote(meeting.Id,"",note.EditRevision);Assert.Equal("",store.Note(meeting.Id)!.Text);
        Assert.Equal(2,store.Note(meeting.Id)!.EditRevision);
    }
    [Fact] public void CafRoundTripsExactSignedSamplesAndSeeksAcrossSegments()
    {
        var directory=Path.Combine(root,"caf");var pcm=new byte[2_000_000];new Random(2).NextBytes(pcm);
        using(var writer=new CafCaptureWriter(directory,WireJson.NewId())){writer.Append(pcm);Assert.Equal(1_000_000,writer.Finish().TotalFrames);}
        using var timeline=new CafTimelineStream(directory);Assert.Equal(pcm.Length,timeline.Length);
        var output=new byte[pcm.Length];timeline.ReadExactly(output);Assert.Equal(pcm,output);
        timeline.Seek(1_919_998,SeekOrigin.Begin);var crossing=new byte[6];timeline.ReadExactly(crossing);Assert.Equal(pcm.AsSpan(1_919_998,6).ToArray(),crossing);
    }
    [Fact] public void CafRejectsFloatOrTruncatedAudio()
    {
        var path=Path.Combine(root,"format.caf");CafAudio.Write(path,new byte[128]);var bytes=File.ReadAllBytes(path);
        BinaryPrimitives.WriteUInt32BigEndian(bytes.AsSpan(32),3);using var invalid=new MemoryStream(bytes);Assert.Throws<InvalidDataException>(()=>CafAudio.Inspect(invalid));
        using var truncated=new MemoryStream(bytes[..^2]);Assert.Throws<InvalidDataException>(()=>CafAudio.Inspect(truncated));
    }
    [Theory]
    [InlineData("../outside")][InlineData("a/../../outside")][InlineData("C:/outside")][InlineData("a\\b")][InlineData("a/CON.txt")][InlineData("a/file.")][InlineData("a//b")]
    public void RejectsUnsafePaths(string path)=>Assert.Throws<InvalidDataException>(()=>SafeFiles.Resolve(root,path));
    [Fact] public void ExchangeSenderWinsOlderEditsKeepsReceiverOnlyAndNeverIncludesModels()
    {
        using var sender=Profile("sender");using var receiver=Profile("receiver");using var a=new MeetingStore(sender.DatabasePath);using var b=new MeetingStore(receiver.DatabasePath);
        var common=NewMeeting();a.Create(common);b.Create(common);var extra=NewMeeting("Only on receiver");b.Create(extra);
        a.SaveNote(common.Id,"sender",0);b.SaveNote(common.Id,"receiver",0);b.SaveNote(common.Id,"newer receiver",1);a.Rename(common.Id,"Sender title");
        File.WriteAllText(Path.Combine(sender.ModelsRoot,"private.gguf"),"not transferable");
        var transfer=Path.Combine(root,"send");var manifest=LibraryExchange.Create(sender,a,transfer);Assert.DoesNotContain(manifest.Files,x=>x.RelativePath.Contains("gguf"));
        var receipt=LibraryExchange.Apply(receiver,b,transfer);Assert.False(receipt.AlreadyApplied);
        Assert.Equal("sender",b.Note(common.Id)!.Text);Assert.Equal("Sender title",b.Meetings().Single(x=>x.Id==common.Id).Title);Assert.Contains(b.Meetings(),x=>x.Id==extra.Id);
        Assert.True(LibraryExchange.Apply(receiver,b,transfer).AlreadyApplied);Assert.Equal(2,b.Meetings().Count);
        Assert.Throws<InvalidOperationException>(()=>b.SaveNote(common.Id,"stale editor",2));
    }
    [Fact] public void DeletionsAreNotPropagatedAndCopyBackRestoresDeletedMeeting()
    {
        using var left=Profile("left");using var right=Profile("right");using var a=new MeetingStore(left.DatabasePath);using var b=new MeetingStore(right.DatabasePath);
        var meeting=NewMeeting();a.Create(meeting);var first=Path.Combine(root,"first");LibraryExchange.Create(left,a,first);LibraryExchange.Apply(right,b,first);
        a.Delete(meeting.Id);var empty=Path.Combine(root,"empty");LibraryExchange.Create(left,a,empty);LibraryExchange.Apply(right,b,empty);Assert.Single(b.Meetings());
        var back=Path.Combine(root,"back");LibraryExchange.Create(right,b,back);LibraryExchange.Apply(left,a,back);Assert.Single(a.Meetings());
    }
    [Fact] public void GeneratedOriginalsRemainImmutableWhileSenderEditsWin()
    {
        using var left=Profile("left");using var right=Profile("right");using var a=new MeetingStore(left.DatabasePath);using var b=new MeetingStore(right.DatabasePath);
        var meeting=NewMeeting();a.Create(meeting);b.Create(meeting);var document=new GeneratedDocument(WireJson.NewId(),meeting.Id,"summary","{\"schema_version\":2}",null,"Original",0,"model","prompt",100,100);
        a.CreateDocument(document);b.CreateDocument(document);a.SaveDocumentEdit(document,"Sender edit");b.SaveDocumentEdit(document,"Receiver edit");
        var transfer=Path.Combine(root,"docs");LibraryExchange.Create(left,a,transfer);LibraryExchange.Apply(right,b,transfer);
        Assert.Equal("Sender edit",b.PreferredSummary(meeting.Id)!.EditedText);Assert.Equal(document.OriginalJson,b.PreferredSummary(meeting.Id)!.OriginalJson);
    }
    [Fact] public void ExportIncludesMoreThanOneThousandSavedAnswers()
    {
        using var profile=Profile("history");using var store=new MeetingStore(profile.DatabasePath);var meeting=NewMeeting();store.Create(meeting);
        for(int i=0;i<1002;i++)store.CreateDocument(new(WireJson.NewId(),meeting.Id,"question_answer","{}","Question "+i,"Answer",0,"m","p",100+i,100+i));
        var path=Path.Combine(root,"history-transfer");LibraryExchange.Create(profile,store,path);
        Assert.Equal(1002,LibraryExchange.Rows(path).Count(x=>x.Type=="document"));
    }
    [Fact] public void CorruptTransferDoesNotMutateReceiver()
    {
        using var sender=Profile("sender");using var receiver=Profile("receiver");using var a=new MeetingStore(sender.DatabasePath);using var b=new MeetingStore(receiver.DatabasePath);a.Create(NewMeeting());
        var path=Path.Combine(root,"corrupt");LibraryExchange.Create(sender,a,path);File.AppendAllText(Path.Combine(path,"records.jsonl"),"tampered");
        Assert.Throws<InvalidDataException>(()=>LibraryExchange.Apply(receiver,b,path));Assert.Empty(b.Meetings());
    }
    [Fact] public void SameImmutableTranscriptIdWithDifferentTextRollsBackWholeImport()
    {
        using var sender=Profile("sender");using var receiver=Profile("receiver");using var a=new MeetingStore(sender.DatabasePath);using var b=new MeetingStore(receiver.DatabasePath);var meeting=NewMeeting();a.Create(meeting);b.Create(meeting);
        var segment=new TranscriptSegment(WireJson.NewId(),meeting.Id,0,0,16000,"Original","m");a.Append(segment);b.Append(segment with{Text="Changed"});a.Rename(meeting.Id,"Should roll back");
        var path=Path.Combine(root,"collision");LibraryExchange.Create(sender,a,path);Assert.Throws<InvalidDataException>(()=>LibraryExchange.Apply(receiver,b,path));Assert.Equal(meeting.Title,b.Meetings()[0].Title);
    }
    [Fact] public void SnapshotOwnsMediaAfterOriginalIsDeleted()
    {
        using var profile=Profile("source");using var store=new MeetingStore(profile.DatabasePath);var meeting=NewMeeting();store.Create(meeting);
        using(var writer=new CafCaptureWriter(profile.MeetingDirectory(meeting.Id),meeting.Id)){writer.Append(new byte[3200]);writer.Finish();}store.FinishRecording(meeting.Id,1600);
        var path=Path.Combine(root,"snapshot");LibraryExchange.Create(profile,store,path);File.Delete(Path.Combine(profile.MeetingDirectory(meeting.Id),"segment-000000.caf"));
        Assert.Contains(LibraryExchange.Validate(path).Files,x=>x.RelativePath.EndsWith(".caf"));
    }
    [Fact] public void InvalidModelCitationsNeverCreateAResult()
    {
        using var profile=Profile("model");var models=new ModelManager(profile);var meeting=NewMeeting();var source=new List<TranscriptSegment>{new(WireJson.NewId(),meeting.Id,0,0,16000,"Source","m")};
        Assert.Throws<InvalidDataException>(()=>LocalIntelligence.ValidateOutput(meeting,null,models.SummaryModels[0],source,"{\"overview\":{\"text\":\"Bad\",\"source_ids\":[99]},\"bullets\":[{\"text\":\"Bad\",\"source_ids\":[99]}]}"));
        Assert.ThrowsAny<JsonException>(()=>LocalIntelligence.ValidateOutput(meeting,null,models.SummaryModels[0],source,"{\"overview\":"));
    }
    [Fact] public void UncommittedImportJournalRestoresFilesAndRemovesOnlyAddedFiles()
    {
        using var profile=Profile("journal");using var store=new MeetingStore(profile.DatabasePath);var meeting=NewMeeting();store.Create(meeting);
        var transfer=WireJson.NewId();var relative=$"Meetings/{meeting.Id}/capture-manifest.json";var added=$"Meetings/{meeting.Id}/segment-000000.caf";
        var directory=profile.MeetingDirectory(meeting.Id);Directory.CreateDirectory(directory);File.WriteAllText(Path.Combine(directory,"capture-manifest.json"),"changed");File.WriteAllText(Path.Combine(directory,"segment-000000.caf"),"new");
        var backup=Path.Combine(profile.Root,"rollback",transfer,"Meetings",meeting.Id);Directory.CreateDirectory(backup);File.WriteAllText(Path.Combine(backup,"capture-manifest.json"),"original");
        File.WriteAllBytes(Path.Combine(profile.Root,"pending-import.json"),JsonSerializer.SerializeToUtf8Bytes(new{transferId=transfer,digest=new string('a',64),replaced=new[]{relative},added=new[]{added}},WireJson.Options));
        LibraryExchange.Recover(profile,store);Assert.Equal("original",File.ReadAllText(Path.Combine(directory,"capture-manifest.json")));Assert.False(File.Exists(Path.Combine(directory,"segment-000000.caf")));Assert.False(File.Exists(Path.Combine(profile.Root,"pending-import.json")));
    }
    [Fact] public void LocalDeletionRemovesOriginalAudioAndMetadata()
    {
        using var profile=Profile("delete");using var store=new MeetingStore(profile.DatabasePath);var meeting=NewMeeting();store.Create(meeting);
        using(var writer=new CafCaptureWriter(profile.MeetingDirectory(meeting.Id),meeting.Id)){writer.Append(new byte[100]);writer.Finish();}
        MeetingFiles.Delete(profile,store,meeting.Id);Assert.Empty(store.Meetings());Assert.False(Directory.Exists(profile.MeetingDirectory(meeting.Id)));MeetingFiles.Recover(profile,store);
    }
    [Fact] public void StartupReconcilesOnlyClosedAudioFromAbandonedRecording()
    {
        using var profile=Profile("crash");using var store=new MeetingStore(profile.DatabasePath);var meeting=NewMeeting() with{RecordingState="recording"};store.Create(meeting);
        using(var writer=new CafCaptureWriter(profile.MeetingDirectory(meeting.Id),meeting.Id)){writer.Append(new byte[1_920_000]);}
        Assert.Equal(1,RecordingService.ReconcileInterrupted(profile,store));Assert.Equal("interrupted",store.Meetings()[0].RecordingState);Assert.Equal(960000,store.Meetings()[0].CapturedSampleCount);
    }
    [Fact] public void CliFooterIsRemovedWithoutRepairingInvalidJson()
    {
        Assert.Equal("{\"ok\":true}",LocalIntelligence.CompletionPayload("{\"ok\":true} [end of text]\n\n"));
        Assert.Equal("{\"ok\":",LocalIntelligence.CompletionPayload("{\"ok\": [end of text]"));
        Assert.Equal("{\"text\":\"[end of text]\"}",LocalIntelligence.CompletionPayload("{\"text\":\"[end of text]\"}"));
    }
    public void Dispose()
    {
        var owned=Path.GetFullPath(root);var parent=Path.Combine(AppContext.BaseDirectory,"test-data")+Path.DirectorySeparatorChar;
        if(!owned.StartsWith(parent,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Test cleanup boundary.");
        if(Directory.Exists(owned))Directory.Delete(owned,true);
    }
}
