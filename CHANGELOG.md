# Change Log

All notable changes to this project will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org/) and [Keep a CHANGELOG](http://keepachangelog.com/).

## [unreleased] - unreleased

### Fixed

- Fix potential connection hang when timer event subscription fails ([PR #97](https://github.com/ponylang/stallion/pull/97))

### Added


### Changed

- Require ponyc 0.63.1 or later ([PR #97](https://github.com/ponylang/stallion/pull/97))

## [0.5.5] - 2026-04-07

### Fixed

- Fix connection stall after large response with backpressure ([PR #96](https://github.com/ponylang/stallion/pull/96))

## [0.5.4] - 2026-04-02

### Added

- Add on_start_failure callback to HTTPServerLifecycleEventReceiver ([PR #93](https://github.com/ponylang/stallion/pull/93))

## [0.5.3] - 2026-03-28

### Fixed

- Fix crash when dispose() arrives before connection initialization ([PR #91](https://github.com/ponylang/stallion/pull/91))

### Added

- Add one-shot timer API ([PR #89](https://github.com/ponylang/stallion/pull/89))

## [0.5.2] - 2026-03-22

### Fixed

- Fix premature idle timeouts on SSL connections ([PR #87](https://github.com/ponylang/stallion/pull/87))

### Changed

- Update ponylang/ssl to 2.0.1 ([PR #86](https://github.com/ponylang/stallion/pull/86))

## [0.5.1] - 2026-03-15

### Fixed

- Fix dispose() hanging when peer FIN is missed ([PR #85](https://github.com/ponylang/stallion/pull/85))

## [0.5.0] - 2026-03-15

### Added

- Add cookie parsing and serialization ([PR #80](https://github.com/ponylang/stallion/pull/80))
- Add content negotiation ([PR #82](https://github.com/ponylang/stallion/pull/82))

### Changed

- Change Headers.values() to yield Header val instead of tuples ([PR #80](https://github.com/ponylang/stallion/pull/80))

## [0.4.0] - 2026-03-03

### Changed

- Upgrade lori dependency to 0.10.0 ([PR #64](https://github.com/ponylang/stallion/pull/64))

## [0.3.2] - 2026-03-02

### Added

- Add cooperative scheduler yielding for HTTP connections ([PR #63](https://github.com/ponylang/stallion/pull/63))

## [0.3.1] - 2026-02-26

### Added

- Add configurable max requests per keep-alive connection ([PR #57](https://github.com/ponylang/stallion/pull/57))

## [0.3.0] - 2026-02-23

### Changed

- Remove max_concurrent_connections from ServerConfig ([PR #54](https://github.com/ponylang/stallion/pull/54))

## [0.2.0] - 2026-02-23

### Changed

- Change start_chunked_response() to return StartChunkedResponseResult ([PR #53](https://github.com/ponylang/stallion/pull/53))

## [0.1.0] - 2026-02-22

### Added

- Initial version

