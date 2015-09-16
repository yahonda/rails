require 'active_record/connection_adapters/abstract_mysql_adapter'

gem 'mysql2', '~> 0.4.2'
require 'mysql2'

module ActiveRecord
  module ConnectionHandling # :nodoc:
    # Establishes a connection to the database that's used by all Active Record objects.
    def mysql2_connection(config)
      config = config.symbolize_keys

      config[:username] = 'root' if config[:username].nil?
      config[:flags] ||= 0

      if Mysql2::Client.const_defined? :FOUND_ROWS
        if config[:flags].kind_of? Array
          config[:flags].push "FOUND_ROWS".freeze
        else
          config[:flags] |= Mysql2::Client::FOUND_ROWS
        end
      end

      client = Mysql2::Client.new(config)
      ConnectionAdapters::Mysql2Adapter.new(client, logger, nil, config)
    rescue Mysql2::Error => error
      if error.message.include?("Unknown database")
        raise ActiveRecord::NoDatabaseError
      else
        raise
      end
    end
  end

  module ConnectionAdapters
    class Mysql2Adapter < AbstractMysqlAdapter
      ADAPTER_NAME = 'Mysql2'.freeze

      def initialize(connection, logger, connection_options, config)
        super
        configure_connection
      end

      def supports_json?
        !mariadb? && version >= '5.7.8'
      end

      # HELPER METHODS ===========================================

      def each_hash(result) # :nodoc:
        if block_given?
          result.each(:as => :hash, :symbolize_keys => true) do |row|
            yield row
          end
        else
          to_enum(:each_hash, result)
        end
      end

      def error_number(exception)
        exception.error_number if exception.respond_to?(:error_number)
      end

      #--
      # QUOTING ==================================================
      #++

      def quote_string(string)
        @connection.escape(string)
      end

      #--
      # CONNECTION MANAGEMENT ====================================
      #++

      def active?
        return false unless @connection
        @connection.ping
      end

      def reconnect!
        super
        disconnect!
        connect
      end
      alias :reset! :reconnect!

      # Disconnects from the database if already connected.
      # Otherwise, this method does nothing.
      def disconnect!
        super
        unless @connection.nil?
          @connection.close
          @connection = nil
        end
      end

      #--
      # DATABASE STATEMENTS ======================================
      #++

      # Returns a record hash with the column names as keys and column values
      # as values.
      def select_one(arel, name = nil, binds = [])
        arel, binds = binds_from_relation(arel, binds)
        @connection.query_options.merge!(as: :hash)
        select_result(to_sql(arel, binds), name, binds).each do |row|
          @connection.next_result while @connection.more_results?
          return row
        end
      ensure
        @connection.query_options.merge!(as: :array)
      end

      # Returns an array of arrays containing the field values.
      # Order is the same as that returned by +columns+.
      def select_rows(sql, name = nil, binds = [])
        result = select_result(sql, name, binds)
        @connection.next_result while @connection.more_results?
        result.to_a
      end

      def select_result(sql, name = nil, binds = []) # :nodoc:
        if without_prepared_statement?(binds)
          execute_and_free(sql, name) { |result| result }
        else
          exec_stmt_and_free(sql, name, binds, cache_stmt: true) { |_, result| result }
        end
      end
      private :select_result

      # Executes the SQL statement in the context of this connection.
      def execute(sql, name = nil)
        if @connection
          # make sure we carry over any changes to ActiveRecord::Base.default_timezone that have been
          # made since we established the connection
          @connection.query_options[:database_timezone] = ActiveRecord::Base.default_timezone
        end

        super
      end

      def exec_query(sql, name = 'SQL', binds = [], prepare: false) # :nodoc:
        if without_prepared_statement?(binds)
          execute_and_free(sql, name) do |result|
            ActiveRecord::Result.new(result.fields, result.to_a) if result
          end
        else
          exec_stmt_and_free(sql, name, binds, cache_stmt: prepare) do |_, result|
            ActiveRecord::Result.new(result.fields, result.to_a) if result
          end
        end
      end

      def last_inserted_id(result)
        @connection.last_id
      end

      private

      def exec_stmt_and_free(sql, name, binds, cache_stmt: false)
        if @connection
          # make sure we carry over any changes to ActiveRecord::Base.default_timezone that have been
          # made since we established the connection
          @connection.query_options[:database_timezone] = ActiveRecord::Base.default_timezone
        end

        type_casted_binds = binds.map { |attr| type_cast(attr.value_for_database) }

        log(sql, name, binds) do
          if !cache_stmt
            stmt = @connection.prepare(sql)
          else
            cache = @statements[sql] ||= {
              stmt: @connection.prepare(sql)
            }
            stmt = cache[:stmt]
          end

          begin
            result = stmt.execute(*type_casted_binds)
          rescue Mysql2::Error => e
            if !cache_stmt
              stmt.close
            else
              @statements.delete(sql)
            end
            raise e
          end

          ret = yield stmt, result
          stmt.close if !cache_stmt
          ret
        end
      end

      def connect
        @connection = Mysql2::Client.new(@config)
        configure_connection
      end

      def configure_connection
        @connection.query_options.merge!(:as => :array)
        super
      end

      def full_version
        @full_version ||= @connection.server_info[:version]
      end
    end
  end
end
