# frozen_string_literal: true

require "config"

require "stringio"

require "active_record"
require "cases/test_case"
require "active_support/dependencies"
require "active_support/logger"
require "active_support/core_ext/kernel/reporting"
require "active_support/core_ext/kernel/singleton_class"

require "support/global_config"
require "support/adapter_config"
require "support/encryption_config"

ARTest::GlobalConfig.apply

class ActiveRecord::TestCase
  class SQLSubscriber
    attr_reader :logged
    attr_reader :payloads

    def initialize
      @logged = []
      @payloads = []
    end

    def start(name, id, payload)
      @payloads << payload
      @logged << [payload[:sql].squish, payload[:name], payload[:binds]]
    end

    def finish(name, id, payload); end
  end

  module InTimeZone
    private
      def in_time_zone(zone)
        old_zone  = Time.zone
        old_tz    = ActiveRecord::Base.time_zone_aware_attributes

        Time.zone = zone ? ActiveSupport::TimeZone[zone] : nil
        ActiveRecord::Base.time_zone_aware_attributes = !zone.nil?
        yield
      ensure
        Time.zone = old_zone
        ActiveRecord::Base.time_zone_aware_attributes = old_tz
      end
  end

  module WaitForTestHelper
    private
      def wait_for(message: "condition not met", timeout: 5, interval: 0.01)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          return if yield
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            raise Timeout::Error, "#{message} after #{timeout} seconds"
          end
          sleep interval
        end
      end

      def wait_for_async_query(connection = ActiveRecord::Base.lease_connection, timeout: 5)
        return unless connection.async_enabled?

        executor = connection.pool.async_executor
        wait_for(message: "The async executor wasn't drained", timeout: timeout) do
          executor.scheduled_task_count <= executor.completed_task_count
        end
      end
  end
end

# helper.rb の末尾。PG コネクションリーク調査用プローブ（診断のみ、PR 前に revert する）

require "pg" if defined?(PG)

