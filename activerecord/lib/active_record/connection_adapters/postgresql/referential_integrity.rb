# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module ReferentialIntegrity # :nodoc:
        def disable_referential_integrity # :nodoc:
          if supports_not_enforced_constraints?
            # PostgreSQL 18+: Use NOT ENFORCED / ENFORCED — requires only table ownership, not superuser.
            # Only toggle FKs that are currently ENFORCED; leave NOT ENFORCED ones unchanged.
            enforced_fks = query_all(<<~SQL)
              SELECT n.nspname AS schema_name, t.relname AS table_name, c.conname AS constraint_name,
                     c.condeferrable AS deferrable, c.condeferred AS deferred
              FROM pg_constraint c
              JOIN pg_class t ON c.conrelid = t.oid
              JOIN pg_namespace n ON c.connamespace = n.oid
              WHERE c.contype = 'f'
                AND c.conenforced = true
            SQL

            enforced_fks.each do |fk|
              execute("ALTER TABLE #{quote_table_name(fk["schema_name"])}.#{quote_table_name(fk["table_name"])} " \
                      "ALTER CONSTRAINT #{quote_column_name(fk["constraint_name"])} NOT ENFORCED")
            end

            begin
              yield
            ensure
              enforced_fks.each do |fk|
                schema = quote_table_name(fk["schema_name"])
                table  = quote_table_name(fk["table_name"])
                constraint = quote_column_name(fk["constraint_name"])
                # Re-state the DEFERRABLE clause explicitly when re-enforcing the constraint.
                # PostgreSQL 18 has a bug where toggling NOT ENFORCED → ENFORCED resets the
                # tgdeferrable/tginitdeferred trigger flags in pg_trigger to false, silently
                # breaking deferred constraint behavior even though pg_constraint retains the
                # correct definition. By including the deferrable clause in the ALTER CONSTRAINT
                # statement we force PostgreSQL to reconstruct the triggers correctly.
                # TODO: Remove this workaround once the upstream fix is released:
                # https://www.mail-archive.com/pgsql-hackers@lists.postgresql.org/msg221360.html
                deferrable_sql = if fk["deferrable"]
                  fk["deferred"] ? "DEFERRABLE INITIALLY DEFERRED " : "DEFERRABLE INITIALLY IMMEDIATE "
                end

                begin
                  execute("ALTER TABLE #{schema}.#{table} ALTER CONSTRAINT #{constraint} #{deferrable_sql}ENFORCED")
                rescue ActiveRecord::InvalidForeignKey
                  # InvalidForeignKey is a subclass of StatementInvalid, so it must be rescued
                  # first and re-raised to let callers surface a meaningful FK violation error.
                  raise
                rescue ActiveRecord::StatementInvalid
                  # The transaction may be in an aborted state due to a SQL error in the block.
                  # Since ALTER CONSTRAINT is transactional, the subsequent rollback will restore
                  # the FK states automatically. Stop trying to restore further constraints.
                  break
                end
              end
            end
          else
            original_exception = nil

            begin
              transaction(requires_new: true) do
                execute(tables.collect { |name| "ALTER TABLE #{quote_table_name(name)} DISABLE TRIGGER ALL" }.join(";"))
              end
            rescue ActiveRecord::ActiveRecordError => e
              original_exception = e
            end

            begin
              yield
            rescue ActiveRecord::InvalidForeignKey => e
              warn <<~WARNING
                WARNING: Rails was not able to disable referential integrity.

                This is most likely caused due to missing permissions.
                Rails needs superuser privileges to disable referential integrity.

                    cause: #{original_exception&.message}

              WARNING
              raise e
            end

            begin
              transaction(requires_new: true) do
                execute(tables.collect { |name| "ALTER TABLE #{quote_table_name(name)} ENABLE TRIGGER ALL" }.join(";"))
              end
            rescue ActiveRecord::ActiveRecordError
            end
          end
        end

        def check_all_foreign_keys_valid! # :nodoc:
          sql = <<~SQL
            do $$
              declare r record;
            BEGIN
            FOR r IN (
              SELECT FORMAT(
                'UPDATE pg_catalog.pg_constraint SET convalidated=false WHERE conname = ''%1$I'' AND connamespace::regnamespace = ''%2$I''::regnamespace; ALTER TABLE %2$I.%3$I VALIDATE CONSTRAINT %1$I;',
                constraint_name,
                table_schema,
                table_name
              ) AS constraint_check
              FROM information_schema.table_constraints WHERE constraint_type = 'FOREIGN KEY'
            )
              LOOP
                EXECUTE (r.constraint_check);
              END LOOP;
            END;
            $$;
          SQL

          transaction(requires_new: true) do
            execute(sql)
          end
        end
      end
    end
  end
end
