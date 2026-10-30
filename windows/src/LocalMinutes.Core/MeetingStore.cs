using Microsoft.Data.Sqlite;
using System.Text;
using System.Text.Json;

namespace LocalMinutes.Core;

/// <summary>One serialized owner for the local connection; import and local edits share the same gate.</summary>
public sealed class MeetingStore : IDisposable
{
    private readonly SqliteConnection connection;
    private readonly object gate = new();
    public long MutationSequence { get; private set; }

    public MeetingStore(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
        connection.Open();
        var version = Convert.ToInt64(Scalar("PRAGMA user_version"));
        if (version is < 0 or > 1) { connection.Dispose(); throw new InvalidDataException("Unsupported Windows library version."); }
        Execute("PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL; PRAGMA busy_timeout=1000;");
        if (version == 0)
        {
            using var transaction = connection.BeginTransaction();
            Execute("""
                CREATE TABLE meetings(id TEXT PRIMARY KEY NOT NULL,title TEXT NOT NULL,created_at REAL NOT NULL,
                    recording_state TEXT NOT NULL CHECK(recording_state IN ('recording','completed','interrupted','recovered','failed')),
                    captured_sample_count INTEGER NOT NULL CHECK(captured_sample_count>=0));
                CREATE INDEX meeting_history ON meetings(created_at DESC,id);
                CREATE TABLE transcript_segments(id TEXT PRIMARY KEY NOT NULL,meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
                    sequence INTEGER NOT NULL CHECK(sequence>=0),start_sample INTEGER NOT NULL CHECK(start_sample>=0),
                    end_sample INTEGER NOT NULL CHECK(end_sample>=start_sample),text TEXT NOT NULL,model_revision TEXT NOT NULL,
                    UNIQUE(meeting_id,sequence));
                CREATE TABLE manual_notes(meeting_id TEXT PRIMARY KEY NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
                    text TEXT NOT NULL,edit_revision INTEGER NOT NULL,modified_at REAL NOT NULL);
                CREATE TABLE generated_documents(id TEXT PRIMARY KEY NOT NULL,meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL CHECK(kind IN ('summary','question_answer')),original_json BLOB NOT NULL,question TEXT,
                    edited_text TEXT NOT NULL,edit_revision INTEGER NOT NULL,model_revision TEXT NOT NULL,prompt_version TEXT NOT NULL,
                    created_at REAL NOT NULL,modified_at REAL NOT NULL);
                CREATE INDEX document_history ON generated_documents(meeting_id,created_at DESC,id);
                CREATE TABLE meeting_speech_model_pins(meeting_id TEXT PRIMARY KEY REFERENCES meetings(id) ON DELETE CASCADE,selection_json TEXT NOT NULL);
                CREATE TABLE preferred_summaries(meeting_id TEXT PRIMARY KEY REFERENCES meetings(id) ON DELETE CASCADE,
                    document_id TEXT NOT NULL REFERENCES generated_documents(id) ON DELETE CASCADE);
                CREATE TABLE sync_receipts(transfer_id TEXT PRIMARY KEY NOT NULL,source_id TEXT NOT NULL,digest TEXT NOT NULL,committed_at REAL NOT NULL);
                CREATE VIRTUAL TABLE transcript_fts USING fts5(text,content='transcript_segments',content_rowid='rowid',tokenize='unicode61 remove_diacritics 2');
                CREATE TRIGGER transcript_insert AFTER INSERT ON transcript_segments BEGIN INSERT INTO transcript_fts(rowid,text) VALUES(new.rowid,new.text); END;
                CREATE TRIGGER transcript_delete AFTER DELETE ON transcript_segments BEGIN INSERT INTO transcript_fts(transcript_fts,rowid,text) VALUES('delete',old.rowid,old.text); END;
                PRAGMA user_version=1;
                """, transaction);
            transaction.Commit();
        }
    }

