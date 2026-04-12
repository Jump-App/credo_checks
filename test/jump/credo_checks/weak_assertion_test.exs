defmodule Jump.CredoChecks.WeakAssertionTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.WeakAssertion

  describe "assert is_*(...)" do
    for type_check <-
          ~w(is_list is_map is_binary is_atom is_boolean is_tuple is_struct is_exception)a do
      @tag type_check: type_check
      test "flags `assert #{type_check}(val)`", %{type_check: type_check} do
        """
        defmodule MyTest do
          use Jump.DataCase, async: true

          test "weak assertion" do
            result = some_function()
            assert #{type_check}(result)
          end
        end
        """
        |> to_source_file("lib/my_module_test.exs")
        |> run_check(WeakAssertion)
        |> assert_issue(fn issue ->
          assert issue.message =~ "assert #{type_check}(...)"
          assert issue.message =~ "weak assertion"
        end)
      end
    end
  end

  describe "refute is_*(...)" do
    for type_check <- ~w(is_list is_map is_binary is_nil)a do
      @tag type_check: type_check
      test "flags `refute #{type_check}(val)`", %{type_check: type_check} do
        """
        defmodule MyTest do
          use Jump.DataCase, async: true

          test "weak refutation" do
            result = some_function()
            refute #{type_check}(result)
          end
        end
        """
        |> to_source_file("lib/my_module_test.exs")
        |> run_check(WeakAssertion)
        |> assert_issue(fn issue ->
          assert issue.message =~ "refute #{type_check}(...)"
        end)
      end
    end
  end

  describe "refute val == nil" do
    test "flags `refute val == nil`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak refutation" do
          result = some_function()
          refute result == nil
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "refute val == nil"
      end)
    end

    test "flags `refute nil == val`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak refutation" do
          result = some_function()
          refute nil == result
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "refute val == nil"
      end)
    end
  end

  describe "assert val != nil" do
    test "flags `assert result != nil`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          result = some_function()
          assert result != nil
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "assert val != nil"
      end)
    end

    test "flags `assert nil != result`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          result = some_function()
          assert nil != result
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "assert val != nil"
      end)
    end
  end

  describe "assert not is_*(...)" do
    test "flags `assert not is_nil(val)`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          result = some_function()
          assert not is_nil(result)
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "assert not is_nil(...)"
      end)
    end

    test "flags `assert !is_nil(val)`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          result = some_function()
          assert !is_nil(result)
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "assert not is_nil(...)"
      end)
    end

    test "flags `assert not is_list(val)`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          result = some_function()
          assert not is_list(result)
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "assert not is_list(...)"
      end)
    end
  end

  describe "non-empty string checks" do
    test "flags `refute String.length(val) == 0`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          val = some_function()
          refute String.length(val) == 0
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "refute String.length(...) == 0"
        assert issue.message =~ "non-empty"
      end)
    end

    test "flags `refute byte_size(val) == 0`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          val = some_function()
          refute byte_size(val) == 0
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "refute byte_size(...) == 0"
        assert issue.message =~ "non-empty"
      end)
    end
  end

  describe "assert variable (bare truthiness check)" do
    test "flags `assert result`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          result = some_function()
          assert result
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "assert result"
        assert issue.message =~ "weak assertion"
        assert issue.message =~ "truthiness"
      end)
    end

    test "does not flag `assert bool?` (since ? indicates it's a boolean)" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          bool? = some_function()
          assert bool?
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end

    test "flags assert true/refute false" do
      for line <- ["assert true", "refute false"] do
        """
        defmodule MyTest do
          use Jump.DataCase, async: true

          test "weak assertion" do
            #{line}
          end
        end
        """
        |> to_source_file("lib/my_module_test.exs")
        |> run_check(WeakAssertion)
        |> assert_issue(fn issue ->
          assert issue.message =~ line
          assert issue.message =~ "weak assertion"
        end)
      end
    end
  end

  test "flags empty string prefix match" do
    for assertion <- [~s(assert "" <> _ = result), ~s(assert "" <> _ = foo.bar.baz)] do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          result = some_function()
          #{assertion}
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ ~s("" <> _)
        assert issue.message =~ "weak assertion"
      end)
    end
  end

  test ~s(does not flag `assert "prefix" <> _ = result`) do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "strong assertion" do
        result = some_function()
        assert "mtg_" <> _ = result
      end
    end
    """
    |> to_source_file("lib/my_module_test.exs")
    |> run_check(WeakAssertion)
    |> refute_issues()
  end

  describe "assert %{} = val (empty map match)" do
    test "flags `assert %{} = result`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          result = some_function()
          assert %{} = result
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "assert %{} = val"
        assert issue.message =~ "weak assertion"
      end)
    end

    test "flags `assert %{} = foo.bar.baz`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          assert %{} = foo.bar.baz
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "assert %{} = val"
      end)
    end

    test "does not flag `assert %{name: _} = result` (non-empty map match)" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "strong assertion" do
          result = some_function()
          assert %{name: "Tyler"} = result
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end
  end

  describe "assert <<_::binary>> = val (non-empty binary match)" do
    test "flags `assert <<_::binary>> = result`" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          result = some_function()
          assert <<_::binary>> = result
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "<<_::binary>>"
        assert issue.message =~ "weak match"
      end)
    end

    test "flags `assert %{key: <<_::binary>>} = result` (nested in map)" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "weak assertion" do
          result = some_function()
          assert %{refresh_token: <<_::binary>>} = result
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issue(fn issue ->
        assert issue.message =~ "<<_::binary>>"
        assert issue.message =~ "weak match"
      end)
    end

    test ~s(does not flag meaningful binary pattern like <<"mtg_", _::binary>>) do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "strong assertion" do
          result = some_function()
          assert <<"mtg_", _::binary>> = result
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end
  end

  describe "does not flag" do
    test "non-test files" do
      """
      defmodule MyModule do
        def check(val) do
          assert is_list(val)
        end
      end
      """
      |> to_source_file("lib/my_module.ex")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end

    test "strong assertions" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "strong assertions" do
          assert [%Product{}] = result
          assert %{name: "Tyler"} = result
          assert result == "expected"
          assert length(result) == 3
          refute result
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end

    test "assert with pattern match binding from function call" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "find element" do
          my_list = [1, 2, 3]
          assert my_element = Enum.find(my_list, fn val -> val == 2 end)
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end

    test "assert with bare function call" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "find element" do
          my_list = [1, 2, 3]
          assert Enum.find(my_list, fn val -> val == 2 end)
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end

    test "assert is_struct(val, Module) — asserting a specific struct type is specific enough" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "struct type assertion" do
          result = some_function()
          assert is_struct(result, DateTime)
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end

    test "assert is_nil(val) — positively asserting nil is specific enough" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "nil assertion" do
          error = some_function()
          assert is_nil(error)
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end

    test "weak assertions inside property tests" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true
        use ExUnitProperties

        property "handles any UTF8 string as query", %{user: user} do
          check all(query <- string(:utf8)) do
            results = FinancialHouseholds.search(user, query)
            assert is_list(results)
          end
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end

    test "multiple weak assertions inside property tests" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true
        use ExUnitProperties

        property "handles various inputs" do
          check all(val <- integer()) do
            result = some_function(val)
            assert is_map(result)
            refute is_nil(result)
            assert result
          end
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end

    test "is_* used outside assert/refute" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "type check in conditional" do
          result = some_function()
          if is_list(result), do: handle_list(result)
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> refute_issues()
    end
  end

  describe "multiple issues" do
    test "flags multiple weak assertions in the same file" do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "multiple weak assertions" do
          assert is_list(a)
          assert is_map(b)
          refute is_nil(c)
        end
      end
      """
      |> to_source_file("lib/my_module_test.exs")
      |> run_check(WeakAssertion)
      |> assert_issues(fn issues ->
        assert length(issues) == 3
      end)
    end
  end
end
