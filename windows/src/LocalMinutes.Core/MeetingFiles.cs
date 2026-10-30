using System.Text.Json;

namespace LocalMinutes.Core;

public static class MeetingFiles
{
    public static void Delete(PortableProfile profile,MeetingStore store,string meetingId)
    {
        meetingId=WireJson.Id(meetingId);
        store.Exclusive(()=>
        {
            if(store.Meetings().Any(x=>x.Id==meetingId&&x.RecordingState=="recording"))throw new InvalidOperationException("Stop recording before deleting this meeting.");
            var root=Path.Combine(profile.Root,"deletions");Directory.CreateDirectory(root);SafeFiles.RequireRegularTree(root);
            SafeFiles.WriteAtomic(Path.Combine(root,meetingId+".json"),JsonSerializer.SerializeToUtf8Bytes(meetingId));
            Complete(profile,store,meetingId);return true;
        });
    }
    public static void Recover(PortableProfile profile,MeetingStore store)
    {
        var root=Path.Combine(profile.Root,"deletions");if(!Directory.Exists(root))return;SafeFiles.RequireRegularTree(root);
        foreach(var marker in Directory.EnumerateFiles(root,"*.json"))
        {
            if(new FileInfo(marker).Length>128)throw new InvalidDataException("Invalid deletion journal.");
            var id=WireJson.Id(JsonSerializer.Deserialize<string>(File.ReadAllBytes(marker))??"");
            if(Path.GetFileName(marker)!=id+".json")throw new InvalidDataException("Deletion journal identity mismatch.");
            Complete(profile,store,id);
        }
    }
    private static void Complete(PortableProfile profile,MeetingStore store,string id)
    {
        var source=profile.MeetingDirectory(id);var root=Path.Combine(profile.Root,"deletions");var quarantine=Path.Combine(root,id);
        if(Directory.Exists(source))
        {
            SafeFiles.RequireRegularTree(source);
            if(Directory.Exists(quarantine))throw new IOException("Deletion quarantine already exists.");
            Directory.Move(source,quarantine);
        }
        store.Delete(id);
        if(Directory.Exists(quarantine))
        {
            SafeFiles.RequireRegularTree(quarantine);
            // Enumerate without following reparse points before recursive cleanup of this exact owned UUID directory.
            var pending=new Stack<string>();pending.Push(quarantine);
            while(pending.Count>0)
                foreach(var path in Directory.EnumerateFileSystemEntries(pending.Pop()))
                {var attributes=File.GetAttributes(path);if((attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Unsafe deletion entry.");if((attributes&FileAttributes.Directory)!=0)pending.Push(path);}
            Directory.Delete(quarantine,true);
        }
        File.Delete(Path.Combine(root,id+".json"));
    }
}