    public List<Meeting> Meetings(string search = "")
    {
        lock (gate)
        {
            using var command = Command("SELECT id,title,created_at,recording_state,captured_sample_count FROM meetings WHERE instr(lower(title),lower($q))>0 ORDER BY created_at DESC,id", null, ("$q", search));
            using var reader = command.ExecuteReader();
            var values = new List<Meeting>();
            while (reader.Read()) values.Add(ReadMeeting(reader));
            return values;
        }
    }

    public void Create(Meeting meeting)
    {
        ValidateMeeting(meeting);
        lock (gate) { InsertMeeting(meeting, null); MutationSequence++; }
    }

    public void Rename(string id, string title)
    {
        if (string.IsNullOrWhiteSpace(title) || title.Length > 1000) throw new InvalidDataException("Enter a title of up to 1,000 characters.");
        lock (gate)
        {
            if (Execute("UPDATE meetings SET title=$title WHERE id=$id", null, ("$title", title.Trim()), ("$id", WireJson.Id(id))) != 1)
                throw new InvalidOperationException("Meeting no longer exists.");
            MutationSequence++;
        }
    }

    public void FinishRecording(string id, long sampleCount, string state = "completed")
    {
        if (sampleCount < 0 || state is not ("completed" or "interrupted" or "recovered" or "failed")) throw new InvalidDataException("Invalid recording state.");
        lock (gate) { Execute("UPDATE meetings SET captured_sample_count=$count,recording_state=$state WHERE id=$id", null, ("$count", sampleCount), ("$state", state), ("$id", WireJson.Id(id))); MutationSequence++; }
    }

    public void Delete(string id)
    {
        lock (gate) { Execute("DELETE FROM meetings WHERE id=$id", null, ("$id", WireJson.Id(id))); MutationSequence++; }
    }

    public List<TranscriptSegment> Transcript(string meetingId)
    {
        lock (gate)
        {
            using var command = Command("SELECT id,meeting_id,sequence,start_sample,end_sample,text,model_revision FROM transcript_segments WHERE meeting_id=$id ORDER BY sequence", null, ("$id", WireJson.Id(meetingId)));
            using var reader = command.ExecuteReader(); var values = new List<TranscriptSegment>();
            while (reader.Read()) values.Add(new(reader.GetString(0),reader.GetString(1),reader.GetInt32(2),reader.GetInt64(3),reader.GetInt64(4),reader.GetString(5),reader.GetString(6)));
            return values;
        }
    }

    public void Append(TranscriptSegment segment)
    {
        ValidateSegment(segment);
        lock (gate) { InsertSegment(segment, null); MutationSequence++; }
    }

    public ManualNote? Note(string meetingId)
    {
        lock (gate)
        {
            using var command = Command("SELECT meeting_id,text,edit_revision,modified_at FROM manual_notes WHERE meeting_id=$id", null, ("$id", WireJson.Id(meetingId)));
            using var reader = command.ExecuteReader();
            return reader.Read() ? new(reader.GetString(0),reader.GetString(1),reader.GetInt64(2),reader.GetDouble(3)) : null;
        }
    }

    public ManualNote SaveNote(string id, string text, long expectedRevision)
    {
        if (Encoding.UTF8.GetByteCount(text) > 1_048_576) throw new InvalidDataException("Notes exceed 1 MiB.");
        lock (gate)
        {
            var previous = Note(id);
            if ((previous?.EditRevision ?? 0) != expectedRevision) throw new InvalidOperationException("Notes changed elsewhere. Reload before saving.");
            var note = new ManualNote(WireJson.Id(id), text, checked(expectedRevision + 1), WireJson.Now);
            UpsertNote(note, null); MutationSequence++; return note;
        }
    }

