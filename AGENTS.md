# Stallion

An HTTP/1.x server library for Pony, built on lori. The user's actor is the connection — there is no separate internal actor.

<!-- contributor-only -->
## Contributing with an AI assistant

This is a Pony project. The ponylang org maintains a set of LLM coding skills. Get set up with them before contributing:

- **Not set up yet?** Install them once:

  ```bash
  git clone https://github.com/ponylang/llm-skills.git
  cd llm-skills
  python install.py
  ```

- **Already set up?** Make sure you're on the latest. If you installed with the script above, `git pull` in the directory where you cloned `llm-skills` and the symlinked skills update automatically — if you set them up another way, refresh them however that setup expects.

See the [llm-skills README](https://github.com/ponylang/llm-skills) for details and other harnesses.

When you start working on this project, load the `pony-skills` skill — it tells your assistant which Pony skill to use for each task.

Read [CONTRIBUTING.md](CONTRIBUTING.md).
<!-- /contributor-only -->

## Building and testing

```
make ssl=3.0.x                       # build + run tests (OpenSSL 3.x)
make ssl=1.1.x                       # OpenSSL 1.1.x
make ssl=libressl                    # LibreSSL
make test-one t=TestName ssl=3.0.x   # run a single test by name
make clean
```

`ssl=` is required because stallion and lori depend on the `ssl` package.

## RFC conformance

Stallion conforms to the HTTP RFCs: we reject what they say to reject and accept what they say to accept. We will also reject more than the RFCs strictly require when doing so closes a security hole and the message is one no conformant client would send — that hardening costs conformant traffic nothing. What we will not do is the reverse: refuse a conformant message, or add non-conformant behavior, to compensate for some other party we cannot fix.

The line is who would be harmed. We reject a message the RFCs themselves say to reject, and a message only a broken or hostile client would send, even where the RFCs would tolerate it. But a conformant message that some intermediary might still mishandle is not ours to pre-empt: refusing it would break conformant clients to chase a misbehaving party we cannot fix.

Concretely: a field name containing `_` is a valid RFC 9110 §5.6.2 token, so we accept it — even though an upstream that rewrites `_` to `-` could confuse `X_Forwarded_For` with `X-Forwarded-For`. That rewrite is the upstream's bug, not ours, and refusing a valid token to defend against it would be the wrong trade.

## Architecture

The design mirrors lori's own layering — a protocol class, an actor trait, and a lifecycle-event-receiver trait:

```
lori:  TCPConnection (class) + TCPConnectionActor (trait) + ServerLifecycleEventReceiver (trait)
http:  HTTPServer    (class) + HTTPServerActor    (trait) + HTTPServerLifecycleEventReceiver (trait)
```

The user's actor holds an `HTTPServer` and implements `HTTPServerActor`; because the actor is the connection, other actors can message it directly. A separate listener actor implements `lori.TCPListenerActor` and creates the server actors in `_on_accept` — no factory, no notify, no hidden actor.

The parser and the connection lifecycle are each a small state machine, with states as classes and every state implementing every operation.

**Each security-critical grammar rule lives in one primitive**, so a fix reaches every caller by construction — CR/LF, for instance, is interpreted only in `_LineScan`, which replaced a scattered `find_crlf` that was the root cause of a class of request-smuggling bugs. Keep a new grammar rule in its own primitive; do not re-interpret bytes in a state class.

## Conventions

- `_Unreachable()` (`_mort.pony`) for impossible code paths.
- `\nodoc\` on test classes.
