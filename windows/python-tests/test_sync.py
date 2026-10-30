import hashlib
import socket
import ssl
import time

import pytest

from localminutes import exchange
from localminutes.files import Profile, identifier, json_bytes
from localminutes.store import Store
from localminutes.sync import SyncHost, read_frame, receive_exact, write_frame


@pytest.fixture
def host(tmp_path):
    profile = Profile(tmp_path / "pc")
    store = Store(profile.database)
    host = SyncHost(profile, store)
    host.start("127.0.0.1", 0)
    yield host, profile, store
    host.close(); store.close(); profile.close()


def connect(invitation, peer, token=None):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False; context.verify_mode = ssl.CERT_NONE
    channel = context.wrap_socket(socket.create_connection(("127.0.0.1", invitation["port"]), timeout=5), server_hostname="LocalMinutes")
    assert hashlib.sha256(channel.getpeercert(binary_form=True)).hexdigest() == invitation["fingerprint"]
    write_frame(channel, dict(command="hello", version=1, replicaId=peer, name="Synthetic iPhone", token=token or invitation["token"]))
    return channel


def request(channel, message):
    write_frame(channel, message)
    return read_frame(channel)


def test_real_tls_push_resume_and_pc_send(host, tmp_path):
    server, pc, target = host
    phone = Profile(tmp_path / "phone"); source = Store(phone.database)
    try:
        meeting = source.create("From phone"); source.save_note(meeting["id"], "Original note", 0)
        snapshot = tmp_path / "source"; manifest = exchange.create(phone, source, snapshot)
        invitation = server.invite("127.0.0.1")
        data = (snapshot / "records.jsonl").read_bytes()
        with connect(invitation, phone.identity["replicaId"]) as channel:
            assert read_frame(channel)["status"] == "ready"
            assert request(channel, dict(command="push", manifest=manifest))["status"] == "accept"
            write_frame(channel, dict(command="put", path="records.jsonl", offset=0, bytes=32)); channel.sendall(data[:32])
            assert read_frame(channel)["offset"] == 32
        with connect(invitation, phone.identity["replicaId"]) as channel:
            read_frame(channel)
            request(channel, dict(command="push", manifest=manifest))
            assert request(channel, dict(command="offset", path="records.jsonl"))["offset"] == 32
            write_frame(channel, dict(command="put", path="records.jsonl", offset=32, bytes=len(data) - 32)); channel.sendall(data[32:]); read_frame(channel)
            assert request(channel, dict(command="commit"))["status"] == "complete"
            assert target.get("note", meeting["id"])["text"] == "Original note"
            target.rename(meeting["id"], "PC title"); server.queue_send()
            outgoing = request(channel, dict(command="poll"))["manifest"]
            received = tmp_path / "received"; received.mkdir(); (received / "manifest.json").write_bytes(json_bytes(outgoing))
            for entry in outgoing["files"]:
                with (received / entry["relativePath"]).open("wb") as stream:
                    offset = 0
                    while offset < entry["byteCount"]:
                        chunk = request(channel, dict(command="get", path=entry["relativePath"], offset=offset))
                        stream.write(receive_exact(channel, chunk["bytes"])); offset += chunk["bytes"]
            exchange.apply(phone, source, received)
            assert source.get("meeting", meeting["id"])["title"] == "PC title"
            assert request(channel, dict(command="received", transferId=outgoing["transferId"]))["status"] == "complete"
    finally:
        source.close(); phone.close()


def test_wrong_secret_cannot_access_library(host):
    server, _, _ = host
    invitation = server.invite("127.0.0.1")
    with connect(invitation, identifier(), "0" * 64) as channel:
        with pytest.raises((ConnectionError, OSError)):
            read_frame(channel)
    assert server.secrets["peers"] == []


def test_close_interrupts_an_unfinished_tls_handshake(host):
    server, _, _ = host
    with socket.create_connection(("127.0.0.1", server.port), timeout=5):
        deadline = time.monotonic() + 3
        while server.channel is None and time.monotonic() < deadline:
            time.sleep(0.01)
        assert server.channel is not None
        start = time.monotonic()
        server.close()
        assert time.monotonic() - start < 2


def test_pending_send_survives_restart_and_cancel(tmp_path):
    profile = Profile(tmp_path / "pc"); store = Store(profile.database)
    first = SyncHost(profile, store); first.start("127.0.0.1", 0)
    peer = identifier(); invitation = first.invite("127.0.0.1")
    try:
        with connect(invitation, peer) as channel:
            read_frame(channel); first.queue_send()
            transfer = request(channel, dict(command="poll"))["manifest"]["transferId"]
        first.close()
        second = SyncHost(profile, store); second.start("127.0.0.1", 0)
        try:
            with connect(dict(invitation, port=second.port), peer) as channel:
                read_frame(channel)
                assert request(channel, dict(command="poll"))["manifest"]["transferId"] == transfer
                second.cancel_send()
                assert request(channel, dict(command="poll"))["status"] == "idle"
            assert not second.pending_path.exists()
        finally:
            second.close()
    finally:
        first.close(); store.close(); profile.close()
