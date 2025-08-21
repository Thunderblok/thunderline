defmodule Thunderline.Repo.Migrations.ObanNotifyFunctions do
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    # Ensure scheduled_at has a default for immediate jobs
    alter table(:oban_jobs) do
      modify :scheduled_at, :utc_datetime_usec, default: fragment("now()"), null: false
    end

    # Add composite index Oban expects for efficient job fetching
    create_if_not_exists index(:oban_jobs, [:queue, :state, :priority, :scheduled_at])
    create_if_not_exists index(:oban_jobs, [:worker])

    # Create notify function & trigger only if they do not already exist
    execute(notify_function_sql())
    execute(insert_trigger_sql())
  end

  def down do
    # Best effort cleanup (don't fail if absent)
    execute("DROP TRIGGER IF EXISTS oban_notify_insert ON oban_jobs")
    execute("DROP FUNCTION IF EXISTS oban_notify()")
  end

  defp notify_function_sql do
    ~S'''
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'oban_notify'
      ) THEN
        CREATE FUNCTION oban_notify() RETURNS trigger LANGUAGE plpgsql AS $FUNCTION$
        BEGIN
          PERFORM pg_notify('oban_insert', '');
          RETURN NULL;
        END;
        $FUNCTION$;
      END IF;
    END;
    $$;
    '''
  end

  defp insert_trigger_sql do
    ~S'''
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'oban_notify_insert'
      ) THEN
        CREATE TRIGGER oban_notify_insert
        AFTER INSERT ON oban_jobs
        FOR EACH STATEMENT EXECUTE FUNCTION oban_notify();
      END IF;
    END;
    $$;
    '''
  end
end
