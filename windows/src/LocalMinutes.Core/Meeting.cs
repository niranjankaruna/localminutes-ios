using System.Text.Json;
using System.Text.Json.Serialization;

namespace LocalMinutes.Core;

public sealed record Meeting(string Id, string Title, double CreatedAt, string RecordingState, long CapturedSampleCount)
{
    [JsonIgnore] public string DateLabel => DateTimeOffset.FromUnixTimeMilliseconds((long)(CreatedAt * 1000)).LocalDateTime.ToString("dd MMM yyyy · HH:mm");
    [JsonIgnore] public string DurationLabel => TimeSpan.FromSeconds(CapturedSampleCount / 16000d).ToString(@"hh\:mm\:ss");
}

public sealed record TranscriptSegment(string Id, string MeetingId, int Sequence, long StartSample, long EndSample, string Text, string ModelRevision);
public sealed record ManualNote(string MeetingId, string Text, long EditRevision, double ModifiedAt);
public sealed record GeneratedDocument(string Id, string MeetingId, string Kind, string OriginalJson, string? Question,
    string EditedText, long EditRevision, string ModelRevision, string PromptVersion, double CreatedAt, double ModifiedAt);
public sealed record SpeechPin(string MeetingId, string SelectionJson);
public sealed record AudioSegment(string RelativePath, long StartFrame, long FrameCount);
public sealed record CaptureManifest(int SchemaVersion, string SessionId, long TotalFrames, List<AudioSegment> Segments)
{
    [JsonPropertyName("sessionID")]
    public string SessionId { get; init; } = SessionId;
}

public static class WireJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = false,
        PropertyNameCaseInsensitive = false,
        MaxDepth = 64
    };
    public static string Id(string id) => Guid.TryParseExact(id, "D", out var value)
        ? value.ToString("D").ToUpperInvariant() : throw new InvalidDataException("Invalid record identifier.");
    public static string NewId() => Guid.NewGuid().ToString("D").ToUpperInvariant();
    public static double Now => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000d;
}
