using System.Text.Json;

namespace LocalMinutes.Core;

public sealed record DocumentCitation(string SourceId,long StartSample,long EndSample,string Quote)
{
    public string Label=>TimeSpan.FromSeconds(StartSample/16000d).ToString(@"hh\:mm\:ss")+"  "+Quote;
}

public static class DocumentEvidence
{
    public static IReadOnlyList<DocumentCitation> Read(GeneratedDocument document,IEnumerable<TranscriptSegment> transcript)
    {
        var sources=transcript.ToDictionary(x=>x.Id,StringComparer.Ordinal);var citations=new List<DocumentCitation>();var seen=new HashSet<string>();
        using var json=JsonDocument.Parse(document.OriginalJson);
        void Evidence(JsonElement parent)
        {
            if(!parent.TryGetProperty("evidence",out var evidence)||evidence.ValueKind!=JsonValueKind.Array)return;
            foreach(var entry in evidence.EnumerateArray())
            {
                if(!entry.TryGetProperty("source_id",out var id)||id.GetString() is not string key||!sources.TryGetValue(key,out var source)||source.MeetingId!=document.MeetingId)continue;
                if(!entry.TryGetProperty("start_sample",out var start)||!start.TryGetInt64(out var first)||!entry.TryGetProperty("end_sample",out var end)||!end.TryGetInt64(out var last)||first<source.StartSample||last>source.EndSample||first>last)continue;
                if(!entry.TryGetProperty("quote",out var quote)||quote.GetString() is not string text||string.IsNullOrEmpty(text)||!source.Text.Contains(text,StringComparison.Ordinal))continue;
                if(seen.Add(key+":"+first+":"+last+":"+text))citations.Add(new(key,first,last,text));
            }
        }
        Evidence(json.RootElement);
        if(json.RootElement.TryGetProperty("overview",out var overview)&&overview.ValueKind==JsonValueKind.Object)Evidence(overview);
        if(json.RootElement.TryGetProperty("bullets",out var bullets)&&bullets.ValueKind==JsonValueKind.Array)foreach(var bullet in bullets.EnumerateArray())Evidence(bullet);
        return citations;
    }
}
