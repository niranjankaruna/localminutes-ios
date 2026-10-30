using Microsoft.Data.Sqlite;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace LocalMinutes.Core;

/// <summary>Reads the existing iOS directory-package format without opening it for writes or executing supplied SQL.</summary>
public static class IosBackupReader
{
    private sealed record BackupManifest(int SchemaVersion,int DatabaseUserVersion,long TotalByteCount,List<ExchangeFile> Files);
    public static string ConvertToExchange(string backup,string destination,string sourceId)
    {
        SafeFiles.RequireRegularTree(backup);
        var manifestPath=SafeFiles.Resolve(backup,"manifest.json");
        if(new FileInfo(manifestPath).Length>1_048_576) throw new InvalidDataException("Oversized backup manifest.");
        var manifest=JsonSerializer.Deserialize<BackupManifest>(File.ReadAllBytes(manifestPath),WireJson.Options) ?? throw new InvalidDataException("Invalid backup manifest.");
        if(manifest.SchemaVersion!=1 || manifest.DatabaseUserVersion is <1 or >6 || manifest.Files.Count is <1 or >16_384) throw new InvalidDataException("Unsupported iPhone backup.");
        var payload=Path.Combine(backup,"payload"); var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase); long total=0;
        foreach(var file in manifest.Files)
        {
            if((file.RelativePath!="meetings.sqlite" && !LibraryExchange.Allowed(file.RelativePath)) || file.RelativePath=="records.jsonl" || !names.Add(file.RelativePath) || file.ByteCount is <0 or >536_870_912) throw new InvalidDataException("Unsafe backup entry.");
            total=checked(total+file.ByteCount); if(total>8_589_934_592) throw new InvalidDataException("Backup exceeds supported size.");
            using var stream=File.OpenRead(SafeFiles.Resolve(payload,file.RelativePath));
            if(stream.Length!=file.ByteCount || Convert.ToHexStringLower(SHA256.HashData(stream))!=file.Sha256) throw new InvalidDataException("Backup checksum mismatch.");
        }
        if(total!=manifest.TotalByteCount || !names.Contains("meetings.sqlite")) throw new InvalidDataException("Incomplete backup.");
        foreach(var file in Directory.EnumerateFiles(payload,"*",SearchOption.AllDirectories))
            if(!names.Contains(Path.GetRelativePath(payload,file).Replace('\\','/'))) throw new InvalidDataException("Unexpected backup payload.");
        if(Directory.Exists(destination)) throw new IOException("Import staging folder already exists.");
        Directory.CreateDirectory(destination);
        using var database=new SqliteConnection(new SqliteConnectionStringBuilder {DataSource=SafeFiles.Resolve(payload,"meetings.sqlite"),Mode=SqliteOpenMode.ReadOnly,Pooling=false}.ToString());
        database.Open();
        using(var check=database.CreateCommand())
        {
            check.CommandText="PRAGMA trusted_schema=OFF; PRAGMA query_only=ON;";check.ExecuteNonQuery();
            check.CommandText="PRAGMA user_version";
            if(Convert.ToInt32(check.ExecuteScalar())!=manifest.DatabaseUserVersion) throw new InvalidDataException("Backup schema mismatch.");
            check.CommandText="PRAGMA quick_check"; if((string?)check.ExecuteScalar()!="ok") throw new InvalidDataException("Backup database integrity check failed.");
            check.CommandText="PRAGMA foreign_key_check";using var violations=check.ExecuteReader();if(violations.Read()) throw new InvalidDataException("Broken backup relationships.");
        }
        using(var output=new FileStream(Path.Combine(destination,"records.jsonl"),FileMode.CreateNew,FileAccess.Write,FileShare.None))
        {
            Query("SELECT id,title,created_at,recording_state,captured_sample_count FROM meetings",r=>LibraryExchange.WriteRow(output,"meeting",MeetingStore.ReadMeeting(r)));
            Query("SELECT id,meeting_id,sequence,start_sample,end_sample,text,model_revision FROM transcript_segments",r=>LibraryExchange.WriteRow(output,"segment",new TranscriptSegment(WireJson.Id(r.GetString(0)),WireJson.Id(r.GetString(1)),r.GetInt32(2),r.GetInt64(3),r.GetInt64(4),r.GetString(5),r.GetString(6))));
            if(manifest.DatabaseUserVersion>=2) Query("SELECT meeting_id,text,edit_revision,modified_at FROM manual_notes",r=>LibraryExchange.WriteRow(output,"note",new ManualNote(WireJson.Id(r.GetString(0)),r.GetString(1),r.GetInt64(2),r.GetDouble(3))));
            if(manifest.DatabaseUserVersion>=4)
            {
                Query("SELECT id,meeting_id,kind,original_json,question,edited_text,edit_revision,model_revision,prompt_version,created_at,modified_at FROM generated_documents ORDER BY created_at,id",r=>LibraryExchange.WriteRow(output,"document",new GeneratedDocument(WireJson.Id(r.GetString(0)),WireJson.Id(r.GetString(1)),r.GetString(2),Encoding.UTF8.GetString((byte[])r[3]),r.IsDBNull(4)?null:r.GetString(4),r.GetString(5),r.GetInt64(6),r.GetString(7),r.GetString(8),r.GetDouble(9),r.GetDouble(10))));
                Query(manifest.DatabaseUserVersion>=6?"SELECT meeting_id,document_id FROM preferred_summaries":"SELECT meeting_id,id FROM generated_documents AS d WHERE kind='summary' AND id=(SELECT id FROM generated_documents WHERE meeting_id=d.meeting_id AND kind='summary' ORDER BY created_at DESC,id ASC LIMIT 1)",r=>LibraryExchange.WriteRow(output,"preference",new SummaryPreference(WireJson.Id(r.GetString(0)),WireJson.Id(r.GetString(1)))));
            }
            if(manifest.DatabaseUserVersion>=5) Query("SELECT meeting_id,selection_json FROM meeting_speech_model_pins",r=>LibraryExchange.WriteRow(output,"pin",new SpeechPin(WireJson.Id(r.GetString(0)),r.GetString(1))));
            output.Flush(true);
        }
        foreach(var file in manifest.Files.Where(f=>f.RelativePath!="meetings.sqlite"))
        {
            var target=SafeFiles.Resolve(destination,file.RelativePath);Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(SafeFiles.Resolve(payload,file.RelativePath),target);
        }
        LibraryExchange.Seal(destination,sourceId);return destination;
        void Query(string sql,Action<SqliteDataReader> action)
        {using var command=database.CreateCommand();command.CommandText=sql;using var reader=command.ExecuteReader();while(reader.Read()) action(reader);}
    }
}
