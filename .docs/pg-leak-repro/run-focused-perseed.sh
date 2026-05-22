#!/usr/bin/env bash
# Each PR's target tests with its own leakiest seed, before/after × N runs each.
set -u
cd /tmp/pg-leak-probe
BASE_SHA=8dedc689b593
PR_57409=yahonda/yahonda/reduce-pg-test-connection-leak
PR_57410=yahonda/yahonda/disconnect-test-local-pg-adapters
PR_57412=yahonda/yahonda/run-load-async-multi-pool-test-on-replaced-pool

N=${N:-5}

run_one() {
  local label=$1 seed=$2; shift 2
  local test_args="$@"
  local wlog=/tmp/watcher-${label}.log
  local tlog=/tmp/test-${label}.log
  rm -f "$wlog" "$tlog"

  docker restart pg-leak >/dev/null 2>&1
  deadline=$((SECONDS + 30))
  until psql -h 127.0.0.1 -p 5432 -U yahonda -d postgres -c 'SELECT 1' >/dev/null 2>&1; do
    [ $SECONDS -ge $deadline ] && { echo "$label PG_TIMEOUT"; return 1; }
    sleep 0.3
  done

  PGHOST=127.0.0.1 PGPORT=5432 PGUSER=yahonda WATCHER_LOG=$wlog ruby /tmp/pg-watcher.rb &
  local wpid=$!
  sleep 0.5

  ( cd /tmp/pg-leak-probe/activerecord && \
    PGHOST=127.0.0.1 PGPORT=5432 PGUSER=yahonda ARCONN=postgresql \
    bundle exec ruby -Itest $test_args --seed=$seed > "$tlog" 2>&1 )

  kill -TERM $wpid 2>/dev/null
  for _ in 1 2 3 4; do sleep 0.5; kill -0 $wpid 2>/dev/null || break; done
  kill -KILL $wpid 2>/dev/null
  wait $wpid 2>/dev/null

  local peak
  peak=$(awk -F'total=' 'NR>1{n=split($2,a," ");p=a[1]+0;if(p>m)m=p}END{print m+0}' "$wlog")
  echo "$label peak=$peak seed=$seed"
}

reset_and_apply() {
  git reset --hard $BASE_SHA >/dev/null 2>&1
  for ref in "$@"; do git cherry-pick "$ref" >/dev/null 2>&1; done
}

FILES_57409="test/cases/adapters/postgresql/range_test.rb test/cases/adapters/postgresql/enum_test.rb test/cases/adapters/postgresql/composite_test.rb test/cases/adapters/postgresql/domain_test.rb"
FILES_57410="test/cases/adapters/postgresql/postgresql_adapter_test.rb"
FILES_57412="test/cases/relation/load_async_test.rb -n /LoadAsync(Multi|Mixed)ThreadPoolExecutorTest/"

# (pr, ref, leaky_seed, files)
for spec in \
  "57409:$PR_57409:22021:$FILES_57409" \
  "57410:$PR_57410:37604:$FILES_57410" \
  "57412:$PR_57412:15223:$FILES_57412"; do
  IFS=":" read -r pr ref seed files <<< "$spec"
  echo "=== PR #$pr (seed=$seed) ==="

  echo "--- BEFORE (base) ---"
  reset_and_apply
  for i in $(seq 1 $N); do run_one pr${pr}-before-r${i} $seed $files; done

  echo "--- AFTER (PR applied) ---"
  reset_and_apply $ref
  for i in $(seq 1 $N); do run_one pr${pr}-after-r${i} $seed $files; done
done

echo "=== DONE ==="
