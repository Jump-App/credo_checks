defmodule Jump.CredoChecks.UndeclaredExternalResourceTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.UndeclaredExternalResource

  test "alerts when a module attribute reads a file without @external_resource" do
    """
    defmodule Foo do
      @prompt_path "priv/data/prompt.md"
      @prompt File.read!(@prompt_path)
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> assert_issue(fn issue ->
      assert issue.trigger == "@prompt"
      assert issue.line_no == 3
    end)
  end

  test "alerts when hard-coded strings don't match up" do
    """
    defmodule Foo do
      @prompt File.read!("priv/data/prompt.md")
      @external_resource "priv/data/not-the-same-prompt.md"
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> assert_issue(fn issue ->
      assert issue.trigger == "@prompt"
      assert issue.line_no == 3
    end)
  end

  test "alerts when external resources from module attributes don't match up" do
    """
    defmodule Foo do
      @path "priv/data/prompt.md"
      @prompt File.read!(@path)

      @path2 "priv/data/not-the-same-prompt.md"
      @external_resource @path2
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> assert_issue(fn issue ->
      assert issue.trigger == "@prompt"
      assert issue.line_no == 3
    end)
  end

  test "alerts when external resources from module attributes from function calls don't match up" do
    """
    defmodule Foo do
      @path Path.join("priv", "data/prompt.md")
      @prompt File.read!(@path)

      @path2 Path.join("priv", "data/not-the-same-prompt.md")
      @external_resource @path2
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> assert_issue(fn issue ->
      assert issue.trigger == "@prompt"
      assert issue.line_no == 3
    end)
  end

  test "alerts when file system access happens in a pipeline or captured function" do
    """
    defmodule Foo do
      @tools_dir Path.expand("../../../tools", __DIR__)
      @tool_subdirs @tools_dir
                    |> File.ls!()
                    |> Enum.filter(&(File.dir?(Path.join(@tools_dir, &1)) and &1 != "core"))
                    |> Enum.map(&(&1 |> Macro.camelize() |> String.to_atom()))
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> assert_issue(fn issue ->
      assert issue.trigger == "@tool_subdirs"
    end)
  end

  test "alerts on fully-qualified Elixir.File and Erlang :file calls" do
    for call <- [
          ~s{Elixir.File.read!("priv/data/prompt.md")},
          ~s{:file.read_file("priv/data/prompt.md")}
        ] do
      """
      defmodule Foo do
        @prompt #{call}
      end
      """
      |> to_source_file()
      |> run_check(UndeclaredExternalResource)
      |> assert_issue()
    end
  end

  test "alerts once per file-reading attribute" do
    """
    defmodule Foo do
      @prompt File.read!("priv/data/prompt.md")
      @schema File.read!("priv/data/schema.json")
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["@prompt", "@schema"]
    end)
  end

  test "alerts when there's a missing @external_resource attr" do
    """
    defmodule Foo do
      @prompt File.read!("priv/data/prompt.md") |> Jason.decode!()
      @schema File.read!("priv/data/schema.json")
      @external_resource "priv/data/prompt.md"
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> assert_issue(fn issue ->
      assert issue.trigger == "@schema"
    end)
  end

  test "alerts on a nested module that lacks its own @external_resource" do
    """
    defmodule Outer do
      @external_resource "priv/data/outer.md"
      @outer File.read!("priv/data/outer.md")

      defmodule Inner do
        @inner File.read!("priv/data/inner.md")
      end
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> assert_issue(fn issue ->
      assert issue.trigger == "@inner"
    end)
  end

  test "an @external_resource in a nested module does not cover the outer module" do
    """
    defmodule Outer do
      @outer File.read!("priv/data/outer.md")

      defmodule Inner do
        @external_resource "priv/data/inner.md"
        @inner File.read!("priv/data/inner.md")
      end
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> assert_issue(fn issue ->
      assert issue.trigger == "@outer"
    end)
  end

  test "does not alert when @external_resource is declared" do
    """
    defmodule Foo do
      @prompt_path "priv/data/prompt.md"
      @external_resource @prompt_path
      @prompt File.read!(@prompt_path)
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> refute_issues()
  end

  test "does not alert when multiple @external_resource attrs are declared" do
    """
    defmodule Foo do
      @prompt_path "priv/data/prompt.md"
      @external_resource @prompt_path
      @prompt File.read!(@prompt_path)

      @schema_path "priv/data/schema.json"
      @external_resource @schema_path
      @schema File.read!(@schema_path)

      @external_resource "priv/data/not-the-same-schema.json"
      @schema File.read!("priv/data/not-the-same-schema.json")
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> refute_issues()
  end

  test "does not alert when external resources from module attributes from function calls match up" do
    """
    defmodule Foo do
      @path Path.join("priv", "data/prompt.md")
      @prompt File.read!(@path)
      @external_resource @path
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> refute_issues()
  end

  test "does not alert when @external_resource is declared inside a comprehension" do
    """
    defmodule Foo do
      @tools_dir Path.expand("../../../tools", __DIR__)
      @tools_files File.ls!(@tools_dir)

      for file <- @tools_files do
        @external_resource file
      end

      @tool_subdirs @tools_files
                    |> Enum.filter(&(File.dir?(Path.join(@tools_dir, &1)) and &1 != "core"))
                    |> Enum.map(&(&1 |> Macro.camelize() |> String.to_atom()))
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> refute_issues()
  end

  test "does not alert on file system access inside function bodies" do
    """
    defmodule Foo do
      def read_prompt do
        File.read!("priv/data/prompt.md")
      end

      defp list_tools(dir) do
        dir |> File.ls!() |> Enum.sort()
      end
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> refute_issues()
  end

  test "does not alert on module attributes that don't touch the file system" do
    """
    defmodule Foo do
      @moduledoc "Call File.read!/1 at your peril"
      @prompt_path Path.expand("priv/data/prompt.md")
      @timeout :timer.seconds(5)
      @names Enum.map([:a, :b], &Atom.to_string/1)
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> refute_issues()
  end

  test "does not alert on modules named like File" do
    """
    defmodule Foo do
      @config MyApp.File.parse("priv/data/config.txt")
    end
    """
    |> to_source_file()
    |> run_check(UndeclaredExternalResource)
    |> refute_issues()
  end

  test "does not alert in .exs files, which mix compile does not track" do
    """
    defmodule FooTest do
      @fixture File.read!("test/fixtures/data.json")
    end
    """
    |> to_source_file("test/foo_test.exs")
    |> run_check(UndeclaredExternalResource)
    |> refute_issues()
  end
end
