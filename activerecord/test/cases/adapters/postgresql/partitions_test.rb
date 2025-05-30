# frozen_string_literal: true

require "cases/helper"

class PostgreSQLPartitionsTest < ActiveRecord::PostgreSQLTestCase
  def setup
    @connection = ActiveRecord::Base.lease_connection
  end

  def teardown
    @connection.drop_table "partitioned_events", if_exists: true
  end

  def test_partitions_table_exists
    skip unless ActiveRecord::Base.lease_connection.database_version >= 100000
    silence_warnings do
      @connection.create_table :partitioned_events, force: true, id: false,
        options: "partition by range (issued_at)" do |t|
        t.timestamp :issued_at
      end
    end
    assert @connection.table_exists?("partitioned_events")
  end
  def test_unlogged_option_ignored_for_partitioned_table_in_postgresql_18
    skip unless @connection.database_version >= 180000
    begin
      previous_unlogged_tables = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.create_unlogged_tables
      ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.create_unlogged_tables = true

      warning = capture(:stderr) do
        @connection.create_table :partitioned_events, force: true, id: false,
          options: "partition by range (issued_at)" do |t|
          t.timestamp :issued_at
        end
      end

      assert_match(/UNLOGGED tables cannot be partitioned in PostgreSQL 18 and later/, warning)
      assert @connection.table_exists?("partitioned_events")
    ensure
      ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.create_unlogged_tables = previous_unlogged_tables
    end
  end
end
