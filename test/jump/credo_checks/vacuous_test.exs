defmodule Jump.CredoChecks.VacuousTestTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.VacuousTest

  describe "flags tests that don't actually test any production code" do
    test "flags cases with no function calls at all" do
      """
      test "awful assertion" do
        assert "foo" == "foo"
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(VacuousTest)
      |> assert_issue()
    end

    test "does not flag cases where setup is asserted against" do
      """
      test "setup assertion", %{val: val} do
        assert val == "foo"
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(VacuousTest)
      |> refute_issues()
    end

    test "flags setup-only tests when ignore_setup_only_tests? is false" do
      """
      test "assert on setup", %{user: user} do
        assert byte_size(user.id) > 0
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(VacuousTest, %{ignore_setup_only_tests?: false})
      |> assert_issue()
    end

    test "does not flag cases where aliased name matches a built-in" do
      """
      defmodule MyTest do
        use ExUnit.Case, async: true
        alias MyApp.Registry

        test "registry assertion" do
          assert [_] = Registry.lookup(MyApp.OtherModule, :foo)
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(VacuousTest)
      |> refute_issues()
    end

    test "does not flag cases where we're testing `use`" do
      """
      test "raises ArgumentError when prefix is missing" do
        assert_raise ArgumentError, ~r/Missing required :prefix option/, fn ->
          defmodule InvalidTracker do
            use Jump.Tracking
          end
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(VacuousTest)
      |> refute_issues()
    end

    test "does not flag metaprogrammed module calls" do
      """
      defmodule MyTest do
        use ExUnit.Case, async: true

        @module MyApp.MyModule

        test "implements fields/0" do
          fields = @module.fields()
          assert "my_field" in fields
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(VacuousTest)
      |> refute_issues()

      """
      test "implements fields/0" do
        module = MyApp.MyModule
        fields = module.fields()
        assert "my_field" in fields
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(VacuousTest)
      |> refute_issues()
    end

    [
      """
      assert byte_size("event: message") > 0
      assert byte_size(": keep-alive") > 0
      """,
      """
      json = Jason.encode!(%{"type" => "response.output_text.delta", "delta" => "Hello"})
      chunk = "data: " <> json
      assert byte_size(chunk) > 0
      """,
      """
      assert Jason.Encode.atom(:test) == "test"
      """,
      """
      assert nil == nil
      assert :meeting == :meeting
      """,
      """
      _state = %{session_id: "test", ping_ref: nil, timeout_ref: nil}
      timestamp = System.system_time(:second)
      assert timestamp > 1_000_000_000
      """,
      """
      _state = %{session_id: "test", ping_ref: nil, timeout_ref: nil}
      reason = "Test reason"
      assert String.length(reason) > 0
      """,
      """
      available_users = [%User{}]
      query = "test"

      filtered_users =
        Enum.filter(available_users, fn user ->
          String.contains?(String.downcase(user.full_name || ""), String.downcase(query))
        end)

      available_contacts = [context.contact]
      _contact_query = "john"

      filtered_contacts = Enum.filter(available_contacts, fn _contact -> false end)

      # Test delete signal functionality coverage (without CRM integration)
      signal_id = context.signal.id
      assert byte_size(signal_id) > 0
      """
    ]
    |> Enum.with_index(fn example_body, i ->
      @tag example_body: example_body
      test "flags real examples from code we shipped (example #{i + 1})", %{example_body: example_body} do
        """
        test "example test" do
          #{example_body}
        end
        """
        |> to_source_file("lib/my_module_test.exs")
        |> run_check(VacuousTest, %{library_modules: [Jason]})
        |> assert_issue()
      end
    end)
  end

  describe "does not flag" do
    test "non-test files" do
      """
      defmodule MyModule do
        def check(val) do
          some_function(val)
        end
      end
      """
      |> to_source_file("lib/my_module.ex")
      |> run_check(VacuousTest)
      |> refute_issues()
    end

    test "tests that call production code" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "calls production code" do
          result = some_function()
          assert result == "expected"
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(VacuousTest)
      |> refute_issues()
    end
  end
end
