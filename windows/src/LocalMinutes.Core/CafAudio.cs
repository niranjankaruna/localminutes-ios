using System.Buffers.Binary;
using System.Text.Json;

namespace LocalMinutes.Core;

/// <summary>The exact PCM CAF subset used by iOS; CAF flags differ from AudioStreamBasicDescription flags.</summary>
public static class CafAudio
{
    public sealed record Region(long Offset, long Bytes);
    public static Region Inspect(Stream stream)
    {
        Span<byte> header = stackalloc byte[8]; stream.ReadExactly(header);
        if (!header[..4].SequenceEqual("caff"u8) || BinaryPrimitives.ReadUInt16BigEndian(header[4..]) != 1) throw new InvalidDataException("Unsupported CAF header.");
        bool described = false; Region? region = null;
        Span<byte> chunk = stackalloc byte[12]; Span<byte> format = stackalloc byte[32];
        while (stream.Position < stream.Length)
        {
            stream.ReadExactly(chunk);
            long length = BinaryPrimitives.ReadInt64BigEndian(chunk[4..]);
            if (length < 0 || length > stream.Length - stream.Position) throw new InvalidDataException("CAF segment is incomplete.");
            long end = checked(stream.Position + length);
            if (chunk[..4].SequenceEqual("desc"u8))
            {
                if (described || length != 32) throw new InvalidDataException("Invalid CAF description.");
                stream.ReadExactly(format);
                if (BitConverter.Int64BitsToDouble(BinaryPrimitives.ReadInt64BigEndian(format)) != 16000 || !format.Slice(8,4).SequenceEqual("lpcm"u8) ||
                    BinaryPrimitives.ReadUInt32BigEndian(format[12..]) != 2 || BinaryPrimitives.ReadUInt32BigEndian(format[16..]) != 2 ||
                    BinaryPrimitives.ReadUInt32BigEndian(format[20..]) != 1 || BinaryPrimitives.ReadUInt32BigEndian(format[24..]) != 1 || BinaryPrimitives.ReadUInt32BigEndian(format[28..]) != 16)
                    throw new InvalidDataException("Expected mono 16 kHz signed 16-bit little-endian PCM CAF.");
                described = true;
            }
            else if (chunk[..4].SequenceEqual("data"u8))
            {
                if (!described || region != null || length < 4 || (length-4)%2 != 0) throw new InvalidDataException("Invalid CAF audio data.");
                region = new(stream.Position+4,length-4);
            }
            stream.Position = end;
        }
        return region ?? throw new InvalidDataException("CAF has no audio data.");
    }

    public static void Write(string path, ReadOnlySpan<byte> pcm)
    {
        if (pcm.Length%2 != 0) throw new InvalidDataException("PCM must contain complete samples.");
        using var stream = new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None);
        WriteHeader(stream,pcm.Length); stream.Write(pcm); stream.Flush(true);
    }

    internal static void WriteHeader(Stream stream, long bytes)
    {
        Span<byte> h = stackalloc byte[68]; h.Clear();
        "caff"u8.CopyTo(h); BinaryPrimitives.WriteUInt16BigEndian(h[4..],1);
        "desc"u8.CopyTo(h[8..]); BinaryPrimitives.WriteInt64BigEndian(h[12..],32);
        BinaryPrimitives.WriteInt64BigEndian(h[20..],BitConverter.DoubleToInt64Bits(16000));
        "lpcm"u8.CopyTo(h[28..]); BinaryPrimitives.WriteUInt32BigEndian(h[32..],2);
        BinaryPrimitives.WriteUInt32BigEndian(h[36..],2); BinaryPrimitives.WriteUInt32BigEndian(h[40..],1);
        BinaryPrimitives.WriteUInt32BigEndian(h[44..],1); BinaryPrimitives.WriteUInt32BigEndian(h[48..],16);
        "data"u8.CopyTo(h[52..]); BinaryPrimitives.WriteInt64BigEndian(h[56..],bytes < 0 ? -1 : checked(bytes+4));
        stream.Write(h);
    }

    public static float[] Samples(string path)
    {
        using var stream=File.OpenRead(path); var region=Inspect(stream);
        if (region.Bytes>1_920_000) throw new InvalidDataException("Recording segment exceeds 60 seconds.");
        stream.Position=region.Offset; var pcm=new byte[(int)region.Bytes]; stream.ReadExactly(pcm);
        var samples=new float[pcm.Length/2];
        for (var i=0;i<samples.Length;i++) samples[i]=BinaryPrimitives.ReadInt16LittleEndian(pcm.AsSpan(i*2,2))/32768f;
        return samples;
    }
}

