use lori = "lori"
use net = "net"

use @socket[I32](domain: I32, type': I32, protocol: I32)
use @pony_os_socket_close[None](fd: U32)

class \nodoc\ ref _TestFakeBackend is lori.TCPBackend
  """
  Fake `TCPBackend` for pure tests.

  `create()` MUST be a no-op — `TCPConnection[TCP].none()` field-initializes
  `_tcp: TCP = TCP`, so `create()` runs even for the placeholder connection
  that never sees a real fd.

  Assumes lori delivers `_on_sent(token)` synchronously from within
  `send()`. Pure tests that assert on chunk-delivery counters immediately
  after `_on_received` returns depend on this. A lori change that defers
  `_on_sent` breaks those tests.

  When lori adds a method to `TCPBackend`, this class must gain the same
  method or every pure test stops compiling.
  """
  new create() => None

  fun ref listen(the_actor: AsioEventNotify,
    host: String,
    port: String,
    ip_version: lori.IPVersion)
    : AsioEventID
  =>
    AsioEvent.none()

  fun ref accept(event: AsioEventID): I32 => 0

  fun ref close(fd: U32) => @pony_os_socket_close(fd)

  fun ref connect(the_actor: AsioEventNotify,
    host: String,
    port: String,
    from: String,
    asio_flags: U32,
    ip_version: lori.IPVersion)
    : U32
  =>
    0

  fun ref keepalive(fd: U32, secs: U32) => None

  fun ref peername(fd: U32, ip: net.NetAddress tag): Bool => false

  fun ref shutdown(fd: U32) => None

  fun ref sockname(fd: U32, ip: net.NetAddress tag): Bool => false

  fun ref writev_max(): I32 => 1024

  fun ref receive(event: AsioEventID,
    buffer: Pointer[U8] tag,
    size: USize)
    : (lori.SocketResult, USize)
  =>
    (lori.SocketResultRetry, 0)

  fun ref sendv(event: AsioEventID,
    data: Array[ByteSeq] box,
    from: USize,
    count: USize,
    first_buffer_byte_offset: USize)
    : (lori.SocketResult, USize) ?
  =>
    var total: USize = 0
    var i = from
    let stop = from + count
    while i < stop do
      let s = data(i)?.size()
      let take =
        if i == from then
          // Guards against a lori bug feeding an offset past the first
          // buffer size — surface it as an error, not a wrap-around count.
          if first_buffer_byte_offset > s then error end
          s - first_buffer_byte_offset
        else s
        end
      total = total + take
      i = i + 1
    end
    (lori.SocketResultOk, total)

primitive \nodoc\ _FakeServerFd
  """
  Allocate a raw TCP socket fd suitable for `PonyAsio.create_event`. The fd
  is never bound or connected — it exists only so ASIO has a valid file
  descriptor. The fake backend handles all I/O; the fd is closed on
  connection teardown via `_TestFakeBackend.close`.
  """
  fun apply(): U32 ? =>
    let fd = @socket(I32(2), I32(1), I32(0))
    if fd < 0 then error end
    fd.u32()

class \nodoc\ ref _TestSendCapture is _SendCaptureNotify
  """
  Accumulator for wire bytes. Tests install one via
  `HTTPServer._install_send_capture` and read `bytes()` to assert on it.
  """
  var _buf: String ref = String

  fun ref _record(data: (ByteSeq | ByteSeqIter)) =>
    match \exhaustive\ data
    | let d: ByteSeq =>
      _buf.append(d)
    | let d: ByteSeqIter =>
      for v in d.values() do _buf.append(v) end
    end

  fun ref bytes(): String box => _buf

  fun ref clear() => _buf = String
