defmodule Jump.CredoChecks.DoctestIExExamples do
  @moduledoc """
  Ensures that modules with interactive Elixir examples in their docstrings
  have a corresponding test file that runs those doctests.
  """
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      derive_test_path: fn filename ->
        filename
        |> String.replace_leading("lib/", "test/")
        |> String.replace_trailing(".ex", "_test.exs")
      end
    ],
    explanations: [
      check: """
      Modules that contain interactive Elixir examples (`iex>`) in their
      `@doc` or `@moduledoc` attributes should have those examples exercised
      via `doctest` in a corresponding test file.

      For a file at `lib/jump/foo.ex` defining `Jump.Foo`, this check expects
      (by default) a test file at `test/jump/foo_test.exs` that contains:

          doctest Jump.Foo

      Without this, the examples are just decoration — they won't be
      compiled or verified, and can silently drift out of date.
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    if contains_doctestable_example?(source_file) do
      check_for_doctest(source_file, params)
    else
      []
    end
  end

  defp contains_doctestable_example?(%SourceFile{filename: filename} = source_file) do
    String.ends_with?(filename, ".ex") and SourceFile.source(source_file) =~ ~r/iex>/
  end

  defp check_for_doctest(source_file, params) do
    source_file
    |> SourceFile.ast()
    |> modules_with_iex_docs()
    |> case do
      [] ->
        []

      modules ->
        issue_meta = IssueMeta.for(source_file, params)
        derive_test_path = Params.get(params, :derive_test_path, __MODULE__)
        test_file = derive_test_path.(source_file.filename)
        check_test_file(test_file, modules, issue_meta)
    end
  end

  # Walk the AST looking for @doc or @moduledoc attributes whose string
  # contains "iex>", tracking which (possibly nested) module each one belongs to.
  # Returns `{module, line}` for each such module, where `line` is that of the
  # module's first doc attribute containing an example.
  defp modules_with_iex_docs(ast) do
    {_ast, {_module_stack, found}} = Macro.traverse(ast, {[], []}, &enter_node/2, &leave_node/2)

    found
    |> Enum.reverse()
    |> Enum.uniq_by(fn {module, _line} -> module end)
  end

  defp enter_node({:defmodule, _, [name, _block]} = node, {module_stack, found}) do
    {node, {[module_name(name, module_stack) | module_stack], found}}
  end

  # @doc "..." or @moduledoc "..."
  defp enter_node({:@, _, [{attr, meta, [value]}]} = node, {[module | _] = module_stack, found})
       when attr in [:doc, :moduledoc] and not is_nil(module) do
    if doc_contains_iex?(value) do
      {node, {module_stack, [{module, meta[:line]} | found]}}
    else
      {node, {module_stack, found}}
    end
  end

  defp enter_node(node, acc), do: {node, acc}

  defp leave_node({:defmodule, _, [_name, _block]} = node, {[_module | module_stack], found}) do
    {node, {module_stack, found}}
  end

  defp leave_node(node, acc), do: {node, acc}

  # Resolves the module a `defmodule` defines, mirroring how Elixir prefixes nested module names
  # with the enclosing module's name. Returns nil if the name can't be determined statically.
  defp module_name({:__aliases__, _, [{:__MODULE__, _, _} | rest]}, [parent | _]) when not is_nil(parent) do
    concat_module([parent | rest])
  end

  defp module_name({:__aliases__, _, [Elixir | _] = parts}, _module_stack), do: concat_module(parts)
  defp module_name({:__aliases__, _, parts}, []), do: concat_module(parts)
  defp module_name({:__aliases__, _, parts}, [parent | _]) when not is_nil(parent), do: concat_module([parent | parts])
  defp module_name(_name, _module_stack), do: nil

  defp concat_module(parts) do
    if Enum.all?(parts, &is_atom/1) do
      Module.concat(parts)
    end
  end

  defp doc_contains_iex?(value) when is_binary(value), do: String.contains?(value, "iex>")

  # Handle heredoc-style sigils like ~S, which appear as {:sigil_S, _, [string, _]}
  defp doc_contains_iex?({:sigil_S, _, [{:<<>>, _, [val]}, _]}) when is_binary(val), do: String.contains?(val, "iex>")

  defp doc_contains_iex?({:<<>>, _, parts}) do
    Enum.any?(parts, fn
      part when is_binary(part) -> String.contains?(part, "iex>")
      _ -> false
    end)
  end

  defp doc_contains_iex?(_), do: false

  defp check_test_file(test_file, modules, issue_meta) do
    if File.exists?(test_file) do
      doctested = doctested_modules([test_file])

      for {module, iex_line} <- modules, module not in doctested do
        module_name = inspect(module)

        format_issue(issue_meta,
          message: "Module `#{module_name}` has iex> examples but its test file is missing `doctest #{module_name}`.",
          trigger: "iex>",
          line_no: iex_line
        )
      end
    else
      for {module, iex_line} <- modules do
        format_issue(issue_meta,
          message: "Module `#{inspect(module)}` has iex> examples but no test file at `#{Path.basename(test_file)}`.",
          trigger: "iex>",
          line_no: iex_line
        )
      end
    end
  end

  # Returns the set of modules the given test files call `doctest` on.
  # TODO: Aliases are treated as file-wide rather than lexically scoped... that's an approximation, but maybe good enough.
  defp doctested_modules(test_files) do
    test_files
    |> Enum.flat_map(fn test_file ->
      with {:ok, source} <- File.read(test_file),
           {:ok, ast} <- Code.string_to_quoted(source) do
        {_ast, {_aliases, modules}} = Macro.prewalk(ast, {%{}, []}, &collect_doctest/2)
        modules
      else
        _ -> []
      end
    end)
    |> MapSet.new()
  end

  # alias Foo.Bar
  defp collect_doctest({:alias, _, [{:__aliases__, _, parts}]} = node, acc) do
    {node, put_alias(acc, List.last(parts), parts)}
  end

  # alias Foo.Bar, as: Baz
  defp collect_doctest({:alias, _, [{:__aliases__, _, parts}, opts]} = node, acc) when is_list(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, [as]} -> {node, put_alias(acc, as, parts)}
      _ -> {node, put_alias(acc, List.last(parts), parts)}
    end
  end

  # alias Foo.{Bar, Baz}
  defp collect_doctest({:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children} | _]} = node, acc) do
    acc =
      Enum.reduce(children, acc, fn
        {:__aliases__, _, parts}, acc -> put_alias(acc, List.last(parts), base ++ parts)
        _child, acc -> acc
      end)

    {node, acc}
  end

  # doctest Foo.Bar, with or without options
  defp collect_doctest({:doctest, _, [{:__aliases__, _, parts} | _]} = node, {aliases, modules}) do
    {node, {aliases, [expand_alias(parts, aliases) | modules]}}
  end

  defp collect_doctest(node, acc), do: {node, acc}

  defp put_alias({aliases, modules}, name, parts) do
    case expand_alias(parts, aliases) do
      nil -> {aliases, modules}
      module -> {Map.put(aliases, name, module), modules}
    end
  end

  # Resolves an alias reference like `Bar.Baz` to its full module, given the aliases
  # declared so far. Returns nil if the name can't be determined statically.
  defp expand_alias([head | tail] = parts, aliases) do
    case aliases do
      %{^head => module} -> concat_module([module | tail])
      _ -> concat_module(parts)
    end
  end
end
