# frozen_string_literal: true

require "cases/helper"
require "models/author"

class PostgresqlDeferredConstraintsTest < ActiveRecord::PostgreSQLTestCase
  def setup
    @connection = ActiveRecord::Base.lease_connection
    @fk = @connection.foreign_keys("authors").first.name
    @other_fk = @connection.foreign_keys("lessons_students").first.name
  end

  # These three tests fail on PostgreSQL 18 because ALTER CONSTRAINT NOT ENFORCED -> ENFORCED
  # resets the pg_trigger deferability flags (tgdeferrable / tginitdeferred) even when
  # DEFERRABLE INITIALLY DEFERRED is explicitly specified. This is a PostgreSQL bug reported at:
  # https://www.mail-archive.com/pgsql-hackers@lists.postgresql.org/msg221360.html
  # Once PostgreSQL ships a fix, remove the skip and these tests should pass without modification.

  def test_defer_constraints
    skip "Requires a PostgreSQL fix for deferability flag corruption after NOT ENFORCED -> ENFORCED cycle" if @connection.supports_not_enforced_constraints?
    assert_raises ActiveRecord::InvalidForeignKey do
      @connection.set_constraints(:deferred)
      assert_nothing_raised do
        Author.create!(author_address_id: -1, name: "John Doe")
      end
      @connection.set_constraints(:immediate)
    end
  end

  def test_defer_constraints_with_specific_fk
    skip "Requires a PostgreSQL fix for deferability flag corruption after NOT ENFORCED -> ENFORCED cycle" if @connection.supports_not_enforced_constraints?
    assert_raises ActiveRecord::InvalidForeignKey do
      @connection.set_constraints(:deferred, @fk)
      assert_nothing_raised do
        Author.create!(author_address_id: -1, name: "John Doe")
      end
      @connection.set_constraints(:immediate, @fk)
    end
  end

  def test_defer_constraints_with_multiple_fks
    skip "Requires a PostgreSQL fix for deferability flag corruption after NOT ENFORCED -> ENFORCED cycle" if @connection.supports_not_enforced_constraints?
    assert_raises ActiveRecord::InvalidForeignKey do
      @connection.set_constraints(:deferred, @other_fk, @fk)
      assert_nothing_raised do
        Author.create!(author_address_id: -1, name: "John Doe")
      end
      @connection.set_constraints(:immediate, @other_fk, @fk)
    end
  end

  def test_defer_constraints_only_defers_single_fk
    @connection.set_constraints(:deferred, @other_fk)
    assert_raises ActiveRecord::InvalidForeignKey do
      Author.create!(author_address_id: -1, name: "John Doe")
    end
  end

  def test_set_constraints_requires_valid_value
    assert_raises ArgumentError do
      @connection.set_constraints(:invalid)
    end
  end
end
