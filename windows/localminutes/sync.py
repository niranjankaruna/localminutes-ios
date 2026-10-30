from __future__ import annotations

import base64
import ctypes
from ctypes import wintypes
from contextlib import contextmanager, nullcontext
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import ipaddress
import os
from pathlib import Path
import secrets
import select
import shutil
import socket
import ssl
import struct
import tempfile
import threading
import time

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID
import ifaddr
from zeroconf import ServiceInfo, Zeroconf

from . import exchange
from .files import atomic_write, check_cancel, copy_file, decode_json, digest, identifier, json_bytes, read_json, safe_path


def protect(data: bytes, *, decrypt=False) -> bytes:
    class Blob(ctypes.Structure):
        _fields_ = [("size", wintypes.DWORD), ("data", ctypes.POINTER(ctypes.c_ubyte))]
    crypt = ctypes.WinDLL("crypt32", use_last_error=True)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    fn = crypt.CryptUnprotectData if decrypt else crypt.CryptProtectData
    fn.argtypes = [ctypes.POINTER(Blob), ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(Blob)]
    fn.restype = wintypes.BOOL
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    kernel.LocalFree.restype = ctypes.c_void_p
    backing = (ctypes.c_ubyte * len(data)).from_buffer_copy(data)
    incoming, outgoing = Blob(len(data), backing), Blob()
    if not fn(ctypes.byref(incoming), None, None, None, None, 1, ctypes.byref(outgoing)):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        return ctypes.string_at(outgoing.data, outgoing.size)
    finally:
        ctypes.memset(outgoing.data, 0, outgoing.size)
        kernel.LocalFree(outgoing.data)


def is_local(address: str) -> bool:
    try:
        value = ipaddress.IPv4Address(address)
        return value.is_loopback or any(value in ipaddress.IPv4Network(network) for network in ("10.0.0.0/8", "192.168.0.0/16", "172.16.0.0/12", "169.254.0.0/16"))
    except ipaddress.AddressValueError:
        return False


def local_addresses() -> list[str]:
    return list(dict.fromkeys(address.ip for adapter in ifaddr.get_adapters() for address in adapter.ips
                             if isinstance(address.ip, str) and is_local(address.ip) and not ipaddress.ip_address(address.ip).is_loopback))


class CancellableTLS:
    """Nonblocking SSL with a total operation deadline and prompt shutdown."""
    def __init__(self, channel, stopping):
        self.channel, self.stopping = channel, stopping
        self.timeout = 15
        self.deadline = None
        channel.setblocking(False)

    def settimeout(self, seconds):
        self.timeout = seconds

    @contextmanager
    def operation(self):
        previous = self.deadline
        if previous is None:
            self.deadline = time.monotonic() + self.timeout
        try:
            yield
        finally:
            self.deadline = previous

    def perform(self, action):
        with self.operation():
            while True:
                check_cancel(self.stopping)
                remaining = self.deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("Sync operation timed out.")
                try:
                    return action()
                except ssl.SSLWantReadError:
                    select.select([self.channel], [], [], min(remaining, 0.1))
                except ssl.SSLWantWriteError:
                    select.select([], [self.channel], [], min(remaining, 0.1))

    def recv(self, count):
        return self.perform(lambda: self.channel.recv(count))

    def sendall(self, data):
        with self.operation():
            pending = memoryview(data)
            while pending:
                count = self.perform(lambda: self.channel.send(pending))
                if count == 0:
                    raise ConnectionError("Sync connection closed.")
                pending = pending[count:]


def receive_exact(channel, count: int) -> bytes:
    with channel.operation() if isinstance(channel, CancellableTLS) else nullcontext():
        data = bytearray()
        while len(data) < count:
            chunk = channel.recv(min(65536, count - len(data)))
            if not chunk:
                raise ConnectionError("Sync connection closed.")
            data.extend(chunk)
        return bytes(data)


