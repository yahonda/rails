#!/usr/bin/env bash
# 各 PR target テストファイル群を base (no fix) でランダム seed × N runs。
set -u
cd /tmp/pg-leak-probe
BASE_SHA=8dedc689b593
N=${N:-15}

unset TESTOPTS
git reset --hard $BASE_SHA >/dev/null 2>&1

run_one() {
  local label=$1; shift
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
    bundle exec ruby -Itest $test_args > "$tlog" 2>&1 )

  kill -TERM $wpid 2>/dev/null
  for _ in 1 2 3 4; do sleep 0.5; kill -0 $wpid 2>/dev/null || break; done
  kill -KILL $wpid 2>/dev/null
  wait $wpid 2>/dev/null

  local peak seed
  peak=$(awk -F'total=' 'NR>1{n=split($2,a," ");p=a[1]+0;if(p>m)m=p}END{print m+0}' "$wlog")
  seed=$(grep -oE "seed [0-9]+" "$tlog" | head -1 | awk '{print $2}')
  echo "$label peak=$peak seed=$seed"
}

FILES_57409="test/cases/adapters/postgresql/range_test.rb test/cases/adapters/postgresql/enum_test.rb test/cases/adapters/postgresql/composite_test.rb test/cases/adapters/postgresql/domain_test.rb"
FILES_57410="test/cases/adapters/postgresql/postgresql_adapter_test.rb"
FILES_57412="test/cases/relation/load_async_test.rb -n /LoadAsync(Multi|Mixed)ThreadPoolExecutorTest/"

echo "=== seed search at base (no fix), N=$N per PR target ==="

echo "=== PR #57409 target ==="
for i in $(seq 1 $N); do run_one search-57409-r${i} $FILES_57409; done

echo "=== PR #57410 target ==="
for i in $(seq 1 $N); do run_one search-57410-r${i} $FILES_57410; done

echo "=== PR #57412 target ==="
for i in $(seq 1 $N); do run_one search-57412-r${i} $FILES_57412; done

echo "=== DONE ==="
