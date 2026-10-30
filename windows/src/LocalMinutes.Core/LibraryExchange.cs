using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace LocalMinutes.Core;

public sealed record ExchangeFile(string RelativePath,long ByteCount,string Sha256);
public sealed record ExchangeManifest(int SchemaVersion,string TransferId,string SourceId,List<ExchangeFile> Files);
public sealed record SummaryPreference(string MeetingId,string DocumentId);
public sealed record ExchangeRow(string Type,JsonElement Value);
public sealed record ImportReceipt(int Meetings,int Notes,int Documents,bool AlreadyApplied);
internal sealed record ApplyJournal(string TransferId,string Digest,List<string> Replaced,List<string> Added);

/// <summary>Platform-neutral, bounded JSON-lines records and hash-verified original media. No model roots are enumerated.</summary>
public static partial class LibraryExchange
{
    public const int Version=1;
    public const int MaximumRecordBytes=8*1024*1024;
    public const int MaximumManifestBytes=16*1024*1024;
    [GeneratedRegex(@"^Meetings/[0-9A-Fa-f-]{36}/(?:capture-manifest\.json|recovery-report\.json|transcription-replay\.json|(?:RecoveryQuarantine/)?segment-[0-9]{6}\.caf)$",RegexOptions.CultureInvariant)]
    private static partial Regex AllowedMedia();

    public static bool Allowed(string relative)=>relative=="records.jsonl" || AllowedMedia().IsMatch(relative) && Guid.TryParseExact(relative.Split('/')[1],"D",out _);