def read_frame(channel) -> dict:
    with channel.operation() if isinstance(channel, CancellableTLS) else nullcontext():
        size = struct.unpack(">I", receive_exact(channel, 4))[0]
        if not 2 <= size <= exchange.MAX_FRAME:
            raise ValueError("Invalid protocol frame size.")
        message = decode_json(receive_exact(channel, size))
        if not isinstance(message, dict):
            raise ValueError("Expected a control message.")
        return message


def write_frame(channel, message) -> None:
    data = json_bytes(message)
    if not 2 <= len(data) <= exchange.MAX_FRAME:
        raise ValueError("Oversized protocol message.")
    channel.sendall(struct.pack(">I", len(data)) + data)


class SyncHost:
    def __init__(self, profile, store, can_sync=lambda: True, status=lambda text: None,
                 prepare_import=lambda: None, finish_import=lambda: None, imported=lambda: None):
        self.profile, self.store, self.can_sync, self.status = profile, store, can_sync, status
        self.prepare_import, self.finish_import, self.imported = prepare_import, finish_import, imported
        self.lock = threading.RLock()
        self.stopping = threading.Event()
        self.listener = self.channel = self.thread = None
        self.discovery = self.discovery_thread = None
        self.connected_phone = None
        self.invitation_token = None
        self.invitation_expiry = 0
        self.failures = 0
        self.preparing = None
        self.outgoing = self.outgoing_target = None
        self.pending_path = profile.root / "pending-send.json"
        self.secret_path = profile.root / "identity" / "sync.dat"
        self.secrets = None
        if self.secret_path.exists():
            try:
                if self.secret_path.stat().st_size > 1048576:
                    raise ValueError("Invalid sync identity.")
                self.secrets = decode_json(protect(self.secret_path.read_bytes(), decrypt=True))
            except OSError:
                os.replace(self.secret_path, self.secret_path.with_suffix(".dat.previous"))
        if self.secrets is None:
            key = ec.generate_private_key(ec.SECP256R1())
            name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "LocalMinutes " + profile.identity["replicaId"])])
            now = datetime.now(timezone.utc)
            certificate = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
                           .serial_number(x509.random_serial_number()).not_valid_before(now - timedelta(days=1))
                           .not_valid_after(now + timedelta(days=1825)).sign(key, hashes.SHA256()))
            pfx = pkcs12.serialize_key_and_certificates(b"LocalMinutes", key, certificate, None, serialization.NoEncryption())
            self.secrets = dict(certificatePfx=base64.b64encode(pfx).decode("ascii"), peers=[])
            self._save_secrets()
        key, certificate, _ = pkcs12.load_key_and_certificates(base64.b64decode(self.secrets["certificatePfx"], validate=True), None)
        if key is None or certificate is None:
            raise ValueError("Invalid sync certificate.")
        self.fingerprint = certificate.fingerprint(hashes.SHA256()).hex()
        self.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.context.minimum_version = ssl.TLSVersion.TLSv1_2
        runtime = safe_path(profile.root, "runtime")
        runtime.mkdir(parents=True, exist_ok=True)
        # SSL loads the encrypted PEM into memory; temporary key material is removed immediately.
        with tempfile.TemporaryDirectory(prefix="tls-", dir=runtime) as temporary:
            password = secrets.token_bytes(32)
            pem_key = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.BestAvailableEncryption(password))
            key_path, cert_path = Path(temporary) / "key.pem", Path(temporary) / "certificate.pem"
            key_path.write_bytes(pem_key)
            cert_path.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
            self.context.load_cert_chain(cert_path, key_path, password)
        if self.pending_path.exists():
            pending = read_json(self.pending_path, 4096)
            folder = safe_path(profile.root, "sync-outgoing/" + identifier(pending["directoryName"]))
            target = identifier(pending["targetId"])
            if any(peer["replicaId"] == target for peer in self.secrets["peers"]) and (folder / "manifest.json").is_file():
                self.outgoing, self.outgoing_target = folder, target
            else:
                self.pending_path.unlink()

    def _save_secrets(self):
        atomic_write(self.secret_path, protect(json_bytes(self.secrets)))

    @property
    def port(self):
        return self.listener.getsockname()[1] if self.listener else 0

    def start(self, address="0.0.0.0", port=47835):
        if self.listener:
            return
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        try:
            listener.bind((address, port))
            listener.listen(4)
            listener.settimeout(0.5)
        except BaseException:
            listener.close()
            raise
        self.listener = listener
        self.thread = threading.Thread(target=self._accept, name="local-sync", daemon=True)
        self.thread.start()
        if address != "127.0.0.1":
            self.discovery_thread = threading.Thread(target=self._advertise, name="local-discovery", daemon=True)
            self.discovery_thread.start()
        self.status("Ready on your local network. Open Sync on your iPhone.")

    def _advertise(self):
        discovery = None
        info = None
        addresses = None
        try:
            discovery = Zeroconf()
            self.discovery = discovery
            while not self.stopping.is_set():
                current = local_addresses()
                if current and current != addresses:
                    if info:
                        discovery.unregister_service(info)
                    device_id = self.profile.identity["replicaId"]
                    name = f"LocalMinutes-{device_id}._localminutes._tcp.local."
                    info = ServiceInfo("_localminutes._tcp.local.", name, addresses=[socket.inet_aton(ip) for ip in current],
                                       port=self.port, properties={"id": device_id, "v": "1"}, server=f"localminutes-{device_id.lower()}.local.")
                    discovery.register_service(info)
                    addresses = current
                self.stopping.wait(5)
        except Exception:
            if not self.stopping.is_set():
                self.status("Discovery is unavailable. Pair using the address in the QR invitation.")
        finally:
            if discovery:
                if info:
                    discovery.unregister_service(info)
                discovery.close()
            self.discovery = None

    def invite(self, address):
        if not self.listener:
            self.start()
        loopback = self.listener.getsockname()[0] == "127.0.0.1" and address == "127.0.0.1"
        if not loopback and address not in local_addresses():
            raise ValueError("Select this PC's local Wi-Fi or Ethernet address.")
        with self.lock:
            self.invitation_token = secrets.token_hex(32)
            self.invitation_expiry = time.monotonic() + 300
            self.failures = 0
            return dict(version=1, host=address, port=self.port, fingerprint=self.fingerprint, token=self.invitation_token,
                        replicaId=self.profile.identity["replicaId"], name=self.profile.identity["deviceName"])

    def queue_send(self, cancel=None):
        with self.lock:
            if not self.connected_phone:
                raise ValueError("Open Sync on your paired iPhone first.")
            if self.outgoing or self.preparing:
                raise ValueError("A PC send is already pending.")
            target = self.connected_phone
            preparation = threading.Event()
            self.preparing = preparation
        host = self
        class CombinedCancellation:
            def is_set(self):
                return preparation.is_set() or host.stopping.is_set() or (cancel is not None and cancel.is_set())
        combined = CombinedCancellation()
        try:
            folder = safe_path(self.profile.root, "sync-outgoing/" + identifier())
            exchange.create(self.profile, self.store, folder, combined)
            with self.lock:
                check_cancel(combined)
                atomic_write(self.pending_path, json_bytes(dict(directoryName=folder.name, targetId=target)))
                self.outgoing, self.outgoing_target = folder, target
            self.status("Waiting for your iPhone to receive this PC's library…")
        finally:
            with self.lock:
                self.preparing = None

    def cancel_send(self):
        with self.lock:
            if self.preparing:
                self.preparing.set()
            self.outgoing = self.outgoing_target = None
            self.pending_path.unlink(missing_ok=True)
        self.status("Pending PC send cancelled. Saved meetings remain.")

    def forget(self):
        with self.lock:
            if self.connected_phone:
                raise ValueError("Disconnect the iPhone before forgetting it.")
            self.cancel_send()
            self.secrets["peers"].clear()
            self.invitation_token = None
            self._save_secrets()

    def _accept(self):
        while not self.stopping.is_set():
            try:
                client, remote = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                if self.stopping.is_set():
                    break
                continue
            try:
                with client:
                    if not is_local(remote[0]):
                        continue
                    client.settimeout(15)
                    with self.context.wrap_socket(client, server_side=True, do_handshake_on_connect=False) as channel:
                        self.channel = channel
                        transport = CancellableTLS(channel, self.stopping)
                        transport.perform(channel.do_handshake)
                        self._session(transport)
            except Exception as error:
                if not self.stopping.is_set():
                    self.status("Sync disconnected. Reconnect from iPhone." + (" " + str(error) if isinstance(error, ValueError) else ""))
            finally:
                self.channel = None
                with self.lock:
                    self.connected_phone = None

    def _session(self, channel):
        hello = read_frame(channel)
        if hello.get("command") != "hello" or hello.get("version") != 1:
            raise ValueError("Unsupported sync version.")
        peer_id, name, token = identifier(hello["replicaId"]), hello["name"], hello["token"]
        if peer_id == self.profile.identity["replicaId"] or not isinstance(name, str) or len(name) > 80 or not isinstance(token, str) or len(token) != 64:
            raise ValueError("Invalid peer identity.")
        with self.lock:
            peer = next((peer for peer in self.secrets["peers"] if peer["replicaId"] == peer_id), None)
            if not peer or not hmac.compare_digest(peer["token"], token):
                if self.failures >= 5 or time.monotonic() > self.invitation_expiry or not self.invitation_token or not hmac.compare_digest(self.invitation_token, token):
                    self.failures += 1
                    raise ValueError("Pairing invitation expired or was not accepted.")
                self.secrets["peers"] = [peer for peer in self.secrets["peers"] if peer["replicaId"] != peer_id]
                self.secrets["peers"].append(dict(replicaId=peer_id, name=name, token=token))
                self.invitation_token = None
                self._save_secrets()
            self.connected_phone = peer_id
        write_frame(channel, dict(status="ready", replicaId=self.profile.identity["replicaId"], name=self.profile.identity["deviceName"]))
        channel.settimeout(120)
        self.status(name + " connected. Either device can send its library.")
        incoming = None
        manifest = None
        entries = {}
        while not self.stopping.is_set():
            request = read_frame(channel)
            command = request.get("command")
            if command == "poll":
                with self.lock:
                    folder = self.outgoing if peer_id == self.outgoing_target else None
                write_frame(channel, dict(status="offer", manifest=read_json(folder / "manifest.json")) if folder else dict(status="idle"))
            elif command in ("get", "received"):
                with self.lock:
                    if peer_id != self.outgoing_target or self.outgoing is None:
                        raise ValueError("No pending transfer for this device.")
                    folder = self.outgoing
                    outgoing = read_json(folder / "manifest.json")
                    if command == "received":
                        if outgoing["transferId"] != request["transferId"]:
                            raise ValueError("Transfer receipt does not match.")
                        self.pending_path.unlink()
                        self.outgoing = self.outgoing_target = None
                if command == "received":
                    write_frame(channel, dict(status="complete"))
                    self.status("iPhone confirmed that your library was saved.")
                    continue
                relative, offset = request["path"], request["offset"]
                if not any(entry["relativePath"] == relative for entry in outgoing["files"]):
                    raise ValueError("File is not in the transfer manifest.")
                path = safe_path(folder, relative)
                if type(offset) is not int or not 0 <= offset <= path.stat().st_size:
                    raise ValueError("Invalid transfer offset.")
                with path.open("rb") as stream:
                    stream.seek(offset)
                    data = stream.read(65536)
                write_frame(channel, dict(status="chunk", bytes=len(data)))
                channel.sendall(data)
            elif command == "push":
                if not self.can_sync():
                    write_frame(channel, dict(status="busy"))
                    continue
                manifest = request["manifest"]
                total = exchange.validate_manifest(manifest)
                if manifest["sourceId"] != peer_id:
                    raise ValueError("Transfer source identity does not match.")
                if shutil.disk_usage(self.profile.root).free < total + 100000000:
                    raise ValueError("Not enough storage to receive the library.")
                incoming = safe_path(self.profile.root, "sync-incoming/" + manifest["transferId"])
                incoming.mkdir(parents=True, exist_ok=True)
                prior = incoming / "manifest.json"
                if prior.exists() and read_json(prior) != manifest:
                    raise ValueError("Transfer identity was reused with different data.")
                atomic_write(prior, json_bytes(manifest))
                entries = {entry["relativePath"]: entry for entry in manifest["files"]}
                write_frame(channel, dict(status="accept"))
                self.status("Receiving iPhone library…")
            elif command in ("offset", "put"):
                if incoming is None or request["path"] not in entries:
                    raise ValueError("File is not in the current manifest.")
                entry = entries[request["path"]]
                target = safe_path(incoming, entry["relativePath"])
                partial = safe_path(target.parent, target.name + ".part")
                if command == "offset":
                    local = safe_path(self.profile.library, entry["relativePath"])
                    if not target.exists() and local.exists() and local.stat().st_size == entry["byteCount"] and digest(local, self.stopping) == entry["sha256"]:
                        copy_file(local, target, self.stopping)
                    complete = target.exists() and target.stat().st_size == entry["byteCount"] and digest(target, self.stopping) == entry["sha256"]
                    offset = entry["byteCount"] if complete else partial.stat().st_size if partial.exists() else 0
                    write_frame(channel, dict(status="offset", offset=offset if offset <= entry["byteCount"] else 0))
                else:
                    size, offset = request["bytes"], request["offset"]
                    if type(size) is not int or not 1 <= size <= 65536 or type(offset) is not int or not 0 <= offset <= entry["byteCount"] - size:
                        raise ValueError("Invalid transfer chunk.")
                    data = receive_exact(channel, size)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with partial.open("r+b" if partial.exists() else "x+b") as stream:
                        if offset == 0:
                            stream.truncate(0)
                        stream.seek(0, os.SEEK_END)
                        if stream.tell() != offset:
                            raise ValueError("Unexpected transfer offset.")
                        stream.write(data)
                        stream.flush()
                        os.fsync(stream.fileno())
                    if offset + size == entry["byteCount"]:
                        if digest(partial, self.stopping) != entry["sha256"]:
                            partial.unlink()
                            raise ValueError("Transfer checksum mismatch.")
                        os.replace(partial, target)
                    write_frame(channel, dict(status="saved", offset=offset + size))
            elif command == "commit":
                if not self.can_sync():
                    write_frame(channel, dict(status="busy"))
                    continue
                if incoming is None:
                    raise ValueError("No incoming transfer.")
                for entry in manifest["files"]:
                    if entry["byteCount"] == 0:
                        target = safe_path(incoming, entry["relativePath"])
                        if not target.exists():
                            atomic_write(target, b"")
                self.prepare_import()
                try:
                    receipt = exchange.apply(self.profile, self.store, incoming, self.stopping)
                    write_frame(channel, dict(status="complete", receipt=receipt))
                    self.status("iPhone library saved on this PC.")
                    self.imported()
                    incoming = None
                finally:
                    self.finish_import()
            else:
                raise ValueError("Unknown sync command.")

    def close(self):
        self.stopping.set()
        if self.channel:
            try:
                self.channel.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        if self.listener:
            self.listener.close()
        if self.thread:
            self.thread.join()
        if self.discovery_thread:
            self.discovery_thread.join()
        self.listener = self.thread = None
