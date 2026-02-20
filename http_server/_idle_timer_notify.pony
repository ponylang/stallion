use "time"

class _IdleTimerNotify is TimerNotify
  """Timer notify that sends an idle timeout message to the server actor."""
  let _server_actor: HTTPServerActor

  new iso create(server_actor: HTTPServerActor) =>
    _server_actor = server_actor

  fun ref apply(timer: Timer, count: U64): Bool =>
    _server_actor._idle_timeout()
    false // One-shot: don't reschedule

  fun ref cancel(timer: Timer) =>
    None
