defmodule Jump.CredoChecks.PreferChangeOverUpDownMigrationsTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.PreferChangeOverUpDownMigrations

  test "flags up + down using alter table with add" do
    """
    defmodule MyApp.Repo.Migrations.AddSalesforceRecordTypes do
      use Ecto.Migration

      def up do
        alter table(:integration_schemas) do
          add :salesforce_record_types, :jsonb,
            null: false,
            default: fragment("'[]'::jsonb")
        end
      end

      def down do
        alter table(:integration_schemas) do
          remove :salesforce_record_types
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000001_add_salesforce_record_types.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue(fn issue ->
      assert issue.trigger == "def up"
      assert issue.message =~ "change/0"
    end)
  end

  test "flags up + down with create table" do
    """
    defmodule MyApp.Repo.Migrations.CreateUsers do
      use Ecto.Migration

      def up do
        create table(:users) do
          add :email, :text, null: false
          timestamps()
        end
      end

      def down do
        drop table(:users)
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000002_create_users.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with create_if_not_exists table" do
    """
    defmodule MyApp.Repo.Migrations.CreateUsersIfNotExists do
      use Ecto.Migration

      def up do
        create_if_not_exists table(:users) do
          add :email, :text, null: false
        end
      end

      def down do
        drop_if_exists table(:users)
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000003_create_users_if_not_exists.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with create index" do
    """
    defmodule MyApp.Repo.Migrations.AddIndex do
      use Ecto.Migration

      def up do
        create index(:users, [:email])
      end

      def down do
        drop index(:users, [:email])
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000004_add_index.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with drop index" do
    """
    defmodule MyApp.Repo.Migrations.RemoveIndex do
      use Ecto.Migration

      def up do
        drop index(:users, [:email])
      end

      def down do
        create index(:users, [:email])
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000023_remove_index.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with drop_if_exists index" do
    """
    defmodule MyApp.Repo.Migrations.RemoveIndexIfExists do
      use Ecto.Migration

      def up do
        drop_if_exists index(:users, [:email])
      end

      def down do
        create_if_not_exists index(:users, [:email])
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000024_remove_index_if_exists.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with create unique_index" do
    """
    defmodule MyApp.Repo.Migrations.AddUniqueIndex do
      use Ecto.Migration

      def up do
        create unique_index(:users, [:email])
      end

      def down do
        drop unique_index(:users, [:email])
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000005_add_unique_index.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with create constraint" do
    """
    defmodule MyApp.Repo.Migrations.AddCheck do
      use Ecto.Migration

      def up do
        create constraint("users", :age_must_be_positive, check: "age > 0")
      end

      def down do
        drop constraint("users", :age_must_be_positive)
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000006_add_check.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with rename column" do
    """
    defmodule MyApp.Repo.Migrations.RenameColumn do
      use Ecto.Migration

      def up do
        rename table(:users), :name, to: :full_name
      end

      def down do
        rename table(:users), :full_name, to: :name
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000007_rename_column.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with rename table" do
    """
    defmodule MyApp.Repo.Migrations.RenameTable do
      use Ecto.Migration

      def up do
        rename table(:posts), to: table(:articles)
      end

      def down do
        rename table(:articles), to: table(:posts)
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000008_rename_table.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with rename index" do
    """
    defmodule MyApp.Repo.Migrations.RenameIndex do
      use Ecto.Migration

      def up do
        rename index(:people, [:name], name: "persons_name_index"), to: "people_name_index"
      end

      def down do
        rename index(:people, [:name], name: "people_name_index"), to: "persons_name_index"
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000025_rename_index.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with modify and from option" do
    """
    defmodule MyApp.Repo.Migrations.ChangeType do
      use Ecto.Migration

      def up do
        alter table(:users) do
          modify :age, :integer, from: :string
        end
      end

      def down do
        alter table(:users) do
          modify :age, :string, from: :integer
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000009_change_type.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with multiple reversible operations" do
    """
    defmodule MyApp.Repo.Migrations.MultiOp do
      use Ecto.Migration

      def up do
        alter table(:users) do
          add :age, :integer
        end

        create index(:users, [:age])
      end

      def down do
        drop index(:users, [:age])

        alter table(:users) do
          remove :age, :integer
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000010_multi_op.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with execute/2 (explicit reverse)" do
    """
    defmodule MyApp.Repo.Migrations.ExplicitReverse do
      use Ecto.Migration

      def up do
        execute "CREATE EXTENSION pgcrypto", "DROP EXTENSION pgcrypto"
      end

      def down do
        execute "DROP EXTENSION pgcrypto", "CREATE EXTENSION pgcrypto"
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000011_explicit_reverse.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with execute_file/2 (explicit reverse)" do
    """
    defmodule MyApp.Repo.Migrations.ExplicitReverseFile do
      use Ecto.Migration

      def up do
        execute_file "up.sql", "down.sql"
      end

      def down do
        execute_file "down.sql", "up.sql"
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000026_explicit_reverse_file.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "flags up + down with remove that includes type" do
    """
    defmodule MyApp.Repo.Migrations.RemoveCol do
      use Ecto.Migration

      def up do
        alter table(:users) do
          remove :legacy_flag, :boolean, default: false
        end
      end

      def down do
        alter table(:users) do
          add :legacy_flag, :boolean, default: false
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000012_remove_col.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> assert_issue()
  end

  test "does not flag when up uses add_if_not_exists (not auto-reversible)" do
    """
    defmodule MyApp.Repo.Migrations.AddColIfNotExists do
      use Ecto.Migration

      def up do
        alter table(:users) do
          add_if_not_exists :nickname, :text
        end
      end

      def down do
        alter table(:users) do
          remove_if_exists :nickname
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000027_add_col_if_not_exists.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end

  test "does not flag when up uses remove_if_exists with type (not auto-reversible)" do
    """
    defmodule MyApp.Repo.Migrations.RemoveColIfExists do
      use Ecto.Migration

      def up do
        alter table(:users) do
          remove_if_exists :nickname, :text
        end
      end

      def down do
        alter table(:users) do
          add_if_not_exists :nickname, :text
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000028_remove_col_if_exists.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end

  test "does not flag when up uses raw execute/1 (not auto-reversible)" do
    """
    defmodule MyApp.Repo.Migrations.AddIndexConcurrently do
      use Ecto.Migration

      def up do
        execute "CREATE INDEX CONCURRENTLY idx_users_email ON users (email)"
      end

      def down do
        execute "DROP INDEX idx_users_email"
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000013_add_index_concurrently.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end

  test "does not flag when up uses drop (not auto-reversible)" do
    """
    defmodule MyApp.Repo.Migrations.DropTable do
      use Ecto.Migration

      def up do
        drop table(:users)
      end

      def down do
        create table(:users) do
          add :email, :text
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000014_drop_table.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end

  test "does not flag when up uses remove without type (not auto-reversible)" do
    """
    defmodule MyApp.Repo.Migrations.RemoveColWithoutType do
      use Ecto.Migration

      def up do
        alter table(:users) do
          remove :legacy
        end
      end

      def down do
        alter table(:users) do
          add :legacy, :text
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000015_remove_col_without_type.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end

  test "does not flag when up uses modify without :from (not auto-reversible)" do
    """
    defmodule MyApp.Repo.Migrations.ModifyCol do
      use Ecto.Migration

      def up do
        alter table(:users) do
          modify :age, :integer
        end
      end

      def down do
        alter table(:users) do
          modify :age, :string
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000016_modify_col.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end

  test "does not flag when up uses modify with nil :from (not auto-reversible)" do
    """
    defmodule MyApp.Repo.Migrations.ModifyColFromNil do
      use Ecto.Migration

      def up do
        alter table(:users) do
          modify :age, :integer, from: nil
        end
      end

      def down do
        alter table(:users) do
          modify :age, :string, from: :integer
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000029_modify_col_from_nil.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end

  test "does not flag when up mixes reversible ops with raw execute/1" do
    """
    defmodule MyApp.Repo.Migrations.AddAndBackfill do
      use Ecto.Migration

      def up do
        alter table(:users) do
          add :status, :text
        end

        execute "UPDATE users SET status = 'active'"
      end

      def down do
        alter table(:users) do
          remove :status, :text
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000017_add_and_backfill.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end

  test "does not flag when only change is defined" do
    """
    defmodule MyApp.Repo.Migrations.AddIt do
      use Ecto.Migration

      def change do
        alter table(:users) do
          add :age, :integer
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000018_add_it.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end

  test "does not flag when only up is defined (no down)" do
    """
    defmodule MyApp.Repo.Migrations.UpOnly do
      use Ecto.Migration

      def up do
        alter table(:users) do
          add :age, :integer
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000019_up_only.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end

  test "does not flag when up calls arbitrary helper functions" do
    """
    defmodule MyApp.Repo.Migrations.ArbitraryCalls do
      use Ecto.Migration

      def up do
        do_some_setup()

        alter table(:users) do
          add :age, :integer
        end
      end

      def down do
        alter table(:users) do
          remove :age, :integer
        end
      end

      defp do_some_setup, do: :ok
    end
    """
    |> to_source_file("priv/repo/migrations/20260101000020_arbitrary_calls.exs")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end

  test "does not flag in non-migration files" do
    """
    defmodule MyApp.Other do
      def up do
        alter_state()
      end

      def down do
        alter_state()
      end

      defp alter_state, do: :ok
    end
    """
    |> to_source_file("lib/my_app/other.ex")
    |> run_check(PreferChangeOverUpDownMigrations)
    |> refute_issues()
  end
end
