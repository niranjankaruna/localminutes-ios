using System.Buffers.Binary;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;

namespace LocalMinutes.Core;

public sealed record PairInvitation(int Version,string Host,int Port,string Fingerprint,string Token,string ReplicaId,string Name);
public sealed record TrustedPhone(string ReplicaId,string Name,string Token);
internal sealed record SyncSecrets(string CertificatePfx,List<TrustedPhone> Peers);
internal sealed record PendingSend(string DirectoryName,string TargetId);

public static class SyncFrames
{
    public static async Task WriteAsync(Stream stream,object value,CancellationToken token)
    {
        var data=JsonSerializer.SerializeToUtf8Bytes(value,WireJson.Options);
        if(data.Length>LibraryExchange.MaximumManifestBytes) throw new InvalidDataException("Protocol message is too large.");
        var header=new byte[4];BinaryPrimitives.WriteInt32BigEndian(header,data.Length);
        await stream.WriteAsync(header,token);await stream.WriteAsync(data,token);await stream.FlushAsync(token);
    }
    public static async Task<JsonDocument> ReadAsync(Stream stream,CancellationToken token)
    {
        var header=new byte[4];await stream.ReadExactlyAsync(header,token);int length=BinaryPrimitives.ReadInt32BigEndian(header);
        if(length is <2 or >LibraryExchange.MaximumManifestBytes) throw new InvalidDataException("Invalid protocol frame length.");
        var bytes=new byte[length];await stream.ReadExactlyAsync(bytes,token);return JsonDocument.Parse(bytes,new JsonDocumentOptions{MaxDepth=64});
    }
}

