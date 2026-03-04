# frozen_string_literal: true

require "cases/helper"
require "support/connection_helper"

class PostgreSQLReferentialIntegrityTest < ActiveRecord::PostgreSQLTestCase
  include ConnectionHelper

  IS_REFERENTIAL_INTEGRITY_SQL = lambda do |sql|
    sql.match(/DISABLE TRIGGER ALL/) || sql.match(/ENABLE TRIGGER ALL/)
  end

  module MissingSuperuserPrivileges
    def execute(sql, name = nil)
      if IS_REFERENTIAL_INTEGRITY_SQL.call(sql)
        super "BROKEN;" rescue nil # put transaction in broken state
        raise ActiveRecord::StatementInvalid, "PG::InsufficientPrivilege"
      else
        super
      end
    end
  end

  module ProgrammerMistake
    def execute(sql, name = nil)
      if IS_REFERENTIAL_INTEGRITY_SQL.call(sql)
        raise ArgumentError, "something is not right."
      else
        super
      end
    end
  end

  def setup
    @connection = ActiveRecord::Base.lease_connection
  end

  def teardown
    reset_connection
    if ActiveRecord::Base.lease_connection.is_a?(MissingSuperuserPrivileges)
      raise "MissingSuperuserPrivileges patch was not removed"
    end
  end

  def test_should_reraise_invalid_foreign_key_exception_and_show_warning
    skip if @connection.supports_not_enforced_constraints?
    @connection.extend MissingSuperuserPrivileges

    warning = capture(:stderr) do
      e = assert_raises(ActiveRecord::InvalidForeignKey) do
        @connection.disable_referential_integrity do
          raise ActiveRecord::InvalidForeignKey, "Should be re-raised"
        end
      end
      assert_equal "Should be re-raised", e.message
    end
    assert_match (/WARNING: Rails was not able to disable referential integrity/), warning
    assert_match (/cause: PG::InsufficientPrivilege/), warning
  end

  def test_does_not_print_warning_if_no_invalid_foreign_key_exception_was_raised
    @connection.extend MissingSuperuserPrivileges

    warning = capture(:stderr) do
      e = assert_raises(ActiveRecord::StatementInvalid) do
        @connection.disable_referential_integrity do
          raise ActiveRecord::StatementInvalid, "Should be re-raised"
        end
      end
      assert_equal "Should be re-raised", e.message
    end
    assert_predicate warning, :blank?, "expected no warnings but got:\n#{warning}"
  end

  def test_does_not_break_transactions
    @connection.extend MissingSuperuserPrivileges

    @connection.transaction do
      @connection.disable_referential_integrity do
        assert_transaction_is_not_broken
      end
      assert_transaction_is_not_broken
    end
  end

  def test_does_not_break_nested_transactions
    @connection.extend MissingSuperuserPrivileges

    @connection.transaction do
      @connection.transaction(requires_new: true) do
        @connection.disable_referential_integrity do
          assert_transaction_is_not_broken
        end
      end
      assert_transaction_is_not_broken
    end
  end

  def test_only_catch_active_record_errors_others_bubble_up
    skip if @connection.supports_not_enforced_constraints?
    @connection.extend ProgrammerMistake

    assert_raises ArgumentError do
      @connection.disable_referential_integrity { }
    end
  end

  def test_disable_referential_integrity_uses_not_enforced_on_pg18
    skip unless @connection.supports_not_enforced_constraints?

    @connection.create_table :ri_test_pg18_parents, force: true
    @connection.create_table :ri_test_pg18_children, force: true do |t|
      t.bigint :parent_id, null: false
    end
    @connection.add_foreign_key :ri_test_pg18_children, :ri_test_pg18_parents, column: :parent_id, name: :ri_test_pg18_fk

    fk_enforced_during_block = nil
    @connection.disable_referential_integrity do
      fk_enforced_during_block = @connection.select_value(<<~SQL)
        SELECT c.conenforced FROM pg_constraint c WHERE c.conname = 'ri_test_pg18_fk'
      SQL
    end

    assert_equal false, fk_enforced_during_block,
      "FK should be NOT ENFORCED inside the disable_referential_integrity block"

    fk_enforced_after = @connection.select_value(<<~SQL)
      SELECT c.conenforced FROM pg_constraint c WHERE c.conname = 'ri_test_pg18_fk'
    SQL

    assert_equal true, fk_enforced_after,
      "FK should be restored to ENFORCED after the disable_referential_integrity block"
  ensure
    @connection.drop_table :ri_test_pg18_children, if_exists: true
    @connection.drop_table :ri_test_pg18_parents, if_exists: true
  end

  def test_not_enforced_foreign_keys_remain_not_enforced_after_block
    skip unless @connection.supports_not_enforced_constraints?

    @connection.create_table :ri_test_parents, force: true
    @connection.create_table :ri_test_children, force: true do |t|
      t.bigint :parent_id, null: false
    end
    @connection.add_foreign_key :ri_test_children, :ri_test_parents, column: :parent_id, name: :ri_test_fk, enforced: false

    @connection.disable_referential_integrity { }

    result = @connection.select_value(<<~SQL)
      SELECT c.conenforced
      FROM pg_constraint c
      WHERE c.conname = 'ri_test_fk'
    SQL

    assert_equal false, result, "NOT ENFORCED FK should remain NOT ENFORCED after disable_referential_integrity block"
  ensure
    @connection.drop_table :ri_test_children, if_exists: true
    @connection.drop_table :ri_test_parents, if_exists: true
  end

  def test_enforced_foreign_keys_are_restored_to_enforced_after_block
    skip unless @connection.supports_not_enforced_constraints?

    @connection.create_table :ri_test_parents, force: true
    @connection.create_table :ri_test_children, force: true do |t|
      t.bigint :parent_id, null: false
    end
    @connection.add_foreign_key :ri_test_children, :ri_test_parents, column: :parent_id, name: :ri_test_fk

    fk_enforced_during_block = nil
    @connection.disable_referential_integrity do
      fk_enforced_during_block = @connection.select_value(<<~SQL)
        SELECT c.conenforced
        FROM pg_constraint c
        WHERE c.conname = 'ri_test_fk'
      SQL
    end

    assert_equal false, fk_enforced_during_block,
      "FK should be NOT ENFORCED inside the disable_referential_integrity block"

    fk_enforced_after = @connection.select_value(<<~SQL)
      SELECT c.conenforced
      FROM pg_constraint c
      WHERE c.conname = 'ri_test_fk'
    SQL

    assert_equal true, fk_enforced_after,
      "FK should be restored to ENFORCED after disable_referential_integrity block"
  ensure
    @connection.drop_table :ri_test_children, if_exists: true
    @connection.drop_table :ri_test_parents, if_exists: true
  end

  def test_deferrable_foreign_keys_are_restored_after_block
    skip unless @connection.supports_not_enforced_constraints?

    @connection.create_table :ri_test_parents, force: true
    @connection.create_table :ri_test_children, force: true do |t|
      t.bigint :parent_id, null: false
    end
    @connection.add_foreign_key :ri_test_children, :ri_test_parents,
      column: :parent_id, name: :ri_test_deferred_fk, deferrable: :deferred

    @connection.disable_referential_integrity { }

    condeferrable = @connection.select_value("SELECT c.condeferrable FROM pg_constraint c WHERE c.conname = 'ri_test_deferred_fk'")
    condeferred = @connection.select_value("SELECT c.condeferred FROM pg_constraint c WHERE c.conname = 'ri_test_deferred_fk'")

    assert condeferrable, "FK should remain DEFERRABLE after disable_referential_integrity block"
    assert condeferred, "FK should remain INITIALLY DEFERRED after disable_referential_integrity block"
  ensure
    @connection.drop_table :ri_test_children, if_exists: true
    @connection.drop_table :ri_test_parents, if_exists: true
  end

  def test_validated_foreign_keys_are_restored_after_block
    skip unless @connection.supports_not_enforced_constraints?

    @connection.create_table :ri_test_parents, force: true
    @connection.create_table :ri_test_children, force: true do |t|
      t.bigint :parent_id, null: false
    end
    @connection.add_foreign_key :ri_test_children, :ri_test_parents,
      column: :parent_id, name: :ri_test_validated_fk

    convalidated_before = @connection.select_value(<<~SQL)
      SELECT c.convalidated FROM pg_constraint c WHERE c.conname = 'ri_test_validated_fk'
    SQL
    assert convalidated_before, "FK should be VALIDATED before disable_referential_integrity block"

    @connection.disable_referential_integrity { }

    convalidated_after = @connection.select_value(<<~SQL)
      SELECT c.convalidated FROM pg_constraint c WHERE c.conname = 'ri_test_validated_fk'
    SQL
    assert convalidated_after, "FK should be restored to VALIDATED after disable_referential_integrity block"
  ensure
    @connection.drop_table :ri_test_children, if_exists: true
    @connection.drop_table :ri_test_parents, if_exists: true
  end

  def test_all_foreign_keys_valid_having_foreign_keys_in_multiple_schemas
    @connection.execute <<~SQL
      CREATE SCHEMA referential_integrity_test_schema;

      CREATE TABLE referential_integrity_test_schema.nodes (
        id          BIGSERIAL,
        parent_id   INT      NOT NULL,
        PRIMARY KEY(id),
        CONSTRAINT fk_parent_node FOREIGN KEY(parent_id)
                                  REFERENCES referential_integrity_test_schema.nodes(id)
      );
    SQL

    result = @connection.execute <<~SQL
      SELECT count(*) AS count
        FROM information_schema.table_constraints
       WHERE constraint_schema = 'referential_integrity_test_schema'
         AND constraint_type = 'FOREIGN KEY';
    SQL

    assert_equal 1, result.first["count"], "referential_integrity_test_schema should have 1 foreign key"
    @connection.check_all_foreign_keys_valid!
  ensure
    @connection.drop_schema "referential_integrity_test_schema", if_exists: true
  end

  private
    def assert_transaction_is_not_broken
      assert_equal 1, @connection.select_value("SELECT 1")
    end
end
