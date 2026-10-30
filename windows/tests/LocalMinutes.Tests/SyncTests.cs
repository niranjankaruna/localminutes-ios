using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;
using LocalMinutes.Core;
using Xunit;

namespace LocalMinutes.Tests;

public sealed class SyncTests : IDisposable
{
    private readonly string root=Path.Combine(AppContext.BaseDirectory,"sync-tests",Guid.NewGuid().ToString("N"));
    private readonly CancellationTokenSource timeout=new(TimeSpan.FromSeconds(30));
    public SyncTests()=>Directory.CreateDirectory(root);
    private async Task<(TcpClient Client,SslStream Stream)> Connect(PairInvitation invitation,string id,string? token=null)
    {
        var client=new TcpClient();await client.ConnectAsync(IPAddress.Loopback,invitation.Port,timeout.Token);
        var stream=new SslStream(client.GetStream(),false,(_,certificate,_,_)=>certificate!=null&&Convert.ToHexStringLower(SHA256.HashData(certificate.GetRawCertData()))==invitation.Fingerprint);
        await stream.AuthenticateAsClientAsync(new SslClientAuthenticationOptions{TargetHost="LocalMinutes"},timeout.Token);
        await SyncFrames.WriteAsync(stream,new{command="hello",version=1,replicaId=id,name="Synthetic iPhone",token=token??invitation.Token},timeout.Token);
        return(client,stream);
    }
    private async Task<JsonDocument> Request(SslStream stream,object message)
    {await SyncFrames.WriteAsync(stream,message,timeout.Token);return await SyncFrames.ReadAsync(stream,timeout.Token);}
    [Fact] public async Task PinnedTlsPairingPushResumeAndPcSendRoundTrip()
    {
        using var pc=new PortableProfile(Path.Combine(root,"pc"));using var store=new MeetingStore(pc.DatabasePath);
        using var phone=new PortableProfile(Path.Combine(root,"phone"));using var source=new MeetingStore(phone.DatabasePath);
        var meeting=new Meeting(WireJson.NewId(),"Phone meeting",1700000000,"completed",0);source.Create(meeting);source.SaveNote(meeting.Id,"Phone note",0);
        var snapshot=Path.Combine(root,"outgoing");var manifest=LibraryExchange.Create(phone,source,snapshot);
        await using var host=new SyncHost(pc,store,()=>true);host.Start(IPAddress.Loopback,0);var invitation=host.Invite("127.0.0.1");
        var first=await Connect(invitation,phone.Identity.ReplicaId);
        using(first.Client)using(first.Stream)
        {
            using var hello=await SyncFrames.ReadAsync(first.Stream,timeout.Token);Assert.Equal("ready",hello.RootElement.GetProperty("status").GetString());
            using var offer=await Request(first.Stream,new{command="push",manifest});Assert.Equal("accept",offer.RootElement.GetProperty("status").GetString());
            var bytes=File.ReadAllBytes(Path.Combine(snapshot,"records.jsonl"));int count=32;
            await SyncFrames.WriteAsync(first.Stream,new{command="put",path="records.jsonl",offset=0,bytes=count},timeout.Token);
            await first.Stream.WriteAsync(bytes.AsMemory(0,count),timeout.Token);
            using var ack=await SyncFrames.ReadAsync(first.Stream,timeout.Token);Assert.Equal(count,ack.RootElement.GetProperty("offset").GetInt32());
        }
        var second=await Connect(invitation,phone.Identity.ReplicaId);
        using(second.Client)using(second.Stream)
        {
            using var hello=await SyncFrames.ReadAsync(second.Stream,timeout.Token);Assert.Equal("ready",hello.RootElement.GetProperty("status").GetString());
            using var offer=await Request(second.Stream,new{command="push",manifest});
            using var offset=await Request(second.Stream,new{command="offset",path="records.jsonl"});Assert.Equal(32,offset.RootElement.GetProperty("offset").GetInt32());
            var bytes=File.ReadAllBytes(Path.Combine(snapshot,"records.jsonl"));
            await SyncFrames.WriteAsync(second.Stream,new{command="put",path="records.jsonl",offset=32,bytes=bytes.Length-32},timeout.Token);
            await second.Stream.WriteAsync(bytes.AsMemory(32),timeout.Token);using var ack=await SyncFrames.ReadAsync(second.Stream,timeout.Token);
            using var committed=await Request(second.Stream,new{command="commit"});Assert.Equal("complete",committed.RootElement.GetProperty("status").GetString());
            Assert.Equal("Phone note",store.Note(meeting.Id)!.Text);
            store.Rename(meeting.Id,"PC title");await host.QueueSendAsync(timeout.Token);
            using var poll=await Request(second.Stream,new{command="poll"});Assert.Equal("offer",poll.RootElement.GetProperty("status").GetString());
            var outgoing=poll.RootElement.GetProperty("manifest").Deserialize<ExchangeManifest>(WireJson.Options)!;
            var received=Path.Combine(root,"received");Directory.CreateDirectory(received);
            File.WriteAllBytes(Path.Combine(received,"manifest.json"),JsonSerializer.SerializeToUtf8Bytes(outgoing,WireJson.Options));
            foreach(var file in outgoing.Files)
            {
                using var output=File.Create(Path.Combine(received,file.RelativePath));long at=0;
                while(at<file.ByteCount)
                {
                    using var response=await Request(second.Stream,new{command="get",path=file.RelativePath,offset=at});int size=response.RootElement.GetProperty("bytes").GetInt32();var chunk=new byte[size];
                    await second.Stream.ReadExactlyAsync(chunk,timeout.Token);output.Write(chunk);at+=size;
                }
            }
            LibraryExchange.Apply(phone,source,received);Assert.Equal("PC title",source.Meetings()[0].Title);
            using var receipt=await Request(second.Stream,new{command="received",transferId=outgoing.TransferId});Assert.Equal("complete",receipt.RootElement.GetProperty("status").GetString());
        }
    }
    [Fact] public async Task QueuedPcSendSurvivesRestartAndCancellationIsPersistent()
    {
        using var pc=new PortableProfile(Path.Combine(root,"pc"));using var store=new MeetingStore(pc.DatabasePath);
        store.Create(new(WireJson.NewId(),"Restart test",1700000000,"completed",0));
        var phoneId=WireJson.NewId();PairInvitation invitation;string transferId;
        await using(var first=new SyncHost(pc,store,()=>true))
        {
            first.Start(IPAddress.Loopback,0);invitation=first.Invite("127.0.0.1");
            var connection=await Connect(invitation,phoneId);
            using(connection.Client)using(connection.Stream)
            {
                using var hello=await SyncFrames.ReadAsync(connection.Stream,timeout.Token);
                await first.QueueSendAsync(timeout.Token);
                using var offered=await Request(connection.Stream,new{command="poll"});
                transferId=offered.RootElement.GetProperty("manifest").GetProperty("transferId").GetString()!;
            }
        }
        await using(var resumed=new SyncHost(pc,store,()=>true))
        {
            resumed.Start(IPAddress.Loopback,0);
            Assert.Equal(invitation.Fingerprint,resumed.Fingerprint);
            var connection=await Connect(invitation with{Port=resumed.Port},phoneId);
            using(connection.Client)using(connection.Stream)
            {
                using var hello=await SyncFrames.ReadAsync(connection.Stream,timeout.Token);
                using var offered=await Request(connection.Stream,new{command="poll"});
                Assert.Equal(transferId,offered.RootElement.GetProperty("manifest").GetProperty("transferId").GetString());
                resumed.CancelPendingSend();
                using var cancelled=await Request(connection.Stream,new{command="poll"});
                Assert.Equal("idle",cancelled.RootElement.GetProperty("status").GetString());
            }
        }
        await using(var final=new SyncHost(pc,store,()=>true))
        {
            final.Start(IPAddress.Loopback,0);var connection=await Connect(invitation with{Port=final.Port},phoneId);
            using(connection.Client)using(connection.Stream)
            {
                using var hello=await SyncFrames.ReadAsync(connection.Stream,timeout.Token);
                using var offered=await Request(connection.Stream,new{command="poll"});
                Assert.Equal("idle",offered.RootElement.GetProperty("status").GetString());
                using var cancelled=new CancellationTokenSource();cancelled.Cancel();
                await Assert.ThrowsAnyAsync<OperationCanceledException>(()=>final.QueueSendAsync(cancelled.Token));
                Assert.False(File.Exists(Path.Combine(pc.Root,"pending-send.json")));
                Assert.Single(store.Meetings());
            }
        }
    }
    [Fact] public async Task IncorrectPairingSecretNeverExposesLibrary()
    {
        using var pc=new PortableProfile(Path.Combine(root,"pc"));using var store=new MeetingStore(pc.DatabasePath);
        await using var host=new SyncHost(pc,store,()=>true);host.Start(IPAddress.Loopback,0);var invitation=host.Invite("127.0.0.1");
        var connection=await Connect(invitation,WireJson.NewId(),new string('0',64));
        using(connection.Client)using(connection.Stream)await Assert.ThrowsAnyAsync<IOException>(()=>SyncFrames.ReadAsync(connection.Stream,timeout.Token));
        Assert.Empty(host.Peers);
    }
    public void Dispose()
    {timeout.Dispose();if(!Path.GetFullPath(root).StartsWith(Path.Combine(AppContext.BaseDirectory,"sync-tests")+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException();Directory.Delete(root,true);}
}