public sealed class CafCaptureWriter : IDisposable
{
    private const int MaximumBytes = 1_920_000;
    private readonly string directory;
    private readonly string meetingId;
    private readonly List<AudioSegment> segments=[];
    private FileStream? current;
    private int bytes;
    public long TotalFrames { get; private set; }
    public IReadOnlyList<AudioSegment> Segments => segments;
    public CafCaptureWriter(string directory,string meetingId)
    {
        this.directory=directory; this.meetingId=WireJson.Id(meetingId);
        if (Directory.Exists(directory) && Directory.EnumerateFileSystemEntries(directory).Any()) throw new IOException("Recording folder already contains data.");
        Directory.CreateDirectory(directory); SafeFiles.RequireRegularTree(directory);
    }
    public void Append(ReadOnlySpan<byte> pcm)
    {
        if (pcm.Length%2!=0) throw new InvalidDataException("Invalid PCM callback.");
        while (!pcm.IsEmpty)
        {
            if (current==null)
            {
                current=new FileStream(Path.Combine(directory,$"segment-{segments.Count:000000}.caf"),FileMode.CreateNew,FileAccess.ReadWrite,FileShare.Read);
                CafAudio.WriteHeader(current,-1); bytes=0;
            }
            int count=Math.Min(MaximumBytes-bytes,pcm.Length); current.Write(pcm[..count]); bytes+=count; pcm=pcm[count..]; TotalFrames+=count/2;
            if (bytes==MaximumBytes) CloseSegment();
        }
    }
    private void CloseSegment()
    {
        if (current==null) return;
        current.Position=56; Span<byte> length=stackalloc byte[8]; BinaryPrimitives.WriteInt64BigEndian(length,bytes+4); current.Write(length); current.Flush(true); current.Dispose(); current=null;
        segments.Add(new($"segment-{segments.Count:000000}.caf",TotalFrames-bytes/2,bytes/2));
        SafeFiles.WriteAtomic(Path.Combine(directory,"capture-manifest.json"),JsonSerializer.SerializeToUtf8Bytes(new CaptureManifest(1,meetingId,TotalFrames,segments),WireJson.Options));
    }
    public CaptureManifest Finish() { CloseSegment(); return new(1,meetingId,TotalFrames,[..segments]); }
    public void Dispose() { current?.Dispose(); current=null; }
}

/// <summary>Seekable original PCM timeline, including silence at explicit missing ranges.</summary>
public sealed class CafTimelineStream : Stream
{
    private sealed record Entry(long Start,long End,string Path,long Offset);
    private readonly List<Entry> entries=[];
    private readonly long length;
    private long position;
    public CafTimelineStream(string directory)
    {
        var manifestPath=SafeFiles.Resolve(directory,"capture-manifest.json");
        if(new FileInfo(manifestPath).Length>16*1024*1024)throw new InvalidDataException("Capture manifest is too large.");
        var manifest=JsonSerializer.Deserialize<CaptureManifest>(File.ReadAllBytes(manifestPath),WireJson.Options) ?? throw new InvalidDataException("Missing capture manifest.");
        if (manifest.SchemaVersion!=1 || manifest.TotalFrames<0) throw new InvalidDataException("Unsupported capture manifest.");
        long previous=0;
        foreach(var segment in manifest.Segments)
        {
            if (segment.StartFrame<previous || segment.FrameCount<0 || segment.FrameCount>960_000) throw new InvalidDataException("Invalid audio timeline.");
            var path=SafeFiles.Resolve(directory,segment.RelativePath);
            using var file=File.OpenRead(path); var audio=CafAudio.Inspect(file);
            if (audio.Bytes!=segment.FrameCount*2) throw new InvalidDataException("Audio sample count mismatch.");
            previous=checked(segment.StartFrame+segment.FrameCount);
            entries.Add(new(checked(segment.StartFrame*2),checked(previous*2),path,audio.Offset));
        }
        if (previous!=manifest.TotalFrames) throw new InvalidDataException("Manifest duration mismatch.");
        length=checked(previous*2);
    }
    public override int Read(byte[] buffer,int offset,int count)
    {
        var span=buffer.AsSpan(offset,count); var available=(int)Math.Min(count,length-position); var remaining=available;
        while(remaining>0)
        {
            var item=entries.FirstOrDefault(x=>x.End>position);
            if (item==null) break;
            int read=(int)Math.Min(remaining,position<item.Start?item.Start-position:item.End-position);
            if(position<item.Start) span[..read].Clear();
            else { using var file=File.OpenRead(item.Path); file.Position=item.Offset+position-item.Start; file.ReadExactly(span[..read]); }
            span=span[read..]; position+=read; remaining-=read;
        }
        return available-remaining;
    }
    public override long Seek(long offset,SeekOrigin origin) { var next=checked((origin==SeekOrigin.Begin?0:origin==SeekOrigin.Current?position:length)+offset); if(next<0||next>length) throw new IOException("Audio seek outside recording."); return position=next; }
    public override bool CanRead=>true; public override bool CanSeek=>true; public override bool CanWrite=>false;
    public override long Length=>length; public override long Position {get=>position;set=>Seek(value,SeekOrigin.Begin);}
    public override void Flush() { }
    public override void SetLength(long value)=>throw new NotSupportedException();
    public override void Write(byte[] buffer,int offset,int count)=>throw new NotSupportedException();
}
