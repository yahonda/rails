require 'cases/helper'
require 'support/schema_dumping_helper'

if ActiveRecord::Base.connection.supports_virtual_columns?
class Mysql2GeneratedColumnTest < ActiveRecord::Mysql2TestCase
  include SchemaDumpingHelper
  self.use_transactional_tests = false

  class GeneratedColumn < ActiveRecord::Base
  end

  def setup
    @connection = ActiveRecord::Base.connection
    @connection.create_table :generated_columns, force: true do |t|
      t.string  :name
      t.virtual :upper_name,  type: :string,  as: 'UPPER(name)'
      t.virtual :name_length, type: :integer, as: 'LENGTH(name)', virtual: :stored
    end
    GeneratedColumn.create(name: 'Rails')
  end

  def teardown
    @connection.drop_table :generated_columns, if_exists: true
    GeneratedColumn.reset_column_information
  end

  def test_virtual_column
    column = GeneratedColumn.columns_hash['upper_name']
    assert column.virtual?
    assert_equal 'VIRTUAL GENERATED', column.extra
    assert_equal 'RAILS', GeneratedColumn.take.upper_name
  end

  def test_stored_column
    column = GeneratedColumn.columns_hash['name_length']
    assert column.virtual?
    assert_equal 'STORED GENERATED', column.extra
    assert_equal 5, GeneratedColumn.take.name_length
  end

  def test_change_table
    @connection.change_table :generated_columns do |t|
      t.virtual :lower_name, type: :string, as: 'LOWER(name)'
    end
    GeneratedColumn.reset_column_information
    column = GeneratedColumn.columns_hash['lower_name']
    assert column.virtual?
    assert_equal 'VIRTUAL GENERATED', column.extra
    assert_equal 'rails', GeneratedColumn.take.lower_name
  end

  def test_schema_dumping
    output = dump_table_schema("generated_columns")
    assert_match(/t\.string\s+"upper_name",\s+as: "UPPER\(name\)",\s+virtual: true$/, output)
    assert_match(/t\.integer\s+"name_length",\s+as: "LENGTH\(name\)",\s+virtual: :stored$/, output)
  end
end
end
