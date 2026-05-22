# PostgreSQL "too many clients already" reproduction scripts

These scripts reproduce and measure the `FATAL: sorry, too many clients already`
failure observed in the Rails nightly suite (e.g. Buildkite build #128640) and
quantify the effect of candidate fixes against `max_connections=100`.

Branch is intentionally separate from any fix PR; it is reference material for
the investigation and is not meant to be merged into `main`.

## Methodology overview

Earlier investigations used an in-process probe that hooked
`PG::Connection#initialize` and registered finalizers. That probe had a
binding-leak bug: the finalizer lambda captured the enclosing method's local
binding (including `conn`), which pinned each `PG::Connection` via the
finalizer table. The pinned connections kept their PG sockets open and inflated
the `pg_stat_activity` counts the probe was trying to measure. Every
`BEFORE/AFTER` number captured by that probe should be considered overstated.

These scripts avoid that pitfall completely:

- **No in-process instrumentation.** Tests are run unmodified. The PG-side
  session count is observed from a separate Ruby process that polls
  `pg_stat_activity` at ~100ms intervals over a dedicated admin connection.
- **`docker restart` per run.** Each test invocation starts against a freshly
  restarted PostgreSQL postmaster, so transient state (cached plans, idle
  reaper timing, prior-run sockets) does not leak between samples. The test
  databases persist in the container's data directory.
- **Random seed for variance, fixed seed for attribution.** Random Minitest
  seeds (left at default) are used to estimate run-to-run variance. A specific
  seed (the one producing the largest BEFORE leak for a target test set) is
  fixed for a clean `BEFORE` vs `AFTER` comparison.

## Environment used for the captured numbers

- macOS host, `postgres:alpine` (PostgreSQL 18.4) in Docker, exposed on
  `127.0.0.1:5432`, started with `-c max_connections=100`, `TRUST` auth.
- Container named `pg-leak`. Databases `activerecord_unittest` and
  `activerecord_unittest2` (created once via
  `bundle exec rake db:postgresql:build`; they survive `docker restart`).
- Ruby installed via mise. `bundle install` was run once against the base SHA
  to populate the gem cache before measurement.
- `PGHOST=127.0.0.1 PGPORT=5432 PGUSER=yahonda ARCONN=postgresql`.

## Files

| File | Purpose |
| --- | --- |
| `pg-watcher.rb` | External `pg_stat_activity` poller. Writes `timestamp total=N datname/state=…` lines at ~100ms cadence. Exits cleanly on `SIGTERM`. |
| `run-suite.sh <label>` | Single end-to-end run: `docker restart pg-leak`, start watcher, `rake test:postgresql`, stop watcher, extract peak. Honours `$TESTOPTS`. |
| `run-seed-search.sh` | For each PR's modified test files, runs the base SHA without the fix N times with random seeds. The `peak` / `seed` pairs identify the seed that maximises that PR's target-file leak. |
| `run-focused-perseed.sh` | For each PR, resets to base, runs `BEFORE` N times at the per-PR leakiest seed, applies the PR via cherry-pick, then runs `AFTER` N times at the same seed. |

## Captured per-PR numbers (`max_connections=100`, base SHA `8dedc689b5`)

After running `run-seed-search.sh` to find each PR's worst seed, then
`run-focused-perseed.sh` with N=5:

| PR | Target test files | Seed | BEFORE peak (5 runs) | AFTER peak (5 runs) |
| --- | --- | ---: | :---: | :---: |
| [#57409](https://github.com/rails/rails/pull/57409) | `range_test.rb`, `enum_test.rb`, `composite_test.rb`, `domain_test.rb` | 22021 | 9, 12, 7, 7, 8 | 2, 2, 2, 2, 2 |
| [#57410](https://github.com/rails/rails/pull/57410) | `postgresql_adapter_test.rb` | 37604 | 13, 15, 17, 16, 13 | 4, 5, 5, 5, 5 |
| [#57412](https://github.com/rails/rails/pull/57412) | `load_async_test.rb` (`LoadAsyncMulti…` + `LoadAsyncMixed…ThreadPoolExecutorTest`) | 15223 | 25, 23, 23, 26, 28 | 2, 2, 2, 2, 2 |

`baseline ≈ 2` is the two fixture-loaded sessions on `activerecord_unittest` /
`activerecord_unittest2`. Each PR reduces its target peak to baseline (or
near-baseline for #57410, whose remaining 2–3 events come from
`verify!` / `reconnect!` paths that the PR explicitly leaves out of scope).

The full PG suite reproduces the `FATAL: sorry, too many clients already`
behaviour locally with the same `max_connections=100`: across 25 unfixed
runs at random seed, 3 (12%) hit `peak=99` and reported 13–18 errors driven
by the saturated pool, mirroring the build #128640 failure mode.

## Running the scripts

```sh
# one-off: build the test databases (after docker run … -c max_connections=100)
cd /path/to/rails/activerecord
PGHOST=127.0.0.1 PGPORT=5432 PGUSER=yahonda \
  bundle exec rake db:postgresql:build

# find the leakiest seed per PR target (N runs each, random seed)
N=15 .docs/pg-leak-repro/run-seed-search.sh

# before/after with each PR's leakiest seed
N=5 .docs/pg-leak-repro/run-focused-perseed.sh
```

The scripts assume the worktree is at `/tmp/pg-leak-probe` and the container
is named `pg-leak`; adjust `BASE_SHA`, paths, and `PGUSER` to your setup.

## Caveats

- These numbers reflect a single host's I/O profile. The absolute peak on
  Buildkite agents may differ; the `BEFORE` vs `AFTER` delta per PR target,
  however, is intrinsic to the leak the PR removes and should be reproducible.
- `run-seed-search.sh` at N=15 is intentionally small. Running larger N (and
  retaining the leakiest seed) gives a more pessimistic `BEFORE` for the
  `BEFORE`/`AFTER` comparison.
- The PR cherry-picks must apply cleanly on the chosen base SHA; if `main`
  has moved past, rebase the topic PR branches first.
