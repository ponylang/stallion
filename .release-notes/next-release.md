## Remove max_concurrent_connections from ServerConfig

`max_concurrent_connections` has been removed from `ServerConfig`. Connection limiting is the listener's responsibility, not the HTTP protocol layer's. The field was never used by stallion — it was only stored in the config.

If you were passing `max_concurrent_connections'` to `ServerConfig`, remove the argument:

Before:

```pony
ServerConfig("localhost", "8080" where
  max_concurrent_connections' = 100,
  max_body_size' = 10_485_760)
```

After:

```pony
ServerConfig("localhost", "8080" where
  max_body_size' = 10_485_760)
```

