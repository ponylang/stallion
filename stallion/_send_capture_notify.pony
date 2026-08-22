trait ref _SendCaptureNotify
  """
  Test hook installed via `HTTPServer._install_send_capture` to observe
  every ByteSeq or ByteSeqIter handed to lori's `send()` on the
  connection, in send order. Production code neither implements nor
  installs this trait.
  """

  fun ref _record(data: (ByteSeq | ByteSeqIter))
    """
    Called synchronously from `HTTPServer._on_send_accepted` for every
    accepted send.
    """
