#!/usr/bin/env ruby
# 外部 watcher: 100ms polling. INT/TERM で即終了。
require "pg"

# 即終了 — 後処理は呼び出し側がログから peak を抽出する
Signal.trap("INT") { exit 0 }
Signal.trap("TERM") { exit 0 }

conn = PG.connect(
  host: ENV["PGHOST"] || "127.0.0.1",
  port: (ENV["PGPORT"] || 5432).to_i,
  user: ENV["PGUSER"] || "yahonda",
  dbname: "postgres",
)
conn.exec("SET application_name = 'pg-leak-watcher'")
my_pid = conn.exec("SELECT pg_backend_pid()")[0]["pg_backend_pid"].to_i

log_path = ENV["WATCHER_LOG"] || "/tmp/pg-watcher.log"
File.open(log_path, "w") do |f|
  f.sync = true
  loop do
    res = conn.exec_params(
      "SELECT datname, state, count(*) AS c FROM pg_stat_activity " \
      "WHERE backend_type='client backend' AND pid <> $1 " \
      "GROUP BY datname, state ORDER BY datname, state",
      [my_pid]
    )
    rows = res.to_a
    total = rows.sum { |r| r["c"].to_i }
    ts = Time.now.strftime("%H:%M:%S.%3N")
    breakdown = rows.map { |r| "#{r['datname']}/#{r['state']}=#{r['c']}" }.join(",")
    f.puts "#{ts} total=#{total} #{breakdown}"
    sleep 0.1
  end
end
