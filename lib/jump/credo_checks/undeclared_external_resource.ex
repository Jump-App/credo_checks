defmodule Jump.CredoChecks.UndeclaredExternalResource do
  @moduledoc """
  Ensures modules that read from the file system at compile time declare
  `@external_resource`, so they get recompiled when those files change.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      When a module attribute reads from the file system (via `File.read!/1`,
      `File.ls!/1`, etc.), the file's contents get baked into the compiled module.
      Without an `@external_resource` declaration, `mix compile` has no idea the
      module depends on that file, so editing the file will *not* trigger a
      recompile and the module will keep stale data until something else forces
      a rebuild.

          # ❌ Bad — editing prompt.md won't recompile this module
          defmodule Foo do
            @prompt_path "priv/data/prompt.md"
            @prompt File.read!(@prompt_path)
          end

          # ✅ Good
          defmodule Foo do
            @prompt_path "priv/data/prompt.md"
            @external_resource @prompt_path
            @prompt File.read!(@prompt_path)
          end

      When both the paths being read and the `@external_resource` values are
      hard-coded strings (written inline, held in a module attribute, or built
      by joining hard-coded strings with `Path.join`), this check also verifies
      that they match up.

      However, when either side is built dynamically (via variables, other
      function calls, etc.), the presence of any `@external_resource`
      declaration in the module satisfies the check.
      """
    ]

  alias Credo.IssueMeta
  alias Credo.SourceFile

  @doc false
  @impl Credo.Check
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    if String.ends_with?(filename, ".ex") do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.ast()
      |> module_bodies()
      |> Enum.flat_map(&issues_for_module_body(&1, issue_meta))
      |> Enum.sort_by(& &1.line_no)
    else
      []
    end
  end

  defp module_bodies(ast) do
    ast
    |> Macro.prewalk([], fn
      {:defmodule, _meta, [_alias, [do: body]]} = node, acc -> {node, [body | acc]}
      node, acc -> {node, acc}
    end)
    |> elem(1)
  end

  defp issues_for_module_body(body, issue_meta) do
    attrs = attribute_values(body)
    resources = external_resources(body)
    resolved_resources = Enum.map(resources, fn {value, _line} -> resolve(value, attrs) end)

    cond do
      resources == [] ->
        body
        |> file_dependent_attributes(attrs)
        |> Enum.map(fn {name, line, _paths} -> undeclared_issue(name, line, issue_meta) end)

      Enum.all?(resolved_resources, &match?({:literal, _}, &1)) ->
        declared_paths = Enum.map(resolved_resources, fn {:literal, path} -> path end)

        # When a mismatching @external_resource holds an inline string, point
        # at it; otherwise point at the attribute doing the reading.
        inline_resource_line =
          Enum.find_value(resources, fn {value, line} -> if is_binary(value), do: line end)

        body
        |> file_dependent_attributes(attrs)
        |> Enum.flat_map(fn {name, line, paths} ->
          case paths -- declared_paths do
            [] -> []
            uncovered -> [mismatch_issue(name, uncovered, inline_resource_line || line, issue_meta)]
          end
        end)

      true ->
        # At least one @external_resource is built dynamically, so we can't
        # tell which files it covers.
        []
    end
  end

  # Groups every module attribute assignment in the body by name, so that
  # `File.read!(@path)` and `@external_resource @path` can be resolved.
  defp attribute_values(body) do
    body
    |> walk_module([], fn
      {:@, _meta, [{name, _, [value]}]} = node, acc when is_atom(name) -> {node, [{name, value} | acc]}
      node, acc -> {node, acc}
    end)
    |> Enum.group_by(fn {name, _value} -> name end, fn {_name, value} -> value end)
  end

  # Resolves an expression to {:literal, path} when it's a hard-coded string,
  # a reference to a module attribute holding one, or a Path.join of such
  # values; returns :dynamic otherwise. Attributes reassigned to different
  # values are treated as dynamic.
  defp resolve(value, attrs), do: resolve(value, attrs, [])

  defp resolve(value, _attrs, _visited) when is_binary(value), do: {:literal, value}

  defp resolve({:@, _, [{name, _, context}]}, attrs, visited) when is_atom(name) and is_atom(context) do
    with false <- name in visited,
         [value] <- attrs |> Map.get(name, []) |> Enum.uniq() do
      resolve(value, attrs, [name | visited])
    else
      _ -> :dynamic
    end
  end

  defp resolve({{:., _, [{:__aliases__, _, aliases}, :join]}, _, [parts]}, attrs, visited)
       when aliases in [[:Path], [Elixir, :Path]] and is_list(parts) and parts != [] do
    join_if_literals(parts, attrs, visited)
  end

  defp resolve({{:., _, [{:__aliases__, _, aliases}, :join]}, _, [_left, _right] = parts}, attrs, visited)
       when aliases in [[:Path], [Elixir, :Path]] do
    join_if_literals(parts, attrs, visited)
  end

  defp resolve(_value, _attrs, _visited), do: :dynamic

  defp join_if_literals(parts, attrs, visited) do
    resolved = Enum.map(parts, &resolve(&1, attrs, visited))

    if Enum.all?(resolved, &match?({:literal, _}, &1)) do
      {:literal, resolved |> Enum.map(fn {:literal, part} -> part end) |> Path.join()}
    else
      :dynamic
    end
  end

  # Walks a module body without descending into nested defmodules, since each
  # module needs its own @external_resource declarations.
  defp walk_module(body, acc, fun) do
    body
    |> Macro.prewalk(acc, fn
      {:defmodule, _meta, _args}, acc -> {nil, acc}
      node, acc -> fun.(node, acc)
    end)
    |> elem(1)
  end

  defp external_resources(body) do
    body
    |> walk_module([], fn
      {:@, meta, [{:external_resource, _, [value]}]} = node, acc -> {node, [{value, meta[:line]} | acc]}
      node, acc -> {node, acc}
    end)
    |> Enum.reverse()
  end

  defp file_dependent_attributes(body, attrs) do
    body
    |> walk_module([], fn
      {:@, meta, [{name, _, [value]}]} = node, acc when is_atom(name) and name != :external_resource ->
        case file_call_paths(value, attrs) do
          :no_file_calls -> {node, acc}
          {:file_calls, paths} -> {node, [{name, meta[:line], paths} | acc]}
        end

      node, acc ->
        {node, acc}
    end)
    |> Enum.reverse()
  end

  # Returns :no_file_calls, or {:file_calls, paths} where paths are the
  # hard-coded string paths passed to the file system calls (dynamically built
  # paths are omitted, since we can't tell what they resolve to).
  defp file_call_paths(value, attrs) do
    value
    |> Macro.prewalk(:no_file_calls, fn
      {{:., _, [{:__aliases__, _, aliases}, _fun]}, _, args} = node, acc
      when aliases in [[:File], [Elixir, :File]] ->
        {node, add_file_call(acc, args, attrs)}

      {{:., _, [:file, _fun]}, _, args} = node, acc ->
        {node, add_file_call(acc, args, attrs)}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp add_file_call(acc, args, attrs) do
    paths =
      case acc do
        :no_file_calls -> []
        {:file_calls, paths} -> paths
      end

    with [path_arg | _] <- args,
         {:literal, path} <- resolve(path_arg, attrs) do
      {:file_calls, [path | paths]}
    else
      _ -> {:file_calls, paths}
    end
  end

  defp undeclared_issue(name, line_no, issue_meta) do
    format_issue(
      issue_meta,
      message:
        "Module attribute `@#{name}` reads from the file system at compile time, but the module " <>
          "never declares `@external_resource`, so editing the file won't trigger a recompile.",
      trigger: "@#{name}",
      line_no: line_no
    )
  end

  defp mismatch_issue(name, uncovered_paths, line_no, issue_meta) do
    paths = Enum.map_join(uncovered_paths, ", ", &"\"#{&1}\"")

    format_issue(
      issue_meta,
      message:
        "Module attribute `@#{name}` reads #{paths} at compile time, but no `@external_resource` " <>
          "declaration matches, so editing the file won't trigger a recompile.",
      trigger: "@#{name}",
      line_no: line_no
    )
  end
end