/// <summary>The PC owns the LAN listener. A foreground iPhone connection can either push or receive a queued PC send.</summary>
public sealed class SyncHost : IAsyncDisposable
{
    private readonly PortableProfile profile;
    private readonly MeetingStore store;
    private readonly Func<bool> canSync;
    private readonly X509Certificate2 certificate;
    private readonly SyncSecrets secrets;
    private readonly object gate=new();
    private readonly SemaphoreSlim sessionAdmission=new(1,1);
    private readonly CancellationTokenSource lifetime=new();
    private TcpListener? listener;
    private LocalAdvertisement? advertisement;
    private Task? acceptLoop;
    private string? invitationToken;
    private DateTime invitationExpiry;
    private string? outgoing;
    private string? outgoingTarget;
    private CancellationTokenSource? preparingSend;
    private string? connectedPhone;
    private string? incoming;
    private int authenticationFailures;
    private string PendingPath=>Path.Combine(profile.Root,"pending-send.json");
    public bool Enabled=>listener!=null;
    public string? ConnectedPhone {get {lock(gate) return connectedPhone;}}
    public int Port=>listener is null?0:((IPEndPoint)listener.LocalEndpoint).Port;
    public string Fingerprint=>Convert.ToHexStringLower(SHA256.HashData(certificate.RawData));
    public IReadOnlyList<TrustedPhone> Peers {get {lock(gate) return secrets.Peers.ToArray();}}
    public event Action<string>? Status;
    public event Action? Imported;
    public Func<Task>? PreparingImport {get;set;}
    public Action? ImportFinished {get;set;}
    public SyncHost(PortableProfile profile,MeetingStore store,Func<bool> canSync)
    {
        this.profile=profile;this.store=store;this.canSync=canSync;
        var secretPath=Path.Combine(profile.Root,"identity","sync.dat");
        SyncSecrets? loaded=null;
        if(File.Exists(secretPath))
        {
            try
            {
                var plain=ProtectedData.Unprotect(File.ReadAllBytes(secretPath),null,DataProtectionScope.CurrentUser);
                try {loaded=JsonSerializer.Deserialize<SyncSecrets>(plain,WireJson.Options) ?? throw new InvalidDataException("Sync identity is invalid.");}
                finally {CryptographicOperations.ZeroMemory(plain);}
            }
            catch(CryptographicException)
            {
                // A portable profile moved to another Windows user/machine keeps its meetings but must pair again.
                File.Move(secretPath,secretPath+".previous",true);
            }
        }
        bool createdIdentity=loaded==null;
        if(loaded==null)
        {
            using var key=ECDsa.Create(ECCurve.NamedCurves.nistP256);
            var request=new CertificateRequest("CN=LocalMinutes "+profile.Identity.ReplicaId,key,HashAlgorithmName.SHA256);
            request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature,true));
            using var created=request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1),DateTimeOffset.UtcNow.AddYears(5));
            loaded=new(Convert.ToBase64String(created.Export(X509ContentType.Pfx)),[]);
        }
        secrets=loaded;
        // Schannel cannot use EphemeralKeySet keys. UserKeySet gives it a temporary OS key container,
        // cleaned when the certificate is disposed; no trusted-root certificate installation is performed.
        certificate=X509CertificateLoader.LoadPkcs12(Convert.FromBase64String(secrets.CertificatePfx),null,X509KeyStorageFlags.UserKeySet|X509KeyStorageFlags.Exportable);
        if(createdIdentity)SaveSecrets();
        if(File.Exists(PendingPath))
        {
            if(new FileInfo(PendingPath).Length>4096)throw new InvalidDataException("Invalid pending send.");
            var pending=JsonSerializer.Deserialize<PendingSend>(File.ReadAllBytes(PendingPath),WireJson.Options)??throw new InvalidDataException("Invalid pending send.");
            var directory=SafeFiles.Resolve(profile.Root,"sync-outgoing/"+WireJson.Id(pending.DirectoryName));
            _=WireJson.Id(pending.TargetId);
            if(secrets.Peers.Any(peer=>peer.ReplicaId==pending.TargetId)&&File.Exists(Path.Combine(directory,"manifest.json"))){outgoing=directory;outgoingTarget=pending.TargetId;}
            else File.Delete(PendingPath);
        }
    }
    private void SaveSecrets()
    {
        var bytes=JsonSerializer.SerializeToUtf8Bytes(secrets,WireJson.Options);
        try {SafeFiles.WriteAtomic(Path.Combine(profile.Root,"identity","sync.dat"),ProtectedData.Protect(bytes,null,DataProtectionScope.CurrentUser));}
        finally {CryptographicOperations.ZeroMemory(bytes);}
    }
    public void Start(IPAddress? address=null,int port=47835)
    {
        if(listener!=null)return;
        var candidate=new TcpListener(address??IPAddress.Any,port);candidate.Start(4);listener=candidate;acceptLoop=AcceptAsync();
        if(address==null||!IPAddress.IsLoopback(address))
        {
            try{advertisement=new LocalAdvertisement(profile.Identity.ReplicaId,checked((ushort)Port));}
            catch(Exception error)when(error is System.Net.Sockets.SocketException or InvalidOperationException){Status?.Invoke("Automatic discovery is unavailable. Pair using the QR invitation's address.");}
        }
        Status?.Invoke("Ready on your local network. Open LocalMinutes on your paired iPhone.");
    }
    public static IReadOnlyList<string> LocalAddresses()=>NetworkInterface.GetAllNetworkInterfaces()
        .Where(n=>n.OperationalStatus==OperationalStatus.Up && n.NetworkInterfaceType!=NetworkInterfaceType.Loopback)
        .OrderByDescending(n=>n.GetIPProperties().GatewayAddresses.Any()).ThenByDescending(n=>n.NetworkInterfaceType==NetworkInterfaceType.Wireless80211)
        .SelectMany(n=>n.GetIPProperties().UnicastAddresses).Select(n=>n.Address)
        .Where(a=>a.AddressFamily==AddressFamily.InterNetwork && IsLocal(a)).Select(a=>a.ToString()).Distinct().ToArray();
    public PairInvitation Invite(string address)
    {
        bool localTest=listener?.LocalEndpoint is IPEndPoint endpoint&&IPAddress.IsLoopback(endpoint.Address)&&address=="127.0.0.1";
        if(!localTest&&!LocalAddresses().Contains(address)) throw new InvalidOperationException("Choose one of this PC's local addresses.");
        Start();
        lock(gate)
        {
            invitationToken=Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32));invitationExpiry=DateTime.UtcNow.AddMinutes(5);authenticationFailures=0;
            return new(1,address,Port,Fingerprint,invitationToken,profile.Identity.ReplicaId,profile.Identity.DeviceName);
        }
    }
    public async Task QueueSendAsync(CancellationToken token)
    {
        // The UI owns its operation lease. Create also checks for active recording under the store lock.
        string target;
        CancellationTokenSource preparation;
        lock(gate)
        {
            target=connectedPhone??throw new InvalidOperationException("Open LocalMinutes on your paired iPhone first.");
            if(outgoing!=null||preparingSend!=null)throw new InvalidOperationException("A send is already pending.");
            preparation=CancellationTokenSource.CreateLinkedTokenSource(token,lifetime.Token);preparingSend=preparation;
        }
        try
        {
            var folder=Path.Combine(profile.Root,"sync-outgoing",WireJson.NewId());
            await Task.Run(()=>LibraryExchange.Create(profile,store,folder,preparation.Token),preparation.Token);
            lock(gate)
            {
                preparation.Token.ThrowIfCancellationRequested();
                SafeFiles.WriteAtomic(PendingPath,JsonSerializer.SerializeToUtf8Bytes(new PendingSend(Path.GetFileName(folder),target),WireJson.Options));outgoing=folder;outgoingTarget=target;
            }
            Status?.Invoke("Waiting for your iPhone to receive this PC's library…");
        }
        finally {lock(gate){preparingSend=null;preparation.Dispose();}}
    }
    public void ForgetPeers()
    {
        lock(gate) {if(connectedPhone!=null)throw new InvalidOperationException("Disconnect the iPhone before forgetting it.");preparingSend?.Cancel();secrets.Peers.Clear();invitationToken=null;outgoing=null;outgoingTarget=null;if(File.Exists(PendingPath))File.Delete(PendingPath);SaveSecrets();}
    }
    public void CancelPendingSend(){lock(gate){preparingSend?.Cancel();outgoing=null;outgoingTarget=null;if(File.Exists(PendingPath))File.Delete(PendingPath);}Status?.Invoke("Pending PC send cancelled. Meetings were not deleted.");}
    private static bool IsLocal(IPAddress address)
    {
        if(IPAddress.IsLoopback(address)) return true;
        var bytes=address.MapToIPv4().GetAddressBytes();
        return bytes[0]==10 || bytes[0]==192&&bytes[1]==168 || bytes[0]==172&&bytes[1]>=16&&bytes[1]<=31 || bytes[0]==169&&bytes[1]==254;
    }
    private async Task AcceptAsync()
    {
        while(!lifetime.IsCancellationRequested)
        {
            TcpClient? client=null;
            try
            {
                client=await listener!.AcceptTcpClientAsync(lifetime.Token);
                if(client.Client.RemoteEndPoint is not IPEndPoint remote || !IsLocal(remote.Address) || !await sessionAdmission.WaitAsync(0,lifetime.Token)) {client.Dispose();continue;}
                // One peer at a time; the loop owns and observes the whole session, including disconnect recovery.
                try {await SessionAsync(client,lifetime.Token);}
                finally {client.Dispose();client=null;lock(gate) connectedPhone=null;sessionAdmission.Release();}
            }
            catch(OperationCanceledException) when(lifetime.IsCancellationRequested) {client?.Dispose();break;}
            catch(Exception error) when(error is not OutOfMemoryException)
            {client?.Dispose();Status?.Invoke("Sync disconnected. Reopen the iPhone app to retry. "+(error is InvalidDataException?error.Message:""));}
        }
    }
    private async Task SessionAsync(TcpClient client,CancellationToken token)
    {
        incoming=null;
        using var tls=new SslStream(client.GetStream(),false);
        using(var handshake=CancellationTokenSource.CreateLinkedTokenSource(token))
        {
            handshake.CancelAfter(TimeSpan.FromSeconds(15));
            await tls.AuthenticateAsServerAsync(new SslServerAuthenticationOptions{ServerCertificate=certificate,EnabledSslProtocols=SslProtocols.Tls12|SslProtocols.Tls13,ClientCertificateRequired=false},handshake.Token);
            using var hello=await SyncFrames.ReadAsync(tls,handshake.Token);var root=hello.RootElement;
            if(root.GetProperty("command").GetString()!="hello" || root.GetProperty("version").GetInt32()!=1) throw new InvalidDataException("Unsupported sync version.");
            string id=WireJson.Id(root.GetProperty("replicaId").GetString()!);string name=root.GetProperty("name").GetString()!;string supplied=root.GetProperty("token").GetString()!;
            if(id==profile.Identity.ReplicaId || name.Length>80 || supplied.Length!=64) throw new AuthenticationException();
            lock(gate)
            {
                var peer=secrets.Peers.FirstOrDefault(p=>p.ReplicaId==id);
                bool Same(string? secret)=>secret!=null&&CryptographicOperations.FixedTimeEquals(System.Text.Encoding.ASCII.GetBytes(secret),System.Text.Encoding.ASCII.GetBytes(supplied));
                if(peer==null||!Same(peer.Token))
                {
                    if(authenticationFailures>=5 || DateTime.UtcNow>invitationExpiry || !Same(invitationToken)) {authenticationFailures++;throw new AuthenticationException();}
                    secrets.Peers.RemoveAll(p=>p.ReplicaId==id);
                    secrets.Peers.Add(new(id,name,supplied));invitationToken=null;SaveSecrets();
                }
                connectedPhone=id;
            }
            await SyncFrames.WriteAsync(tls,new{status="ready",replicaId=profile.Identity.ReplicaId,name=profile.Identity.DeviceName},handshake.Token);
            Status?.Invoke(name+" connected. Either device can send its library.");
        }
        while(!token.IsCancellationRequested)
        {
            using var timeout=CancellationTokenSource.CreateLinkedTokenSource(token);timeout.CancelAfter(TimeSpan.FromMinutes(2));
            using var message=await SyncFrames.ReadAsync(tls,timeout.Token);var request=message.RootElement;
            switch(request.GetProperty("command").GetString())
            {
                case "poll":
                    string? folder;lock(gate)folder=connectedPhone==outgoingTarget?outgoing:null;
                    if(folder==null) await SyncFrames.WriteAsync(tls,new{status="idle"},token);
                    else
                    {using var manifest=JsonDocument.Parse(await File.ReadAllBytesAsync(Path.Combine(folder,"manifest.json"),token));await SyncFrames.WriteAsync(tls,new{status="offer",manifest=manifest.RootElement},token);}
                    break;
                case "get":
                    string outgoingPath;lock(gate) {if(connectedPhone!=outgoingTarget)throw new AuthenticationException();outgoingPath=outgoing??throw new InvalidOperationException("No outgoing transfer.");}
                    var path=request.GetProperty("path").GetString()!;var offset=request.GetProperty("offset").GetInt64();
                    if(!LibraryExchange.Allowed(path))throw new InvalidDataException("Invalid file request.");
                    await using(var file=File.OpenRead(SafeFiles.Resolve(outgoingPath,path)))
                    {
                        if(offset<0||offset>file.Length)throw new InvalidDataException("Invalid resume offset.");
                        file.Position=offset;int size=(int)Math.Min(65536,file.Length-offset);var buffer=new byte[size];await file.ReadExactlyAsync(buffer,token);
                        await SyncFrames.WriteAsync(tls,new{status="chunk",bytes=size},token);await tls.WriteAsync(buffer,token);
                    }
                    break;
                case "received":
                    lock(gate) {if(connectedPhone!=outgoingTarget)throw new AuthenticationException();if(outgoing==null)throw new InvalidOperationException("No pending send.");using var m=JsonDocument.Parse(File.ReadAllBytes(Path.Combine(outgoing,"manifest.json")));if(m.RootElement.GetProperty("transferId").GetString()!=request.GetProperty("transferId").GetString())throw new InvalidDataException("Wrong receipt.");File.Delete(PendingPath);outgoing=null;outgoingTarget=null;}
                    await SyncFrames.WriteAsync(tls,new{status="complete"},token);Status?.Invoke("iPhone confirmed that your PC library was saved.");break;
                case "push":
                    if(!canSync()) {await SyncFrames.WriteAsync(tls,new{status="busy"},token);break;}
                    var incomingManifest=request.GetProperty("manifest").Deserialize<ExchangeManifest>(WireJson.Options) ?? throw new InvalidDataException("Missing manifest.");
                    if(incomingManifest.SchemaVersion!=1 || incomingManifest.SourceId!=ConnectedPhone || incomingManifest.Files.Count>100_000 || incomingManifest.Files.Count==0)throw new InvalidDataException("Invalid transfer manifest.");
                    var incomingId=WireJson.Id(incomingManifest.TransferId);incoming=Path.Combine(profile.Root,"sync-incoming",incomingId);Directory.CreateDirectory(incoming);
                    var data=JsonSerializer.SerializeToUtf8Bytes(incomingManifest,WireJson.Options);
                    var oldManifest=Path.Combine(incoming,"manifest.json");
                    if(File.Exists(oldManifest)&&!File.ReadAllBytes(oldManifest).SequenceEqual(data))throw new InvalidDataException("Transfer identity changed.");
                    SafeFiles.WriteAtomic(oldManifest,data);
                    var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);long total=0;
                    foreach(var incomingEntry in incomingManifest.Files)
                    {if(!LibraryExchange.Allowed(incomingEntry.RelativePath)||!seen.Add(incomingEntry.RelativePath)||incomingEntry.ByteCount<0||incomingEntry.Sha256.Length!=64||!incomingEntry.Sha256.All(char.IsAsciiHexDigit))throw new InvalidDataException("Invalid transfer file.");total=checked(total+incomingEntry.ByteCount);}
                    long available=new DriveInfo(Path.GetPathRoot(profile.Root)!).AvailableFreeSpace;
                    if(available<total||available-total<100_000_000)throw new IOException("Not enough space to receive the library.");
                    await SyncFrames.WriteAsync(tls,new{status="accept"},token);Status?.Invoke("Receiving iPhone library…");break;
                case "offset":
                    var entry=IncomingFile(request);var part=SafeFiles.Resolve(incoming!,entry.RelativePath)+".part";
                    var completed=SafeFiles.Resolve(incoming!,entry.RelativePath);
                    var local=SafeFiles.Resolve(profile.LibraryRoot,entry.RelativePath);
                    if(!File.Exists(completed)&&File.Exists(local)&&new FileInfo(local).Length==entry.ByteCount&&await SafeFiles.HashAsync(local,token)==entry.Sha256)
                    {Directory.CreateDirectory(Path.GetDirectoryName(completed)!);File.Copy(local,completed);}
                    long have=File.Exists(completed)&&await SafeFiles.HashAsync(completed,token)==entry.Sha256?entry.ByteCount:File.Exists(part)?new FileInfo(part).Length:0;
                    if(have>entry.ByteCount)have=0;
                    await SyncFrames.WriteAsync(tls,new{status="offset",offset=have},token);break;
                case "put":
                    var targetFile=IncomingFile(request);var targetPath=SafeFiles.Resolve(incoming!,targetFile.RelativePath);Directory.CreateDirectory(Path.GetDirectoryName(targetPath)!);
                    int bytes=request.GetProperty("bytes").GetInt32();long start=request.GetProperty("offset").GetInt64();
                    if(bytes is <1 or >65536 || start<0 || start>targetFile.ByteCount-bytes)throw new InvalidDataException("Invalid transfer chunk.");
                    var chunk=new byte[bytes];await tls.ReadExactlyAsync(chunk,timeout.Token);
                    await using(var target=new FileStream(targetPath+".part",FileMode.OpenOrCreate,FileAccess.Write,FileShare.None))
                    {SafeFiles.RequireSingleLink(target);if(start==0)target.SetLength(0);if(target.Length!=start)throw new InvalidDataException("Unexpected chunk offset.");target.Position=start;await target.WriteAsync(chunk,token);target.Flush(true);}
                    if(start+bytes==targetFile.ByteCount)
                    {if(await SafeFiles.HashAsync(targetPath+".part",token)!=targetFile.Sha256) {File.Delete(targetPath+".part");throw new InvalidDataException("File checksum mismatch.");}File.Move(targetPath+".part",targetPath,true);}
                    await SyncFrames.WriteAsync(tls,new{status="saved",offset=start+bytes},token);break;
                case "commit":
                    if(!canSync()) {await SyncFrames.WriteAsync(tls,new{status="busy"},token);break;}
                    if(incoming==null)throw new InvalidOperationException("No incoming transfer.");
                    foreach(var file in JsonSerializer.Deserialize<ExchangeManifest>(File.ReadAllBytes(Path.Combine(incoming,"manifest.json")),WireJson.Options)!.Files.Where(x=>x.ByteCount==0))
                    {var empty=SafeFiles.Resolve(incoming,file.RelativePath);Directory.CreateDirectory(Path.GetDirectoryName(empty)!);if(!File.Exists(empty))File.WriteAllBytes(empty,[]);}
                    if(PreparingImport!=null)await PreparingImport();
                    try
                    {
                        var receipt=await Task.Run(()=>LibraryExchange.Apply(profile,store,incoming),token);
                        await SyncFrames.WriteAsync(tls,new{status="complete",receipt},token);Status?.Invoke("iPhone library saved on this PC.");Imported?.Invoke();incoming=null;
                    }
                    finally{ImportFinished?.Invoke();}
                    break;
                default: throw new InvalidDataException("Unknown sync command.");
            }
        }
    }
    private ExchangeFile IncomingFile(JsonElement request)
    {
        if(incoming==null)throw new InvalidOperationException("No incoming transfer.");
        var manifest=JsonSerializer.Deserialize<ExchangeManifest>(File.ReadAllBytes(Path.Combine(incoming,"manifest.json")),WireJson.Options)!;
        return manifest.Files.FirstOrDefault(x=>x.RelativePath==request.GetProperty("path").GetString()) ?? throw new InvalidDataException("File is not in the manifest.");
    }
    public async ValueTask DisposeAsync()
    {
        lifetime.Cancel();listener?.Stop();if(acceptLoop!=null)try{await acceptLoop;}catch(OperationCanceledException){}
        advertisement?.Dispose();certificate.Dispose();lifetime.Dispose();sessionAdmission.Dispose();listener=null;
    }
}
