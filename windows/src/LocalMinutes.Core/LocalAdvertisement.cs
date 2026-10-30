using System.Net;
using System.Net.NetworkInformation;
using Makaretu.Dns;

namespace LocalMinutes.Core;

/// <summary>DNS-SD hints only: the TLS certificate and pairing token remain the authority.</summary>
public sealed class LocalAdvertisement : IDisposable
{
    private readonly string replicaId;
    private readonly ushort port;
    private readonly object gate=new();
    private ServiceDiscovery? discovery;
    private bool disposed;
    public LocalAdvertisement(string replicaId,ushort port)
    {
        this.replicaId=WireJson.Id(replicaId);this.port=port;
        NetworkChange.NetworkAddressChanged+=AddressChanged;
        try{Refresh();}catch{NetworkChange.NetworkAddressChanged-=AddressChanged;throw;}
    }
    private void AddressChanged(object? sender,EventArgs args)
    {try{Refresh();}catch(System.Net.Sockets.SocketException){ }catch(InvalidOperationException){ }}
    private void Refresh()
    {
        lock(gate)
        {
            if(disposed)return;
            discovery?.Dispose();discovery=null;
            var addresses=SyncHost.LocalAddresses().Take(1).Select(IPAddress.Parse).ToArray();if(addresses.Length==0)return;
            var service=new ServiceProfile("LocalMinutes-"+replicaId,"_localminutes._tcp",port,addresses);
            service.AddProperty("id",replicaId);service.AddProperty("v","1");
            var next=new ServiceDiscovery();
            try{next.Advertise(service);discovery=next;}
            catch{next.Dispose();throw;}
        }
    }
    public void Dispose()
    {
        NetworkChange.NetworkAddressChanged-=AddressChanged;
        lock(gate)
        {
            disposed=true;
            try{discovery?.Unadvertise();}catch(System.Net.Sockets.SocketException){ }
            finally{discovery?.Dispose();discovery=null;}
        }
    }
}
