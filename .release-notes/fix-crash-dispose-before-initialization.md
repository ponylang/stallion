## Fix crash when dispose() arrives before connection initialization

Fixed a crash that could occur when `dispose()` was called on a connection actor before its internal initialization completed. The race between initialization and disposal is unlikely but was observed on macOS arm64 CI.