    public List<GeneratedDocument> Documents(string id)
    {
        lock (gate)
        {
            using var command = Command("SELECT id,meeting_id,kind,original_json,question,edited_text,edit_revision,model_revision,prompt_version,created_at,modified_at FROM generated_documents WHERE meeting_id=$id ORDER BY created_at DESC,id", null, ("$id", WireJson.Id(id)));
            using var reader = command.ExecuteReader(); var result = new List<GeneratedDocument>();
            while (reader.Read()) result.Add(new(reader.GetString(0),reader.GetString(1),reader.GetString(2),Encoding.UTF8.GetString((byte[])reader[3]),reader.IsDBNull(4)?null:reader.GetString(4),reader.GetString(5),reader.GetInt64(6),reader.GetString(7),reader.GetString(8),reader.GetDouble(9),reader.GetDouble(10)));
            return result;
        }
    }

    public GeneratedDocument? PreferredSummary(string meetingId)
    {
        lock (gate)
        {
            var preferred = Scalar("SELECT document_id FROM preferred_summaries WHERE meeting_id=$id", null, ("$id", WireJson.Id(meetingId))) as string;
            var documents = Documents(meetingId).Where(x => x.Kind == "summary").ToList();
            return documents.FirstOrDefault(x => x.Id == preferred) ?? documents.FirstOrDefault();
        }
    }

    public void CreateDocument(GeneratedDocument document)
    {
        ValidateDocument(document);
        lock (gate)
        {
            using var transaction = connection.BeginTransaction();
            InsertDocument(document, transaction);
            if (document.Kind == "summary") SetPreferred(document.MeetingId, document.Id, transaction);
            transaction.Commit(); MutationSequence++;
        }
    }

    public GeneratedDocument SaveDocumentEdit(GeneratedDocument document, string text)
    {
        if (Encoding.UTF8.GetByteCount(text) > 1_048_576) throw new InvalidDataException("Edited text exceeds 1 MiB.");
        lock (gate)
        {
            var edited = document with { EditedText = text, EditRevision = checked(document.EditRevision + 1), ModifiedAt = WireJson.Now };
            if (Execute("UPDATE generated_documents SET edited_text=$text,edit_revision=$next,modified_at=$time WHERE id=$id AND meeting_id=$meeting AND edit_revision=$expected", null,
                ("$text",text),("$next",edited.EditRevision),("$time",edited.ModifiedAt),("$id",document.Id),("$meeting",document.MeetingId),("$expected",document.EditRevision)) != 1)
                throw new InvalidOperationException("Document changed elsewhere. Reload before saving.");
            MutationSequence++; return edited;
        }
    }

    public void DeleteSummaries(string meetingId)
    { lock (gate) { Execute("DELETE FROM generated_documents WHERE meeting_id=$id AND kind='summary'", null, ("$id",WireJson.Id(meetingId))); MutationSequence++; } }

    public void BackupTo(string path)
    {
        lock (gate)
        {
            using var target = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
            target.Open(); connection.BackupDatabase(target);
        }
    }

    public T Exclusive<T>(Func<T> operation) { lock (gate) return operation(); }

    internal List<SpeechPin> Pins()
    {
        lock (gate)
        {
            using var command = Command("SELECT meeting_id,selection_json FROM meeting_speech_model_pins");
            using var reader = command.ExecuteReader(); var values = new List<SpeechPin>();
            while (reader.Read()) values.Add(new(reader.GetString(0),reader.GetString(1)));
            return values;
        }
    }

