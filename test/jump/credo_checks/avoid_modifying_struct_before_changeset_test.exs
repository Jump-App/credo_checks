defmodule Jump.CredoChecks.AvoidModifyingStructBeforeChangesetTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.AvoidModifyingStructBeforeChangeset

  describe "flags a struct modified inline before a changeset function" do
    test "struct update syntax as the first argument" do
      """
      defmodule MyApp.Accounts do
        def move_user(existing_user, account_id, params) do
          User.changeset(%{existing_user | account_id: account_id}, params)
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue(fn issue ->
        assert issue.line_no == 3
        assert issue.trigger == "User.changeset"
        assert issue.message =~ "bypass"
      end)
    end

    test "struct update syntax piped into the changeset" do
      """
      defmodule MyApp.Accounts do
        def move_user(existing_user, account_id, params) do
          %{existing_user | account_id: account_id}
          |> User.changeset(params)
          |> Repo.update()
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue(fn issue ->
        assert issue.line_no == 4
        assert issue.trigger == "User.changeset"
      end)
    end

    test "variable piped through a struct update into the changeset" do
      """
      defmodule MyApp.Accounts do
        def move_user(existing_user, account_id, params) do
          existing_user
          |> Map.put(:account_id, account_id)
          |> User.changeset(params)
          |> Repo.update()
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue(fn issue -> assert issue.line_no == 5 end)
    end

    test "struct update syntax that names the struct module" do
      """
      defmodule MyApp.Accounts do
        def move_user(existing_user, account_id, params) do
          User.changeset(%User{existing_user | account_id: account_id}, params)
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue()
    end

    test "Map and Kernel functions that modify a struct" do
      for modification <- [
            "Map.put(user, :account_id, account_id)",
            "Map.put_new(user, :account_id, account_id)",
            "Map.merge(user, %{account_id: account_id})",
            "Map.replace(user, :account_id, account_id)",
            "Map.replace!(user, :account_id, account_id)",
            "Map.update(user, :account_id, account_id, fn _ -> account_id end)",
            "Map.update!(user, :account_id, fn _ -> account_id end)",
            "struct(user, account_id: account_id)",
            "struct!(user, account_id: account_id)",
            "Kernel.struct(user, account_id: account_id)",
            "put_in(user.account_id, account_id)",
            "put_in(user, [Access.key(:account_id)], account_id)",
            "update_in(user.account_id, fn _ -> account_id end)"
          ] do
        """
        defmodule MyApp.Accounts do
          def move_user(user, account_id, params) do
            User.changeset(#{modification}, params)
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> assert_issue()
      end
    end

    test "piped Map and Kernel functions that modify a struct" do
      for modification <- [
            "Map.put(:account_id, account_id)",
            "Map.merge(%{account_id: account_id})",
            "struct(account_id: account_id)",
            "put_in([Access.key(:account_id)], account_id)"
          ] do
        """
        defmodule MyApp.Accounts do
          def move_user(user, account_id, params) do
            user
            |> #{modification}
            |> User.changeset(params)
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> assert_issue()
      end
    end
  end

  describe "recognizes changeset functions" do
    test "any function with changeset in the name, qualified or not" do
      for call <- [
            "User.changeset(%{user | account_id: account_id}, params)",
            "MyApp.Accounts.User.changeset(%{user | account_id: account_id}, params)",
            "User.registration_changeset(%{user | account_id: account_id}, params)",
            "User.changeset_for_registration(%{user | account_id: account_id}, params)",
            "changeset(%{user | account_id: account_id}, params)",
            "update_changeset(%{user | account_id: account_id}, params)"
          ] do
        """
        defmodule MyApp.Accounts do
          def move_user(user, account_id, params) do
            #{call}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> assert_issue()
      end
    end

    test "Ecto.Changeset.cast/4 and change/2, qualified, aliased, or imported" do
      for call <- [
            "Ecto.Changeset.cast(%{user | account_id: account_id}, params, [:name])",
            "Ecto.Changeset.change(%{user | account_id: account_id}, name: name)",
            "Ecto.Changeset.change(%{user | account_id: account_id})",
            "Changeset.cast(%{user | account_id: account_id}, params, [:name])",
            "Changeset.change(%{user | account_id: account_id})",
            "cast(%{user | account_id: account_id}, params, [:name])",
            "change(%{user | account_id: account_id})"
          ] do
        """
        defmodule MyApp.Accounts do
          import Ecto.Changeset
          alias Ecto.Changeset

          def move_user(user, account_id, name, params) do
            #{call}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> assert_issue()
      end
    end

    test "piped into cast" do
      """
      defmodule MyApp.Accounts.User do
        import Ecto.Changeset

        def changeset(user, attrs) do
          %{user | name: String.trim(user.name)}
          |> cast(attrs, [:name])
          |> validate_required([:name])
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue(fn issue -> assert issue.trigger == "cast" end)
    end
  end

  describe "flags a struct modified by a local helper function" do
    test "helper using struct update syntax, piped into the changeset" do
      """
      defmodule MyApp.Actions do
        @spec copy_action(Action.t(), String.t(), map(), map()) :: Action.t()
        def copy_action(action, destination_id, %{} = template_map, %{} = block_template_map) do
          action
          |> put_destination_id(destination_id)
          |> Action.changeset(%{})
          |> Repo.insert!()
        end

        defp put_destination_id(action, destination_id), do: %{action | destination_id: destination_id}
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue(fn issue ->
        assert issue.line_no == 6
        assert issue.trigger == "Action.changeset"
      end)
    end

    test "helper called directly as the first argument" do
      """
      defmodule MyApp.Actions do
        def copy_action(action, destination_id) do
          Action.changeset(put_destination_id(action, destination_id), %{})
        end

        defp put_destination_id(action, destination_id), do: Map.put(action, :destination_id, destination_id)
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue()
    end

    test "helper defined after use with a multi-line body ending in a modification" do
      """
      defmodule MyApp.Actions do
        def copy_action(action, destination_id) do
          action
          |> put_destination_id(destination_id)
          |> Action.changeset(%{})
        end

        def put_destination_id(action, destination_id) do
          destination_id = String.trim(destination_id)
          action |> Map.put(:destination_id, destination_id)
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue()
    end

    test "multi-clause helper where only one clause modifies the struct" do
      """
      defmodule MyApp.Actions do
        def copy_action(action, destination_id) do
          action
          |> maybe_put_destination_id(destination_id)
          |> Action.changeset(%{})
        end

        defp maybe_put_destination_id(action, nil), do: action
        defp maybe_put_destination_id(action, id) when is_binary(id), do: %{action | destination_id: id}
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue()
    end

    test "helper that conditionally modifies the struct" do
      for body <- [
            "if destination_id, do: %{action | destination_id: destination_id}, else: action",
            """
            case destination_id do
                nil -> action
                id -> %{action | destination_id: id}
              end
            """
          ] do
        """
        defmodule MyApp.Actions do
          def copy_action(action, destination_id) do
            action
            |> maybe_put_destination_id(destination_id)
            |> Action.changeset(%{})
          end

          defp maybe_put_destination_id(action, destination_id) do
            #{body}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> assert_issue()
      end
    end
  end

  describe "flags a variable bound to a modified struct earlier in the same block" do
    test "passed directly or piped into the changeset" do
      for call <- ["User.changeset(user, params)", "user |> User.changeset(params) |> Repo.update()"] do
        """
        defmodule MyApp.Accounts do
          def move_user(user, account_id, params) do
            user = %{user | account_id: account_id}
            #{call}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> assert_issue(fn issue -> assert issue.line_no == 4 end)
      end
    end

    test "changeset call nested inside a later expression" do
      """
      defmodule MyApp.Accounts do
        def move_user(user, account_id, params) do
          moved_user = Map.put(user, :account_id, account_id)
          {:ok, user} = Repo.update(User.changeset(moved_user, params))
          user
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue(fn issue -> assert issue.line_no == 4 end)
    end

    test "bound via a local helper" do
      """
      defmodule MyApp.Actions do
        def copy_action(action, destination_id) do
          action = put_destination_id(action, destination_id)
          Action.changeset(action, %{})
        end

        defp put_destination_id(action, destination_id), do: %{action | destination_id: destination_id}
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue()
    end

    test "bound via a conditional modification" do
      """
      defmodule MyApp.Accounts do
        def move_user(user, account_id, params) do
          user = if account_id, do: %{user | account_id: account_id}, else: user
          User.changeset(user, params)
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue()
    end
  end

  test "reports one issue per offending changeset call" do
    """
    defmodule MyApp.Accounts do
      def move_users(user_a, user_b, account_id, params) do
        a = User.changeset(%{user_a | account_id: account_id}, params)
        b = %{user_b | account_id: account_id} |> User.changeset(params)
        [a, b]
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidModifyingStructBeforeChangeset)
    |> assert_issues(fn issues -> assert issues |> Enum.map(& &1.line_no) |> Enum.sort() == [3, 4] end)
  end

  describe "does not flag" do
    test "an unmodified struct" do
      for call <- [
            "User.changeset(user, params)",
            "user |> User.changeset(params) |> Repo.update()",
            "User |> Repo.get!(id) |> User.changeset(params)",
            "user |> Repo.preload(:account) |> User.changeset(params)",
            "Ecto.build_assoc(account, :users) |> User.changeset(params)"
          ] do
        """
        defmodule MyApp.Accounts do
          def update_user(user, account, id, params) do
            #{call}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> refute_issues()
      end
    end

    test "params passed in to build an implied, new struct" do
      for params_name <- ["map", "attrs", "attributes", "params"],
          call <- [
            "User.changeset(#{params_name})",
            "#{params_name} |> Map.put(:account_id, account_id) |> User.changeset() |> Repo.update()",
            ~s'#{params_name} |> Map.put("account_id", account_id) |> User.changeset() |> Repo.update()',
            "#{params_name} = Map.put(#{params_name}, :account_id, account_id)\nUser.changeset(#{params_name})"
          ] do
        """
        defmodule MyApp.Accounts do
          def update_user(user, account, id, params) do
            #{call}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> refute_issues()
      end
    end

    test "a newly constructed struct" do
      for call <- [
            "%User{account_id: account_id} |> User.changeset(params) |> Repo.insert()",
            "User.changeset(%User{account_id: account_id}, params)",
            "struct(User, account_id: account_id) |> User.changeset(params)",
            "User |> struct(account_id: account_id) |> User.changeset(params)",
            "struct!(__MODULE__, account_id: account_id) |> changeset(params)",
            "%__MODULE__{account_id: account_id} |> changeset(params)"
          ] do
        """
        defmodule MyApp.Accounts.User do
          def create(account_id, params) do
            #{call}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> refute_issues()
      end
    end

    test "map update syntax in the params, rather than the struct" do
      for call <- [
            ~s[User.changeset(user, %{params | "account_id" => account_id})],
            ~s[user |> User.changeset(%{params | "account_id" => account_id})],
            ~s[user |> User.changeset(Map.put(params, "account_id", account_id))]
          ] do
        """
        defmodule MyApp.Accounts do
          def move_user(user, account_id, params) do
            #{call}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> refute_issues()
      end
    end

    test "a modified struct passed to a function that isn't a changeset function" do
      """
      defmodule MyApp.Accounts do
        def move_user(user, account_id) do
          notify(%{user | account_id: account_id})
          user |> Map.put(:account_id, account_id) |> render_preview()
          changesets = Enum.map(users, & &1.changeset)
          changeset_count = length(changesets)
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> refute_issues()
    end

    test "a changeset piped into another changeset function" do
      """
      defmodule MyApp.Accounts do
        def move_user(user, params) do
          user
          |> User.changeset(params)
          |> User.password_changeset(params)
          |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now())
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> refute_issues()
    end

    test "a local helper that doesn't modify the struct" do
      """
      defmodule MyApp.Actions do
        def copy_action(action) do
          action
          |> with_blocks()
          |> Action.changeset(%{})
        end

        defp with_blocks(action), do: Repo.preload(action, :blocks)
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> refute_issues()
    end

    test "a local helper whose arity doesn't match the call" do
      """
      defmodule MyApp.Actions do
        def copy_action(action, destination_id) do
          action
          |> put_destination_id()
          |> Action.changeset(%{})
        end

        defp put_destination_id(action), do: Repo.preload(action, :destination)
        defp put_destination_id(action, destination_id), do: %{action | destination_id: destination_id}
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> refute_issues()
    end

    test "a helper that isn't defined in the file" do
      """
      defmodule MyApp.Actions do
        import MyApp.ActionHelpers

        def copy_action(action, destination_id) do
          action
          |> put_destination_id(destination_id)
          |> Action.changeset(%{})
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> refute_issues()
    end

    test "a modified variable that is rebound before reaching the changeset" do
      """
      defmodule MyApp.Accounts do
        def move_user(user, account_id, params) do
          user = %{user | account_id: account_id}
          notify(user)
          user = Repo.get!(User, user.id)
          User.changeset(user, params)
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> refute_issues()
    end

    test "a modified variable rebound by a destructuring pattern" do
      """
      defmodule MyApp.Accounts do
        def move_user(user, account_id, params) do
          user = %{user | account_id: account_id}
          {:ok, user} = Accounts.reload(user)
          User.changeset(user, params)
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> refute_issues()
    end

    test "a modified variable shadowed by a fn, case, for, or with clause" do
      for shadowing_expr <- [
            "Enum.map(users, fn user -> User.changeset(user, params) end)",
            """
            case Repo.get(User, user.id) do
                nil -> :error
                user -> User.changeset(user, params)
              end
            """,
            "for user <- users, do: User.changeset(user, params)",
            "with {:ok, user} <- Accounts.reload(user), do: User.changeset(user, params)"
          ] do
        """
        defmodule MyApp.Accounts do
          def move_users(user, users, account_id, params) do
            user = %{user | account_id: account_id}
            notify(user)
            #{shadowing_expr}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> refute_issues()
      end
    end

    test "a different variable than the one that was modified" do
      """
      defmodule MyApp.Accounts do
        def move_user(user, account_id, params) do
          preview = %{user | account_id: account_id}
          notify(preview)
          User.changeset(user, params)
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> refute_issues()
    end

    test "a changeset variable with a modified action" do
      """
      defmodule MyAppWeb.UserLive.FormComponent do
        def handle_event("validate", %{"user" => params}, socket) do
          changeset = User.changeset(socket.assigns.user, params)
          changeset = %{changeset | action: :validate}
          {:noreply, assign(socket, form: to_form(changeset))}
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> refute_issues()
    end
  end
end
