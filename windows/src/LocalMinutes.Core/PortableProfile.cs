using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace LocalMinutes.Core;

public sealed record LocalIdentity(string ReplicaId, string DeviceName);

public sealed class PortableProfile : IDisposable
{
    private readonly FileStream writerLock;
    public string Root { get; }
    public string LibraryRoot => Path.Combine(Root, "library");
    public string MeetingsRoot => Path.Combine(LibraryRoot, "Meetings");
    public string ModelsRoot => Path.Combine(Root, "models");
    public string DatabasePath => Path.Combine(LibraryRoot, "meetings.sqlite");
    public LocalIdentity Identity { get; }
    public string RunId { get; } = WireJson.NewId();

    public PortableProfile(string root)
    {
        Root = Path.GetFullPath(root);
        SafeFiles.RequireRegularTree(Root);
        Directory.CreateDirectory(Root);
        SafeFiles.RequireRegularTree(Root);
        writerLock = new FileStream(Path.Combine(Root, "profile.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        try
        {
            Directory.CreateDirectory(MeetingsRoot);
            Directory.CreateDirectory(ModelsRoot);
            Directory.CreateDirectory(Path.Combine(Root, "identity"));
            var identityPath = Path.Combine(Root, "identity", "device.json");
            if (File.Exists(identityPath))
            {
                Identity = JsonSerializer.Deserialize<LocalIdentity>(File.ReadAllBytes(identityPath), WireJson.Options)
                    ?? throw new InvalidDataException("Device identity is invalid.");
                _ = WireJson.Id(Identity.ReplicaId);
            }
            else
            {
                Identity = new(WireJson.NewId(), "My Windows PC");
                SafeFiles.WriteAtomic(identityPath, JsonSerializer.SerializeToUtf8Bytes(Identity, WireJson.Options));
            }
        }
        catch { writerLock.Dispose(); throw; }
    }

    public string MeetingDirectory(string id) => Path.Combine(MeetingsRoot, WireJson.Id(id));
    public void Dispose() => writerLock.Dispose();
}

public static class SafeFiles
{
    [StructLayout(LayoutKind.Sequential)]
    private struct FileInformation
    {
        public uint Attributes,CreationLow,CreationHigh,AccessLow,AccessHigh,WriteLow,WriteHigh,Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;
    }
    [DllImport("kernel32.dll",SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle,out FileInformation information);
    public static void RequireSingleLink(FileStream stream)
    {
        if(!GetFileInformationByHandle(stream.SafeFileHandle,out var info)||info.Links!=1||(info.Attributes&(uint)FileAttributes.ReparsePoint)!=0)
            throw new IOException("Linked or unverifiable data files are not supported.");
    }
    public static void RequireRegularTree(string path)
    {
        var current = new DirectoryInfo(Path.GetFullPath(path));
        while (current != null)
        {
            if (current.Exists && (current.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Linked data directories are not supported.");
            current = current.Parent;
        }
    }

    public static string Resolve(string root, string relative)
    {
        if (string.IsNullOrWhiteSpace(relative) || relative.Contains('\\') || relative.Contains(':') || Path.IsPathRooted(relative))
            throw new InvalidDataException("Unsafe relative path.");
        var parts = relative.Split('/');
        if (parts.Any(p => p is "" or "." or ".." || p.EndsWith('.') || p.EndsWith(' ') ||
            p.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 ||
            new[] { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9" }.Contains(p.Split('.')[0], StringComparer.OrdinalIgnoreCase)))
            throw new InvalidDataException("Unsafe path component.");
        var full = Path.GetFullPath(Path.Combine(root, Path.Combine(parts)));
        if (!full.StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Path escapes the data folder.");
        RequireRegularTree(Path.GetDirectoryName(full)!);
        if (File.Exists(full) && (File.GetAttributes(full) & FileAttributes.ReparsePoint) != 0)
            throw new IOException("Linked files are not supported.");
        return full;
    }

    public static void WriteAtomic(string path, ReadOnlySpan<byte> bytes)
    {
        RequireRegularTree(Path.GetDirectoryName(path)!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { stream.Write(bytes); stream.Flush(true); }
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    public static async Task<string> HashAsync(string path, CancellationToken cancellationToken = default)
    {
        using var stream = File.OpenRead(path);
        RequireSingleLink(stream);
        return Convert.ToHexStringLower(await SHA256.HashDataAsync(stream, cancellationToken));
    }
}
