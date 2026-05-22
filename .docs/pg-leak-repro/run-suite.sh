#!/usr/bin/env bash
set -u
label=$1
wlog=/tmp/watcher-${label}.log
tlog=/tmp/test-${label}.log
rm -f "$wlog" "$tlog"

# 1. PG container 再起動
docker restart pg-leak >/dev/null 2>&1
deadline=$((SECONDS + 30))
until psql -h 127.0.0.1 -p 5432 -U yahonda -d postgres -c 'SELECT 1' >/dev/null 2>&1; do
  [ $SECONDS -ge $deadline ] && { echo "$label PG_TIMEOUT"; exit 1; }
  sleep 0.3
done

# 2. watcher 起動
PGHOST=127.0.0.1 PGPORT=5432 PGUSER=yahonda WATCHER_LOG=$wlog ruby /tmp/pg-watcher.rb &
wpid=$!
sleep 0.5

# 3. test 実行
cd /tmp/pg-leak-probe/activerecord
PGHOST=127.0.0.1 PGPORT=5432 PGUSER=yahonda ARCONN=postgresql TESTOPTS="${TESTOPTS:-}" bundle exec rake test:postgresql > "$tlog" 2>&1
test_exit=$?

# 4. watcher 停止
kill -TERM $wpid 2>/dev/null
for _ in 1 2 3 4; do
  sleep 0.5
  kill -0 $wpid 2>/dev/null || break
done
kill -KILL $wpid 2>/dev/null
wait $wpid 2>/dev/null

# 5. peak 抽出
peak=$(awk -F'total=' 'NR>1{split($2,a," ");p=a[1]+0;if(p>m)m=p}END{print m+0}' "$wlog")
runs=$(awk '/^[0-9]+ runs, [0-9]+ assertions/{print; exit}' "$tlog")
echo "$label peak=$peak exit=$test_exit  $runs"