    internal SqliteTransaction BeginTransaction() => connection.BeginTransaction();
    internal void Changed() => MutationSequence++;
    internal int Execute(string sql, SqliteTransaction? transaction = null, params (string Name, object? Value)[] parameters)
    { using var command = Command(sql,transaction,parameters); return command.ExecuteNonQuery(); }
    internal object? Scalar(string sql, SqliteTransaction? transaction = null, params (string Name, object? Value)[] parameters)
    { using var command = Command(sql,transaction,parameters); return command.ExecuteScalar(); }
    internal SqliteCommand Command(string sql, SqliteTransaction? transaction = null, params (string Name, object? Value)[] parameters)
    {
        var command = connection.CreateCommand(); command.CommandText = sql; command.Transaction = transaction;
        foreach (var parameter in parameters) command.Parameters.AddWithValue(parameter.Name,parameter.Value ?? DBNull.Value);
        return command;
    }
    internal void InsertMeeting(Meeting m, SqliteTransaction? t) => Execute("INSERT INTO meetings VALUES($id,$title,$created,$state,$samples)",t,("$id",m.Id),("$title",m.Title),("$created",m.CreatedAt),("$state",m.RecordingState),("$samples",m.CapturedSampleCount));
    internal void InsertSegment(TranscriptSegment s, SqliteTransaction? t) => Execute("INSERT INTO transcript_segments VALUES($id,$meeting,$seq,$start,$end,$text,$model)",t,("$id",s.Id),("$meeting",s.MeetingId),("$seq",s.Sequence),("$start",s.StartSample),("$end",s.EndSample),("$text",s.Text),("$model",s.ModelRevision));
    internal void UpsertNote(ManualNote n, SqliteTransaction? t) => Execute("INSERT INTO manual_notes VALUES($id,$text,$revision,$modified) ON CONFLICT(meeting_id) DO UPDATE SET text=excluded.text,edit_revision=excluded.edit_revision,modified_at=excluded.modified_at",t,("$id",n.MeetingId),("$text",n.Text),("$revision",n.EditRevision),("$modified",n.ModifiedAt));
    internal void InsertDocument(GeneratedDocument d, SqliteTransaction? t) => Execute("INSERT INTO generated_documents VALUES($id,$meeting,$kind,$json,$question,$text,$rev,$model,$prompt,$created,$modified)",t,("$id",d.Id),("$meeting",d.MeetingId),("$kind",d.Kind),("$json",Encoding.UTF8.GetBytes(d.OriginalJson)),("$question",d.Question),("$text",d.EditedText),("$rev",d.EditRevision),("$model",d.ModelRevision),("$prompt",d.PromptVersion),("$created",d.CreatedAt),("$modified",d.ModifiedAt));
    internal void SetPreferred(string meeting, string document, SqliteTransaction? t) => Execute("INSERT INTO preferred_summaries VALUES($meeting,$document) ON CONFLICT(meeting_id) DO UPDATE SET document_id=excluded.document_id",t,("$meeting",meeting),("$document",document));

    internal static Meeting ReadMeeting(SqliteDataReader r) => new(r.GetString(0),r.GetString(1),r.GetDouble(2),r.GetString(3),r.GetInt64(4));
    internal static void ValidateMeeting(Meeting m)
    {
        if (WireJson.Id(m.Id) != m.Id || string.IsNullOrWhiteSpace(m.Title) || m.Title.Length > 1000 || !double.IsFinite(m.CreatedAt) || m.CapturedSampleCount < 0 ||
            m.RecordingState is not ("recording" or "completed" or "interrupted" or "recovered" or "failed")) throw new InvalidDataException("Invalid meeting.");
    }
    internal static void ValidateSegment(TranscriptSegment s)
    {
        if (WireJson.Id(s.Id)!=s.Id || WireJson.Id(s.MeetingId)!=s.MeetingId || s.Sequence<0 || s.StartSample<0 || s.EndSample<s.StartSample || Encoding.UTF8.GetByteCount(s.Text)>1_048_576) throw new InvalidDataException("Invalid transcript segment.");
    }
    internal static void ValidateDocument(GeneratedDocument d)
    {
        if (WireJson.Id(d.Id)!=d.Id || WireJson.Id(d.MeetingId)!=d.MeetingId || d.Kind is not ("summary" or "question_answer") || !double.IsFinite(d.CreatedAt) || !double.IsFinite(d.ModifiedAt) || d.EditRevision<0 || Encoding.UTF8.GetByteCount(d.OriginalJson)>1_048_576 || Encoding.UTF8.GetByteCount(d.EditedText)>1_048_576) throw new InvalidDataException("Invalid generated document.");
        using var json = JsonDocument.Parse(d.OriginalJson);
        if (json.RootElement.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Invalid document JSON.");
    }
    public void Dispose() { lock (gate) connection.Dispose(); }
}