if defined?(PG::Connection)
  module PgConnectionAllocTrace
    ALLOCATIONS = {}
    MUTEX = Mutex.new
    BASELINE = ["<pre-probe baseline — connection existed before probe installed>"].freeze

    class << self
      def record(conn, stack)
        addr = safe_peer(conn)
        MUTEX.synchronize { ALLOCATIONS[conn.object_id] = [stack, addr] }
        # NOTE: finalizer は object_id をクロージャに掴むため conn 自体は保持しない
        oid = conn.object_id
        ObjectSpace.define_finalizer(conn, ->(_id) {
          MUTEX.synchronize { ALLOCATIONS.delete(oid) }
        })
      end

      def snapshot_baseline
        ObjectSpace.each_object(PG::Connection) do |c|
          next if c.finished?
          next if MUTEX.synchronize { ALLOCATIONS.key?(c.object_id) }
          record(c, BASELINE)
        end
      end

      def safe_peer(conn)
        return "<finished>" if conn.finished?
        host = conn.host rescue "?"
        port = conn.port rescue "?"
        db   = conn.db   rescue "?"
        "#{host}:#{port}/#{db}"
      rescue
        "<unknown>"
      end
    end

    # PG::Connection.new / PG.connect が呼ぶ initialize を捕捉
    def initialize(*args, **kwargs, &block)
      super
      PgConnectionAllocTrace.record(self, caller(1, 30))
    end
  end
  PG::Connection.prepend(PgConnectionAllocTrace)

  # initialize を経由しない C 経路（connect_start 等）も singleton レベルで包む
  module PgConnectionSingletonTrace
    %i[connect_start async_connect ping open].each do |m|
      next unless PG::Connection.respond_to?(m)
      define_method(m) do |*args, **kwargs, &block|
        conn = super(*args, **kwargs, &block)
        if conn.is_a?(PG::Connection)
          PgConnectionAllocTrace.record(conn, caller(1, 30))
        end
        conn
      end
    end
  end
  PG::Connection.singleton_class.prepend(PgConnectionSingletonTrace)

  # プローブ登録時点で既に存在しているコネクションをベースラインとして記録
  PgConnectionAllocTrace.snapshot_baseline

  module PgConnectionLeakProbe
    @max_seen = 0
    @max_pg_seen = 0
    # 専用 admin connection を 1 本確保して pg_stat_activity を問い合わせる。
    # この connection 自身が 1 セッション消費するので、count から自分の pid を除外する。
    @admin_conn = nil

    class << self
      attr_accessor :max_seen, :max_pg_seen

      def admin_conn
        @admin_conn ||= begin
          host = ENV["PGHOST"] || "localhost"
          port = (ENV["PGPORT"] || 5432).to_i
          user = ENV["PGUSER"] || "rails"
          PG.connect(host: host, port: port, user: user, dbname: "postgres")
        rescue
          nil
        end
      end

      def live_count
        GC.start
        ObjectSpace.each_object(PG::Connection).count { |c| !c.finished? }
      end

      def live_object_ids
        GC.start
        ObjectSpace.each_object(PG::Connection).reject(&:finished?).map(&:object_id)
      end

      # PG サーバー側で実際に保持されている client backend session 数
      # （admin_conn 自身を除く）
      def pg_session_count
        c = admin_conn
        return -1 unless c
        res = c.exec("SELECT count(*) FROM pg_stat_activity WHERE backend_type='client backend' AND pid <> pg_backend_pid()")
        res[0]["count"].to_i
      rescue
        -1
      end
    end

    def before_setup
      super
      @_pg_leak_before = PgConnectionLeakProbe.live_count
      @_pg_leak_before_ids = PgConnectionLeakProbe.live_object_ids
      @_pg_server_before = PgConnectionLeakProbe.pg_session_count
    end

    def after_teardown
      super
      return unless @_pg_leak_before # before_setup might not have run on early-abort tests
      after_ids = PgConnectionLeakProbe.live_object_ids
      after_count = after_ids.size
      delta = after_count - @_pg_leak_before
      pg_after = PgConnectionLeakProbe.pg_session_count
      pg_delta = pg_after - @_pg_server_before
      PgConnectionLeakProbe.max_seen = after_count if after_count > PgConnectionLeakProbe.max_seen
      PgConnectionLeakProbe.max_pg_seen = pg_after if pg_after > PgConnectionLeakProbe.max_pg_seen

      # PG サーバー側 delta が +1 以上、または Ruby delta が +1 以上、または高水準なら出力
      should_log = delta != 0 || pg_delta != 0 || after_count >= 10 || pg_after >= 50
      if should_log
        marker = pg_after >= 80 ? "!!" : "  "
        $stderr.puts "[pg-leak]#{marker} #{self.class}##{name} " \
                     "ruby=#{@_pg_leak_before}→#{after_count}(#{format('%+d', delta)}) " \
                     "pg=#{@_pg_server_before}→#{pg_after}(#{format('%+d', pg_delta)})"

        # PG サーバー側 delta が +1 以上、または Ruby delta が +1 以上のとき alloc stack を吐く
        if delta > 0 || pg_delta > 0
          new_ids = after_ids - @_pg_leak_before_ids
          PgConnectionAllocTrace::MUTEX.synchronize do
            new_ids.each do |id|
              stack, addr = PgConnectionAllocTrace::ALLOCATIONS[id]
              $stderr.puts "  [pg-alloc] NEW conn object_id=#{id} peer=#{addr || '<unknown>'}"
              if stack
                stack.first(25).each { |frame| $stderr.puts "    #{frame}" }
              else
                $stderr.puts "    <no alloc stack — constructor not hooked?>"
              end
            end
          end
        end
      end
    end
  end

  # admin connection を遅延ではなく即時 init して、最初のテストの delta に紛れないようにする
  PgConnectionLeakProbe.admin_conn

  ActiveSupport::TestCase.prepend(PgConnectionLeakProbe)

  Minitest.after_run do
    GC.start
    final_ids = PgConnectionLeakProbe.live_object_ids
    final_pg = PgConnectionLeakProbe.pg_session_count
    $stderr.puts "[pg-leak] final ruby=#{final_ids.size} (peak=#{PgConnectionLeakProbe.max_seen}), " \
                 "final pg_server=#{final_pg} (peak=#{PgConnectionLeakProbe.max_pg_seen})"
    PgConnectionAllocTrace::MUTEX.synchronize do
      final_ids.each do |id|
        stack, addr = PgConnectionAllocTrace::ALLOCATIONS[id]
        $stderr.puts "[pg-alloc] FINAL live conn object_id=#{id} peer=#{addr || '<unknown>'}"
        if stack
          stack.first(15).each { |frame| $stderr.puts "    #{frame}" }
        else
          $stderr.puts "    <no alloc stack — constructor not hooked?>"
        end
      end
    end
  end
end
