# Change Log

All notable changes to this project will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org/) and [Keep a CHANGELOG](http://keepachangelog.com/).

## [unreleased] - unreleased

### Fixed


### Added

- Add cookie parsing and serialization ([PR #80](https://github.com/ponylang/stallion/pull/80))

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

