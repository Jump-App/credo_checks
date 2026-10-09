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

    test "a struct modified using a map of params" do
      for call <- [
            "user |> Map.merge(params) |> User.changeset(attrs)",
            "User.changeset(struct(user, attrs), params)",
            "%{user | account_id: params.account_id} |> User.changeset(params)"
          ] do
        """
        defmodule MyApp.Accounts do
          def move_user(user, attrs, params) do
            #{call}
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
      defmodule MyApp.Accounts do
        import Ecto.Changeset

        def rename_user(user, attrs) do
          %{user | name: String.trim(user.name)}
          |> cast(attrs, [:name])
          |> Repo.update()
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

    test "a changeset variable used for more than to_form" do
      for statements <- [
            """
            changeset = Contact.changeset(%{contact | account_id: account_id}, params)
            assign(socket, changeset: changeset, form: to_form(changeset))
            """,
            """
            changeset = Contact.changeset(%{contact | account_id: account_id}, params)
            if connected?(socket), do: Repo.update(changeset)
            assign(socket, form: to_form(changeset))
            """,
            """
            changeset = Contact.changeset(%{contact | account_id: account_id}, params)
            changeset = %{changeset | action: :update}
            Repo.update(changeset)
            """,
            """
            _result = Repo.update(Contact.changeset(%{contact | account_id: account_id}, params))
            assign(socket, form: to_form(Contact.changeset(contact, params)))
            """
          ] do
        """
        defmodule MyAppWeb.ContactLive.FormComponent do
          def save_contact(contact, account_id, params, socket) do
            #{statements}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> assert_issue(fn issue -> assert issue.line_no == 3 end)
      end
    end

    test "a changeset variable used for more than apply_changes" do
      """
      defmodule MyApp.Accounts do
        def move_user(user, account_id, params) do
          changeset = User.changeset(%{user | account_id: account_id}, params)
          notify(Ecto.Changeset.apply_changes(changeset))
          Repo.update(changeset)
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue(fn issue -> assert issue.line_no == 3 end)
    end

    test "a changeset variable returned from the block" do
      """
      defmodule MyApp.Contacts do
        def move_contact(contact, account_id, params) do
          contact = Repo.preload(contact, :account)
          changeset = Contact.changeset(%{contact | account_id: account_id}, params)
        end
      end
      """
      |> to_source_file()
      |> run_check(AvoidModifyingStructBeforeChangeset)
      |> assert_issue(fn issue -> assert issue.line_no == 4 end)
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
      for params_name <- ["map", "attrs", "attributes", "params", "parameters"],
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

    test "a modified map of params passed to a changeset function along with other arguments" do
      for params_name <- ["map", "attrs", "attributes", "params", "parameters"],
          statements <- [
            """
            #{params_name} = normalize_form_params(#{params_name})
            changeset = rubric_form_changeset(#{params_name}, require_task?: selected_rubric == nil)
            Repo.insert(changeset)
            """,
            "#{params_name} = normalize_form_params(form_data)\nRubric.changeset(#{params_name}, opts)",
            "#{params_name} |> normalize_form_params() |> Rubric.changeset(opts)",
            "#{params_name} |> Map.put(:account_id, account_id) |> Rubric.changeset(opts)",
            "#{params_name} |> Map.put(:account_id, account_id) |> Map.put(:name, name) |> Rubric.changeset(opts)",
            "Rubric.changeset(%{#{params_name} | account_id: account_id}, opts)",
            ~s'Rubric.changeset(put_in(#{params_name}["account_id"], account_id), opts)',
            "form_attrs = Map.put(#{params_name}, :account_id, account_id)\nRubric.changeset(form_attrs, opts)"
          ] do
        """
        defmodule MyApp.Rubrics do
          def create_rubric(#{params_name}, form_data, selected_rubric, account_id, name, opts) do
            #{statements}
          end

          defp normalize_form_params(form), do: Map.update!(form, :name, &String.trim/1)
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

    test "a new struct built from a variable named for a module" do
      for statements <- [
            "struct(module, %{id: Ecto.UUID.generate()}) |> module.changeset(params)",
            "module |> struct(%{id: Ecto.UUID.generate()}) |> module.changeset(params)",
            "schema_module |> struct!(id: Ecto.UUID.generate()) |> changeset(params)",
            "Kernel.struct(module_name, id: Ecto.UUID.generate()) |> changeset(params)",
            "record = struct(module, id: Ecto.UUID.generate())\nmodule.changeset(record, params)"
          ] do
        """
        defmodule MyApp.Records do
          def create(module, schema_module, module_name, params) do
            #{statements}
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

    test "a struct modified within a changeset function" do
      for definition <- [
            """
            def changeset(user, attrs) do
                %{user | account_id: user.account_id || Ecto.UUID.generate()}
                |> cast(attrs, [:name])
              end
            """,
            """
            defp registration_changeset(user, attrs) when is_map(attrs) do
                user = Map.put(user, :account_id, user.account_id || Ecto.UUID.generate())
                changeset(user, attrs)
              end
            """
          ] do
        """
        defmodule MyApp.Accounts.User do
          import Ecto.Changeset

          #{definition}
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> refute_issues()
      end
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

    test "a changeset passed to Phoenix.Component.to_form" do
      for call <- [
            ~s'%{user | password: "hunter1"} |> User.changeset(%{}) |> Phoenix.Component.to_form()',
            ~s[to_form(User.changeset(%{user | password: "hunter1"}, %{}), as: "user")],
            ~s[%{user | password: "hunter1"} |> User.changeset(params) |> Phoenix.Component.to_form()],
            ~s[%{user | password: "hunter1"} |> User.changeset(params) |> to_form(as: "user")],
            ~s[to_form(User.changeset(%{user | password: "hunter1"}, params), as: "user")],
            ~s[Component.to_form(User.changeset(Map.put(user, :password, "hunter1"), params))],
            ~s[user = %{user | password: "hunter1"}\nuser |> User.changeset(params) |> to_form()]
          ] do
        """
        defmodule MyAppWeb.UserLive.FormComponent do
          def build_form(user, params) do
            #{call}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> refute_issues()
      end
    end

    test "a changeset variable only passed to to_form" do
      for statements <- [
            """
            changeset = Contact.changeset(%{contact | account_id: account_id}, %{})
            assign(socket, :fact_card_form, to_form(changeset, as: "contact"))
            """,
            """
            changeset = contact |> Map.put(:account_id, account_id) |> Contact.changeset(params)
            socket = assign(socket, :form, to_form(changeset))
            {:noreply, socket}
            """,
            """
            contact = %{contact | account_id: account_id}
            changeset = Contact.changeset(contact, params)
            {:noreply, assign(socket, form: to_form(changeset), other_form: to_form(changeset, as: "other"))}
            """,
            """
            changeset = Contact.changeset(%{contact | account_id: account_id}, params)
            changeset = %{changeset | action: :validate}
            {:noreply, assign(socket, form: to_form(changeset))}
            """,
            """
            changeset =
              contact
              |> Map.put(:account_id, account_id)
              |> Contact.changeset(params)
              |> Map.put(:action, :validate)

            {:noreply, assign(socket, form: to_form(changeset))}
            """
          ] do
        """
        defmodule MyAppWeb.ContactLive.FormComponent do
          def handle_event("validate", %{"contact" => params}, socket) do
            #{statements}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> refute_issues()
      end
    end

    test "a changeset passed to Ecto.Changeset.apply_changes" do
      for call <- [
            "%{user | account_id: account_id} |> User.changeset(params) |> Ecto.Changeset.apply_changes()",
            "Ecto.Changeset.apply_changes(User.changeset(%{user | account_id: account_id}, params))",
            "user |> Map.put(:account_id, account_id) |> User.changeset(params) |> Changeset.apply_changes()",
            "user |> Map.put(:account_id, account_id) |> cast(params, [:name]) |> apply_changes()",
            "user = %{user | account_id: account_id}\nuser |> User.changeset(params) |> apply_changes()"
          ] do
        """
        defmodule MyApp.Accounts do
          import Ecto.Changeset
          alias Ecto.Changeset

          def preview_move(user, account_id, params) do
            #{call}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> refute_issues()
      end
    end

    test "a changeset variable only passed to apply_changes" do
      for statements <- [
            """
            changeset = User.changeset(%{user | account_id: account_id}, params)
            preview = Ecto.Changeset.apply_changes(changeset)
            render(conn, :preview, user: preview)
            """,
            """
            user = Map.put(user, :account_id, account_id)
            changeset = User.changeset(user, params)
            render(conn, :preview, user: Ecto.Changeset.apply_changes(changeset))
            """
          ] do
        """
        defmodule MyAppWeb.UserController do
          def preview_move(conn, user, account_id, params) do
            #{statements}
          end
        end
        """
        |> to_source_file()
        |> run_check(AvoidModifyingStructBeforeChangeset)
        |> refute_issues()
      end
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