    public static ExchangeManifest Create(PortableProfile profile,MeetingStore store,string destination,CancellationToken cancellationToken=default)
    {
        if(Directory.Exists(destination)) throw new IOException("Export destination already exists.");
        Directory.CreateDirectory(destination); SafeFiles.RequireRegularTree(destination);
        return store.Exclusive(()=>
        {
            var meetings=store.Meetings();
            if(meetings.Any(x=>x.RecordingState=="recording")) throw new InvalidOperationException("Stop recording before copying your library.");
            var recordPath=Path.Combine(destination,"records.jsonl");
            using(var stream=new FileStream(recordPath,FileMode.CreateNew,FileAccess.Write,FileShare.None))
            {
                foreach(var meeting in meetings)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    WriteRow(stream,"meeting",meeting);
                    foreach(var segment in store.Transcript(meeting.Id)) WriteRow(stream,"segment",segment);
                    if(store.Note(meeting.Id) is { } note) WriteRow(stream,"note",note);
                    foreach(var document in store.Documents(meeting.Id)) WriteRow(stream,"document",document);
                    if(store.PreferredSummary(meeting.Id) is { } summary) WriteRow(stream,"preference",new SummaryPreference(meeting.Id,summary.Id));
                }
                foreach(var pin in store.Pins()) WriteRow(stream,"pin",pin);
                stream.Flush(true);
            }
            foreach(var meeting in meetings)
            {
                var directory=profile.MeetingDirectory(meeting.Id);
                if(!Directory.Exists(directory)) continue;
                CopyMedia(directory,destination,$"Meetings/{meeting.Id}",cancellationToken);
            }
            return Seal(destination,profile.Identity.ReplicaId,cancellationToken);
        });
    }
    internal static void CopyMedia(string source,string destination,string prefix,CancellationToken cancellationToken=default)
    {
        SafeFiles.RequireRegularTree(source);
        foreach(var entry in Directory.EnumerateFileSystemEntries(source))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var attributes=File.GetAttributes(entry);
            if((attributes&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked media is not permitted.");
            var relative=prefix+"/"+Path.GetFileName(entry);
            if((attributes&FileAttributes.Directory)!=0)
            {
                if(Path.GetFileName(entry)=="RecoveryQuarantine") CopyMedia(entry,destination,relative,cancellationToken);
                continue;
            }
            if(!Allowed(relative)) continue;
            var output=SafeFiles.Resolve(destination,relative); Directory.CreateDirectory(Path.GetDirectoryName(output)!);
            using var input=File.OpenRead(entry); using var target=new FileStream(output,FileMode.CreateNew,FileAccess.Write,FileShare.None);
            SafeFiles.RequireSingleLink(input);var buffer=new byte[131072];int count;
            while((count=input.Read(buffer))>0){cancellationToken.ThrowIfCancellationRequested();target.Write(buffer,0,count);}target.Flush(true);
        }
    }
    internal static void WriteRow<T>(Stream stream,string type,T value)
    {
        var data=JsonSerializer.SerializeToUtf8Bytes(new {type,value},WireJson.Options);
        if(data.Length>MaximumRecordBytes) throw new InvalidDataException("A record exceeds the exchange size limit.");
        stream.Write(data); stream.WriteByte(10);
    }
    public static ExchangeManifest Seal(string directory,string sourceId,CancellationToken cancellationToken=default)
    {
        var files=new List<ExchangeFile>();
        foreach(var path in Directory.EnumerateFiles(directory,"*",SearchOption.AllDirectories).Order(StringComparer.Ordinal))
        {
            var relative=Path.GetRelativePath(directory,path).Replace('\\','/');
            if(!Allowed(relative)) throw new InvalidDataException("Unexpected file in transfer.");
            _=SafeFiles.Resolve(directory,relative);
            using var stream=File.OpenRead(path);
            using var hash=IncrementalHash.CreateHash(HashAlgorithmName.SHA256);var buffer=new byte[131072];int count;
            while((count=stream.Read(buffer))>0){cancellationToken.ThrowIfCancellationRequested();hash.AppendData(buffer,0,count);}
            files.Add(new(relative,stream.Length,Convert.ToHexStringLower(hash.GetHashAndReset())));
        }
        var manifest=new ExchangeManifest(Version,WireJson.NewId(),WireJson.Id(sourceId),files);
        var bytes=JsonSerializer.SerializeToUtf8Bytes(manifest,WireJson.Options);
        if(bytes.Length>MaximumManifestBytes) throw new InvalidDataException("Transfer manifest is too large.");
        SafeFiles.WriteAtomic(Path.Combine(directory,"manifest.json"),bytes);
        return manifest;
    }
    public static ExchangeManifest Validate(string directory)
    {
        SafeFiles.RequireRegularTree(directory);
        var manifestPath=SafeFiles.Resolve(directory,"manifest.json");
        if(new FileInfo(manifestPath).Length>MaximumManifestBytes) throw new InvalidDataException("Oversized transfer manifest.");
        var manifest=JsonSerializer.Deserialize<ExchangeManifest>(File.ReadAllBytes(manifestPath),WireJson.Options) ?? throw new InvalidDataException("Invalid transfer manifest.");
        if(manifest.SchemaVersion!=Version || WireJson.Id(manifest.TransferId)!=manifest.TransferId || WireJson.Id(manifest.SourceId)!=manifest.SourceId || manifest.Files.Count==0 || manifest.Files.Count>100_000) throw new InvalidDataException("Unsupported transfer.");
        var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var file in manifest.Files)
        {
            if(!Allowed(file.RelativePath) || !names.Add(file.RelativePath) || file.ByteCount<0 || file.RelativePath.EndsWith(".json",StringComparison.Ordinal)&&file.ByteCount>MaximumManifestBytes || file.Sha256.Length!=64 || !file.Sha256.All(c=>char.IsAsciiHexDigit(c))) throw new InvalidDataException("Invalid transfer entry.");
            var path=SafeFiles.Resolve(directory,file.RelativePath);
            using var input=File.OpenRead(path);
            SafeFiles.RequireSingleLink(input);
            if(input.Length!=file.ByteCount || Convert.ToHexStringLower(SHA256.HashData(input))!=file.Sha256) throw new InvalidDataException("Transfer checksum mismatch.");
        }
        if(!names.Contains("records.jsonl")) throw new InvalidDataException("Transfer records are missing.");
        foreach(var row in Rows(directory)) ValidateRow(row);
        return manifest;
    }
    public static IEnumerable<ExchangeRow> Rows(string directory)
    {
        using var stream=File.OpenRead(SafeFiles.Resolve(directory,"records.jsonl"));
        using var line=new MemoryStream(); var buffer=new byte[65536]; int count;
        while((count=stream.Read(buffer))>0)
        {
            for(int i=0;i<count;i++)
            {
                if(buffer[i]==10)
                {
                    if(line.Length==0) throw new InvalidDataException("Empty exchange record.");
                    var row=JsonSerializer.Deserialize<ExchangeRow>(line.GetBuffer().AsSpan(0,(int)line.Length),WireJson.Options) ?? throw new InvalidDataException("Invalid record.");
                    line.SetLength(0); yield return row;
                }
                else { if(line.Length>=MaximumRecordBytes) throw new InvalidDataException("Oversized record."); line.WriteByte(buffer[i]); }
            }
        }
        if(line.Length!=0) throw new InvalidDataException("Truncated exchange records.");
    }
    private static T Read<T>(ExchangeRow row)=>row.Value.Deserialize<T>(WireJson.Options) ?? throw new InvalidDataException("Missing record value.");
    private static void ValidateRow(ExchangeRow row)
    {
        switch(row.Type)
        {
            case "meeting": var m=Read<Meeting>(row); MeetingStore.ValidateMeeting(m); if(m.RecordingState=="recording") throw new InvalidDataException("Active recording cannot be imported."); break;
            case "segment": MeetingStore.ValidateSegment(Read<TranscriptSegment>(row)); break;
            case "document": MeetingStore.ValidateDocument(Read<GeneratedDocument>(row)); break;
            case "note": var n=Read<ManualNote>(row); _=WireJson.Id(n.MeetingId); if(n.EditRevision<0 || !double.IsFinite(n.ModifiedAt) || Encoding.UTF8.GetByteCount(n.Text)>1_048_576) throw new InvalidDataException("Invalid note."); break;
            case "pin": var p=Read<SpeechPin>(row); _=WireJson.Id(p.MeetingId); using(var json=JsonDocument.Parse(p.SelectionJson)) { if(Encoding.UTF8.GetByteCount(p.SelectionJson)>1_048_576 || json.RootElement.ValueKind!=JsonValueKind.Object) throw new InvalidDataException("Invalid speech provenance."); } break;
            case "preference": var preference=Read<SummaryPreference>(row); _=WireJson.Id(preference.MeetingId); _=WireJson.Id(preference.DocumentId); break;
            default: throw new InvalidDataException("Unsupported exchange record type.");
        }
    }

    public static ImportReceipt Apply(PortableProfile profile,MeetingStore store,string snapshot)
    {
        var manifest=Validate(snapshot);
        using var manifestStream=File.OpenRead(Path.Combine(snapshot,"manifest.json"));
        var digest=Convert.ToHexStringLower(SHA256.HashData(manifestStream));
        return store.Exclusive(()=>
        {
            var existing=store.Scalar("SELECT digest FROM sync_receipts WHERE transfer_id=$id",null,("$id",manifest.TransferId)) as string;
            if(existing!=null) { if(existing!=digest) throw new InvalidDataException("Transfer ID was reused with different data."); return new ImportReceipt(0,0,0,true); }
            if(store.Meetings().Any(m=>m.RecordingState=="recording")) throw new InvalidOperationException("Stop recording before receiving data.");
            // Validate a full import transaction before touching media. The second transaction uses the same exclusive gate.
            using(var preflight=store.BeginTransaction()) { ApplyRows(store,snapshot,preflight); preflight.Rollback(); }
            var rollback=Path.Combine(profile.Root,"rollback",manifest.TransferId); Directory.CreateDirectory(rollback);
            store.BackupTo(Path.Combine(rollback,"before.sqlite"));
            var replacements=new List<string>(); var additions=new List<string>();
            foreach(var file in manifest.Files.Where(f=>f.RelativePath!="records.jsonl"))
            {
                var target=SafeFiles.Resolve(profile.LibraryRoot,file.RelativePath);
                if(File.Exists(target))
                {
                    using var targetStream=File.OpenRead(target);
                    if(Convert.ToHexStringLower(SHA256.HashData(targetStream))==file.Sha256) continue;
                    if(file.RelativePath.EndsWith(".caf",StringComparison.Ordinal)) throw new InvalidDataException("Original audio conflicts with an existing recording.");
                    var backup=SafeFiles.Resolve(rollback,file.RelativePath); Directory.CreateDirectory(Path.GetDirectoryName(backup)!); File.Copy(target,backup,true); replacements.Add(file.RelativePath);
                }
                else additions.Add(file.RelativePath);
            }
            var journal=new ApplyJournal(manifest.TransferId,digest,replacements,additions);
            var journalPath=Path.Combine(profile.Root,"pending-import.json");
            if(File.Exists(journalPath)) throw new IOException("An earlier import needs recovery.");
            SafeFiles.WriteAtomic(journalPath,JsonSerializer.SerializeToUtf8Bytes(journal,WireJson.Options));
            try
            {
                foreach(var relative in replacements.Concat(additions))
                {
                    var target=SafeFiles.Resolve(profile.LibraryRoot,relative); Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                    var source=SafeFiles.Resolve(snapshot,relative);
                    if(relative.EndsWith("/capture-manifest.json",StringComparison.Ordinal) && File.Exists(target)) MergeCapture(source,target);
                    else
                    {
                        var temporary=target+"."+Guid.NewGuid().ToString("N")+".import";
                        using(var input=File.OpenRead(source)) using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {SafeFiles.RequireSingleLink(input);input.CopyTo(output);output.Flush(true);}
                        File.Move(temporary,target,true);
                    }
                }
                // Every manifest's sample ranges must resolve before any metadata is committed.
                foreach(var file in manifest.Files.Where(x=>x.RelativePath.EndsWith("/capture-manifest.json",StringComparison.Ordinal)))
                { using var timeline=new CafTimelineStream(Path.GetDirectoryName(SafeFiles.Resolve(profile.LibraryRoot,file.RelativePath))!); }
                ImportReceipt receipt;
                using(var transaction=store.BeginTransaction())
                {
                    receipt=ApplyRows(store,snapshot,transaction);
                    store.Execute("INSERT INTO sync_receipts VALUES($id,$source,$digest,$time)",transaction,("$id",manifest.TransferId),("$source",manifest.SourceId),("$digest",digest),("$time",WireJson.Now));
                    transaction.Commit(); store.Changed();
                }
                File.Delete(journalPath); return receipt;
            }
            catch { Recover(profile,store); throw; }
        });
    }
    private static ImportReceipt ApplyRows(MeetingStore store,string snapshot,Microsoft.Data.Sqlite.SqliteTransaction transaction)
    {
        int meetings=0,notes=0,documents=0;
        var seen=new HashSet<string>(StringComparer.Ordinal);
        foreach(var row in Rows(snapshot))
        {
            switch(row.Type)
            {
                case "meeting":
                    var m=Read<Meeting>(row); if(!seen.Add("meeting:"+m.Id)) throw new InvalidDataException("Duplicate meeting.");
                    var original=store.Scalar("SELECT created_at FROM meetings WHERE id=$id",transaction,("$id",m.Id));
                    if(original==null) store.InsertMeeting(m,transaction);
                    else
                    {
                        if(Convert.ToDouble(original)!=m.CreatedAt) throw new InvalidDataException("Meeting identity collision.");
                        store.Execute("UPDATE meetings SET title=$title,recording_state=CASE WHEN captured_sample_count<=$samples THEN $state ELSE recording_state END,captured_sample_count=max(captured_sample_count,$samples) WHERE id=$id",transaction,("$title",m.Title),("$state",m.RecordingState),("$samples",m.CapturedSampleCount),("$id",m.Id));
                    }
                    meetings++;break;
                case "segment":
                    var s=Read<TranscriptSegment>(row); if(!seen.Add("segment:"+s.Id)) throw new InvalidDataException("Duplicate transcript segment.");
                    using(var command=store.Command("SELECT meeting_id,sequence,start_sample,end_sample,text,model_revision FROM transcript_segments WHERE id=$id",transaction,("$id",s.Id)))
                    using(var reader=command.ExecuteReader())
                    {
                        if(reader.Read())
                        { if(reader.GetString(0)!=s.MeetingId || reader.GetInt32(1)!=s.Sequence || reader.GetInt64(2)!=s.StartSample || reader.GetInt64(3)!=s.EndSample || reader.GetString(4)!=s.Text || reader.GetString(5)!=s.ModelRevision) throw new InvalidDataException("Original transcript identity collision."); }
                        else { reader.Close(); store.InsertSegment(s,transaction); }
                    }
                    break;
                case "note":
                    var n=Read<ManualNote>(row); if(!seen.Add("note:"+n.MeetingId)) throw new InvalidDataException("Duplicate note.");
                    var revision=Convert.ToInt64(store.Scalar("SELECT edit_revision FROM manual_notes WHERE meeting_id=$id",transaction,("$id",n.MeetingId)) ?? 0);
                    store.UpsertNote(n with {EditRevision=checked(revision+1)},transaction);notes++;break;
                case "document":
                    var d=Read<GeneratedDocument>(row); if(!seen.Add("document:"+d.Id)) throw new InvalidDataException("Duplicate document.");
                    using(var command=store.Command("SELECT meeting_id,kind,original_json,question,model_revision,prompt_version,created_at FROM generated_documents WHERE id=$id",transaction,("$id",d.Id)))
                    using(var reader=command.ExecuteReader())
                    {
                        if(reader.Read())
                        {
                            if(reader.GetString(0)!=d.MeetingId || reader.GetString(1)!=d.Kind || !((byte[])reader[2]).SequenceEqual(Encoding.UTF8.GetBytes(d.OriginalJson)) || (reader.IsDBNull(3)?null:reader.GetString(3))!=d.Question || reader.GetString(4)!=d.ModelRevision || reader.GetString(5)!=d.PromptVersion || reader.GetDouble(6)!=d.CreatedAt) throw new InvalidDataException("Original generated document identity collision.");
                            reader.Close();store.Execute("UPDATE generated_documents SET edited_text=$text,edit_revision=edit_revision+1,modified_at=$time WHERE id=$id",transaction,("$text",d.EditedText),("$time",d.ModifiedAt),("$id",d.Id));
                        }
                        else {reader.Close();store.InsertDocument(d with {EditRevision=0},transaction);}
                    }
                    documents++;break;
                case "preference":
                    var p=Read<SummaryPreference>(row);
                    if(!seen.Add("preference:"+p.MeetingId) || Convert.ToInt64(store.Scalar("SELECT COUNT(*) FROM generated_documents WHERE id=$id AND meeting_id=$meeting AND kind='summary'",transaction,("$id",p.DocumentId),("$meeting",p.MeetingId)))!=1) throw new InvalidDataException("Invalid summary preference.");
                    store.SetPreferred(p.MeetingId,p.DocumentId,transaction);break;
                case "pin":
                    var pin=Read<SpeechPin>(row); if(!seen.Add("pin:"+pin.MeetingId)) throw new InvalidDataException("Duplicate provenance.");
                    var old=store.Scalar("SELECT selection_json FROM meeting_speech_model_pins WHERE meeting_id=$id",transaction,("$id",pin.MeetingId)) as string;
                    if(old!=null && old!=pin.SelectionJson) throw new InvalidDataException("Original speech provenance collision.");
                    store.Execute("INSERT OR IGNORE INTO meeting_speech_model_pins VALUES($id,$json)",transaction,("$id",pin.MeetingId),("$json",pin.SelectionJson));break;
                default: throw new InvalidDataException("Unsupported record.");
            }
        }
        return new(meetings,notes,documents,false);
    }
    private static void MergeCapture(string source,string target)
    {
        var incoming=JsonSerializer.Deserialize<CaptureManifest>(File.ReadAllBytes(source),WireJson.Options)!;
        var existing=JsonSerializer.Deserialize<CaptureManifest>(File.ReadAllBytes(target),WireJson.Options)!;
        if(incoming.SchemaVersion!=1 || existing.SchemaVersion!=1 || incoming.SessionId!=existing.SessionId) throw new InvalidDataException("Capture identity collision.");
        var union=existing.Segments.ToDictionary(x=>x.RelativePath,StringComparer.Ordinal);
        foreach(var segment in incoming.Segments)
        { if(union.TryGetValue(segment.RelativePath,out var old) && old!=segment) throw new InvalidDataException("Capture segment collision."); union[segment.RelativePath]=segment; }
        var segments=union.Values.OrderBy(x=>x.StartFrame).ToList();
        var frames=segments.LastOrDefault() is { } last?checked(last.StartFrame+last.FrameCount):0;
        SafeFiles.WriteAtomic(target,JsonSerializer.SerializeToUtf8Bytes(new CaptureManifest(1,incoming.SessionId,frames,segments),WireJson.Options));
    }
    public static void Recover(PortableProfile profile,MeetingStore store)
    {
        var path=Path.Combine(profile.Root,"pending-import.json"); if(!File.Exists(path)) return;
        var journal=JsonSerializer.Deserialize<ApplyJournal>(File.ReadAllBytes(path),WireJson.Options) ?? throw new InvalidDataException("Invalid import recovery journal.");
        var committed=store.Scalar("SELECT digest FROM sync_receipts WHERE transfer_id=$id",null,("$id",journal.TransferId)) as string;
        if(committed!=null && committed!=journal.Digest) throw new InvalidDataException("Import recovery mismatch.");
        if(committed==null)
        {
            var rollback=Path.Combine(profile.Root,"rollback",WireJson.Id(journal.TransferId));
            foreach(var relative in journal.Replaced)
            { var target=SafeFiles.Resolve(profile.LibraryRoot,relative); SafeFiles.WriteAtomic(target,File.ReadAllBytes(SafeFiles.Resolve(rollback,relative))); }
            foreach(var relative in journal.Added)
            { var target=SafeFiles.Resolve(profile.LibraryRoot,relative); if(File.Exists(target)) File.Delete(target); }
        }
        File.Delete(path);
    }
}
