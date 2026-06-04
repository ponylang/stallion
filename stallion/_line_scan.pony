class val _Line
  """
  A complete CRLF-terminated protocol line, with content guaranteed free of
  any bare CR or bare LF.

  Content is `buf[content_start, content_end)`; the terminating CR sits at
  `content_end` and the LF at `content_end + 1`, so the next line begins at
  `next_pos()`.
  """
  let content_start: USize
  let content_end: USize

  new val create(content_start': USize, content_end': USize) =>
    content_start = content_start'
    content_end = content_end'

  fun is_blank(): Bool =>
    """Whether this is the empty line (a bare CRLF with no content)."""
    content_start == content_end

  fun next_pos(): USize =>
    """Buffer position immediately after this line's CRLF terminator."""
    content_end + 2

class val _ScannedLine
  """
  The content of one protocol line, already proven free of bare CR and LF by
  `_LineScan`.

  The parser gates (`_FieldLine`, `_RequestLine`, `_ChunkHeader`) take this
  rather than a raw `String` so a caller cannot hand them bytes that skipped the
  line policy — the line invariant the rewrite rests on. The only intended
  construction is `_RequestParser.scanned_line` from a `_LineScan` `_Line`;
  wrapping an arbitrary string here is a deliberate, greppable assertion that the
  bytes are CR/LF-clean.
  """
  let content: String val

  new val create(content': String val) =>
    content = content'

primitive _LineTooLong
  """A line's content reached the size limit before any CRLF terminator."""

primitive _LineNeedMore
  """
  No complete CRLF-terminated line is available yet.

  A CR at the very end of the buffer is reported as need-more (not a bare CR):
  the next read may supply the LF that completes the CRLF. This is what keeps
  line parsing resumable at every byte boundary.
  """

type _LineResult is (_Line | BareCRLF | _LineTooLong | _LineNeedMore)

primitive _LineScan
  """
  RFC 9112 §2.2 line policy — the single place CR/LF is interpreted, for every
  line type (request line, header/trailer field-line, chunk-size line).

  Only CRLF terminates a line. A bare LF, or a bare CR not immediately followed
  by LF, is rejected (`BareCRLF`): folding either into a line boundary is the
  request-smuggling vector this parser exists to close — an intermediary that
  splits on a bare CR/LF would see a message boundary where Stallion does not.
  A CR at the end of the buffer is need-more (it may become CRLF next read).

  This is the only producer of a `_Line`, so no other code can obtain a line
  that skipped the CR/LF check. It replaces the old `find_crlf`, which returned
  the first CRLF and was blind to any interior bare CR/LF before it — the root
  cause of the recurring smuggling bugs.
  """
  fun next(buf: Array[U8] box, from: USize, max: USize): _LineResult =>
    """
    Scan `buf[from..]` for one complete line. `max` bounds the content length
    (excluding the CRLF); content reaching `max` bytes without a terminator is
    `_LineTooLong`. A returned `_Line`'s content is free of bare CR and LF.
    """
    var i = from
    let size = buf.size()
    try
      while i < size do
        let b = buf(i)?
        if b == '\n' then
          return BareCRLF
        elseif b == '\r' then
          if (i + 1) == size then
            return _LineNeedMore
          elseif buf(i + 1)? != '\n' then
            return BareCRLF
          else
            return _Line(from, i)
          end
        end
        if (i - from) >= max then return _LineTooLong end
        i = i + 1
      end
    else
      _Unreachable()
    end
    _LineNeedMore
