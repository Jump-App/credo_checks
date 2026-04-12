defmodule Jump.CredoChecks.PreferTextColumnsTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.PreferTextColumns

  test "alerts on :string column type in migration file" do
    """
    defmodule MyApp.Repo.Migrations.CreateUsers do
      use Ecto.Migration

      def change do
        create table(:users) do
          add :name, :string
          add :email, :string, null: false
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20240101000000_create_users.exs")
    |> run_check(PreferTextColumns)
    |> assert_issues()
  end

  test "alerts on modify with :string column type in migration file" do
    """
    defmodule MyApp.Repo.Migrations.ModifyUsers do
      use Ecto.Migration

      def change do
        alter table(:users) do
          modify :name, :string
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20240101000001_modify_users.exs")
    |> run_check(PreferTextColumns)
    |> assert_issue()
  end

  test "does not alert on :text column type in migration file" do
    """
    defmodule MyApp.Repo.Migrations.CreateUsers do
      use Ecto.Migration

      def change do
        create table(:users) do
          add :name, :text
          add :email, :text, null: false
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20240101000000_create_users.exs")
    |> run_check(PreferTextColumns)
    |> refute_issues()
  end

  test "ignores migrations after the custom start_after" do
    problem_module_body = """
    defmodule MyApp.Repo.Migrations.CreateUsers do
      use Ecto.Migration

      def change do
        create table(:users) do
          add :name, :string
          add :email, :string, null: false
        end
      end
    end
    """

    start_after = "20240101000000"

    for too_early_timestamp <- ["20231231000001", "2024010100000"] do
      problem_module_body
      |> to_source_file("priv/repo/migrations/#{too_early_timestamp}_create_users.exs")
      |> run_check(PreferTextColumns, start_after: start_after)
      |> refute_issues()
    end

    for after_timestamp <- ["20240101000001", "20250101000002"] do
      problem_module_body
      |> to_source_file("priv/repo/migrations/#{after_timestamp}_create_users.exs")
      |> run_check(PreferTextColumns, start_after: start_after)
      |> assert_issues()
    end
  end

  test "does not alert on :string in non-migration files" do
    """
    defmodule MyModule do
      def some_function do
        add :name, :string
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferTextColumns)
    |> refute_issues()
  end
end
