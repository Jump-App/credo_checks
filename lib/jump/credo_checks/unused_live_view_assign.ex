defmodule Jump.CredoChecks.UnusedLiveViewAssign do
  @moduledoc false

  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      excluded: [],
      ignored_assigns: [:page_title],
      custom_assign_functions: []
    ],
    explanations: [
      check: """
      Checks for literal LiveView assigns that are written by a module but never
      read in that module's Elixir or HEEx source.

      This check is intentionally conservative. It is a source-level Credo check,
      not compiler-grade dataflow analysis, so it only tracks assign usage
      patterns that are obvious from the current module's Elixir source and
      related HEEx templates.

      Conventions and limitations:

      - Helper functions should read the assigns map through a variable named
        `assigns` or through `socket.assigns`. If you bind assigns to another
        name (like `%{assigns: opts} = socket`, followed by using
        `opts.my_attr`), the reads will not be recognized as being related
        to LiveView assigns.
      - Only literal writes via `assign`, `assign_new`, `assign_async`,
        `allow_upload`, `stream`, `stream_async`, and `update` are checked
        by default. Use `custom_assign_functions` to also track project-specific
        helpers that write assigns.
      - Writes to dynamic assign keys are not tracked. Examples include
        `assign(socket, field, value)`, `socket.assigns[field]`, and
        `Map.get(assigns, field)`.
      - `Phoenix.Component.assigns_to_attributes/2` is not treated as a read.
        Prefer explicit `attr` declarations and `attr :rest, :global` for
        forwarded attributes.
      - Some assigns are intended to be consumed by framework or layout code
        outside the current LiveView module. Use `ignored_assigns` to allowlist
        those keys.
      """,
      params: [
        ignored_assigns: """
        Assign names that should be ignored because they are consumed outside the
        current LiveView module, such as by layouts, hooks, parent components,
        child components, or framework behavior.

        `:page_title` is always included by default.

        Example:

            {Jump.CredoChecks.UnusedLiveViewAssign,
             ignored_assigns: [:active_path]}
        """,
        custom_assign_functions: """
        Additional functions that write LiveView assigns. Each entry is either
        `{function, arity}` for local/imported calls or `{module, function, arity}`
        for qualified calls.

        The assign key is expected to be the second argument (as it is in `Phoenix.Component.assign/3`).

        Example:

            {Jump.CredoChecks.UnusedLiveViewAssign,
             custom_assign_functions: [
               {:assign_current_user, 3},
               {MyApp.LiveHelpers, :assign_tenant, 3}
             ]}

        ...would match the following calls:

            socket
            |> MyApp.LiveHelpers.assign_tenant(:tenant, tenant)
            |> assign_current_user(:user, user)
        """
      ]
    ]

  alias Credo.Check.Params
  alias Credo.SourceFile

  @assign_write_functions ~w(assign assign_new assign_async allow_upload stream stream_async update)a
  @map_read_functions ~w(fetch fetch! get get_lazy has_key? take)a
  @doc false
  @impl Credo.Check
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    if String.ends_with?(filename, ".ex") and live_view_source?(source_file) and not exclude_path?(filename, params) do
      issue_meta = IssueMeta.for(source_file, params)
      ignored_assigns = ignored_assigns(params)
      custom_assign_functions = custom_assign_functions(params)

      source_file
      |> collect_usage(custom_assign_functions)
      |> issues_for_unused_writes(issue_meta, ignored_assigns)
    else
      []
    end
  end

  defp live_view_source?(source_file) do
    source_file
    |> SourceFile.ast()
    |> Macro.prewalk(false, fn
      {:use, _meta, [{:__aliases__, _, [:Phoenix, :LiveView]}]} = node, _acc ->
        {node, true}

      {:use, _meta, [{:__aliases__, _, [:Phoenix, :LiveComponent]}]} = node, _acc ->
        {node, true}

      {:use, _meta, [_module, type | _opts]} = node, _acc when type in [:live_view, :live_component] ->
        {node, true}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp collect_usage(%SourceFile{} = source_file, custom_assign_functions) do
    ast = SourceFile.ast(source_file)

    state =
      ast
      |> collect_ast_usage(%{writes: %{}, reads: MapSet.new()}, custom_assign_functions)
      |> collect_heex_sigils(ast)
      |> collect_heex_files(source_file.filename, ast)

    %{state | reads: MapSet.delete(state.reads, nil)}
  end

  defp collect_ast_usage(ast, state, custom_assign_functions) do
    ast
    |> Macro.prewalk(state, fn node, acc ->
      acc =
        acc
        |> collect_write(node, custom_assign_functions)
        |> collect_read(node)

      {node, acc}
    end)
    |> elem(1)
  end

  defp collect_write(state, {:|>, _pipe_meta, [_lhs, call]}, custom_assign_functions) do
    collect_call_write(state, call, :piped, custom_assign_functions)
  end

  defp collect_write(state, call, custom_assign_functions) do
    collect_call_write(state, call, :direct, custom_assign_functions)
  end

  defp collect_call_write(state, call, style, custom_assign_functions) do
    case call_parts(call) do
      {_module, function_name, meta, args} when function_name in @assign_write_functions ->
        Enum.reduce(write_keys(function_name, args, style), state, fn key, acc ->
          put_write(acc, key, meta[:line])
        end)

      {module, function_name, meta, args} ->
        if custom_assign_match?(custom_assign_functions, module, function_name, length(args), style) do
          Enum.reduce(custom_write_keys(args, style), state, fn key, acc ->
            put_write(acc, key, meta[:line])
          end)
        else
          state
        end

      _ ->
        state
    end
  end

  defp write_keys(:assign, [target, key, _value], :direct) do
    if assign_target?(target), do: literal_keys(key), else: []
  end

  defp write_keys(:assign, [target, attrs], :direct) do
    if assign_target?(target), do: literal_assign_attrs(attrs), else: []
  end

  defp write_keys(:assign, [key, _value], :piped), do: literal_keys(key)
  defp write_keys(:assign, [attrs], :piped), do: literal_assign_attrs(attrs)

  defp write_keys(:assign_new, [target, key, _value], :direct) do
    if assign_target?(target), do: literal_keys(key), else: []
  end

  defp write_keys(:assign_new, [key, _value], :piped), do: literal_keys(key)

  defp write_keys(:assign_async, [target, key_or_keys, _value], :direct) do
    if assign_target?(target), do: literal_keys(key_or_keys), else: []
  end

  defp write_keys(:assign_async, [target, key_or_keys, _value, _opts], :direct) do
    if assign_target?(target), do: literal_keys(key_or_keys), else: []
  end

  defp write_keys(:assign_async, [key_or_keys, _value], :piped), do: literal_keys(key_or_keys)
  defp write_keys(:assign_async, [key_or_keys, _value, _opts], :piped), do: literal_keys(key_or_keys)

  defp write_keys(:allow_upload, [target, _name, _opts], :direct) do
    if assign_target?(target), do: [:uploads], else: []
  end

  defp write_keys(:allow_upload, [_name, _opts], :piped), do: [:uploads]

  defp write_keys(:stream, [target, key, _items], :direct) do
    if assign_target?(target), do: literal_keys(key), else: []
  end

  defp write_keys(:stream, [target, key, _items, _opts], :direct) do
    if assign_target?(target), do: literal_keys(key), else: []
  end

  defp write_keys(:stream, [key, _items], :piped), do: literal_keys(key)
  defp write_keys(:stream, [key, _items, _opts], :piped), do: literal_keys(key)

  defp write_keys(:stream_async, [target, key, _value], :direct) do
    if assign_target?(target), do: literal_keys(key), else: []
  end

  defp write_keys(:stream_async, [target, key, _value, _opts], :direct) do
    if assign_target?(target), do: literal_keys(key), else: []
  end

  defp write_keys(:stream_async, [key, _value], :piped), do: literal_keys(key)
  defp write_keys(:stream_async, [key, _value, _opts], :piped), do: literal_keys(key)

  defp write_keys(:update, [target, key, _value], :direct) do
    if assign_target?(target), do: literal_keys(key), else: []
  end

  defp write_keys(:update, [key, _value], :piped), do: literal_keys(key)

  defp write_keys(_function_name, _args, _style), do: []

  defp custom_write_keys([_target, key | _rest], :direct), do: literal_keys(key)
  defp custom_write_keys([key | _rest], :piped), do: literal_keys(key)
  defp custom_write_keys(_args, _style), do: []

  defp custom_assign_match?(customs, module, function_name, arg_count, style) do
    expected_arity = if style == :piped, do: arg_count + 1, else: arg_count

    Enum.any?(customs, fn
      {^function_name, arity} when is_nil(module) and is_integer(arity) ->
        arity == expected_arity

      {^module, ^function_name, arity} when not is_nil(module) and is_integer(arity) ->
        arity == expected_arity

      _ ->
        false
    end)
  end

  defp assign_target?({name, _meta, context}) when name in [:assigns, :socket] and is_atom(context), do: true
  defp assign_target?({{:., _dot_meta, [_left, :assigns]}, _call_meta, args}), do: args in [[], nil]
  defp assign_target?(_target), do: false

  defp literal_assign_attrs(list) when is_list(list) do
    if Keyword.keyword?(list), do: Keyword.keys(list), else: []
  end

  defp literal_assign_attrs({:%{}, _meta, pairs}) do
    pairs
    |> Enum.map(fn
      {key, _value} when is_atom(key) -> key
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp literal_assign_attrs(_attrs), do: []

  defp put_write(state, key, line_no) when is_atom(key) and not is_nil(key) do
    write = %{key: key, key_name: Atom.to_string(key), line_no: line_no}
    %{state | writes: Map.update(state.writes, write.key_name, write, &earlier_write(&1, write))}
  end

  defp put_write(state, _key, _line_no), do: state

  defp earlier_write(%{line_no: nil}, candidate), do: candidate
  defp earlier_write(existing, %{line_no: nil}), do: existing
  defp earlier_write(existing, candidate), do: if(candidate.line_no < existing.line_no, do: candidate, else: existing)

  defp collect_read(state, node) do
    node
    |> read_keys()
    |> Enum.reduce(state, fn key, acc -> %{acc | reads: MapSet.put(acc.reads, Atom.to_string(key))} end)
  end

  defp read_keys({{:., _dot_meta, [{:assigns, _meta, nil}, key]}, _call_meta, args})
       when is_atom(key) and args in [[], nil] do
    [key]
  end

  defp read_keys({{:., _dot_meta, [{{:., _, [{_socket_name, _, _}, :assigns]}, _, args}, key]}, _call_meta, call_args})
       when is_atom(key) and args in [[], nil] and call_args in [[], nil] do
    [key]
  end

  defp read_keys({{:., _dot_meta, [{:__aliases__, _, [:Access]}, :get]}, _call_meta, [assigns_ast, key]})
       when is_atom(key) do
    if assigns_ast?(assigns_ast), do: [key], else: []
  end

  defp read_keys({{:., _dot_meta, [Access, :get]}, _call_meta, [assigns_ast, key]}) when is_atom(key) do
    if assigns_ast?(assigns_ast), do: [key], else: []
  end

  defp read_keys({{:., _dot_meta, [{:__aliases__, _, [:Map]}, function_name]}, _call_meta, [assigns_ast, key | _rest]})
       when function_name in @map_read_functions do
    if assigns_ast?(assigns_ast), do: literal_keys(key), else: []
  end

  defp read_keys(
         {:|>, _meta,
          [assigns_ast, {{:., _dot_meta, [{:__aliases__, _, [:Map]}, function_name]}, _call_meta, [key | _rest]}]}
       )
       when function_name in @map_read_functions do
    if assigns_ast?(assigns_ast), do: literal_keys(key), else: []
  end

  defp read_keys(
         {:|>, _meta, [assigns_ast, {{:., _dot_meta, [{:__aliases__, _, [:Access]}, :get]}, _call_meta, [key | _rest]}]}
       )
       when is_atom(key) do
    if assigns_ast?(assigns_ast), do: [key], else: []
  end

  defp read_keys({:|>, _meta, [assigns_ast, {{:., _dot_meta, [Access, :get]}, _call_meta, [key | _rest]}]})
       when is_atom(key) do
    if assigns_ast?(assigns_ast), do: [key], else: []
  end

  defp read_keys({:=, _meta, [map_pattern, assigns_ast]}) do
    if assigns_ast?(assigns_ast) or assigns_binding_ast?(assigns_ast), do: map_pattern_keys(map_pattern), else: []
  end

  defp read_keys({:%{}, _meta, pairs}) do
    Enum.flat_map(pairs, fn
      {:assigns, nested_pattern} -> map_pattern_keys(nested_pattern)
      _ -> []
    end)
  end

  defp read_keys(_call), do: []

  defp assigns_ast?({:assigns, _meta, nil}), do: true
  defp assigns_ast?({{:., _dot_meta, [{_socket_name, _, _}, :assigns]}, _call_meta, args}), do: args in [[], nil]
  defp assigns_ast?(_ast), do: false

  defp assigns_binding_ast?({name, _meta, nil}), do: name in [:assigns, :_assigns]
  defp assigns_binding_ast?(_ast), do: false

  defp literal_keys(key) when is_atom(key), do: [key]
  defp literal_keys(keys) when is_list(keys), do: Enum.filter(keys, &is_atom/1)
  defp literal_keys(_key), do: []

  defp map_pattern_keys({:%{}, _meta, pairs}) do
    pairs
    |> Enum.map(fn
      {key, _value} when is_atom(key) -> key
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp map_pattern_keys(_pattern), do: []

  defp call_parts({function_name, meta, args}) when is_atom(function_name) and is_list(args) do
    {nil, function_name, meta, args}
  end

  defp call_parts({{:., meta, [{:__aliases__, _, module_parts}, function_name]}, _call_meta, args})
       when is_atom(function_name) and is_list(args) and is_list(module_parts) do
    if Enum.all?(module_parts, &is_atom/1) do
      {Module.concat(module_parts), function_name, meta, args}
    else
      :error
    end
  end

  defp call_parts({{:., meta, [module, function_name]}, _call_meta, args})
       when is_atom(module) and is_atom(function_name) and is_list(args) do
    {module, function_name, meta, args}
  end

  defp call_parts(_node), do: :error

  defp collect_heex_sigils(state, ast) do
    ast
    |> Macro.prewalk(state, fn
      {:sigil_H, _meta, [{:<<>>, _string_meta, [heex]}, _modifiers]} = node, acc when is_binary(heex) ->
        {node, add_heex_reads(acc, heex)}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp collect_heex_files(state, filename, ast) do
    heex_files =
      filename
      |> sibling_heex_files()
      |> Kernel.++(embedded_heex_files(filename, ast))
      |> Enum.uniq()

    Enum.reduce(heex_files, state, fn file, acc ->
      if File.exists?(file), do: add_heex_reads(acc, File.read!(file)), else: acc
    end)
  end

  defp sibling_heex_files(filename) do
    heex = Path.rootname(filename, ".ex") <> ".html.heex"
    if File.exists?(heex), do: [heex], else: []
  end

  defp embedded_heex_files(filename, ast) do
    source_dir = Path.dirname(filename)

    ast
    |> Macro.prewalk([], fn
      {:embed_templates, _meta, args} = node, acc ->
        files =
          args
          |> Enum.flat_map(&template_pattern/1)
          |> Enum.flat_map(fn pattern -> Path.wildcard(Path.join(source_dir, pattern)) end)

        {node, files ++ acc}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp template_pattern(pattern) when is_binary(pattern), do: [pattern]
  defp template_pattern(_pattern), do: []

  defp add_heex_reads(state, heex) do
    reads =
      heex
      |> heex_assign_reads()
      |> MapSet.new()

    %{state | reads: MapSet.union(state.reads, reads)}
  end

  defp heex_assign_reads(heex) do
    at_reads =
      ~r/(?<![[:alnum:]_])@([a-zA-Z_][a-zA-Z0-9_?!]*)/
      |> Regex.scan(heex, capture: :all_but_first)
      |> List.flatten()

    stream_reads =
      ~r/(?<![[:alnum:]_])@streams\.([a-zA-Z_][a-zA-Z0-9_?!]*)/
      |> Regex.scan(heex, capture: :all_but_first)
      |> List.flatten()

    dot_reads =
      ~r/\b(?:assigns|socket\.assigns)\.([a-zA-Z_][a-zA-Z0-9_?!]*)/
      |> Regex.scan(heex, capture: :all_but_first)
      |> List.flatten()

    access_reads =
      ~r/\b(?:assigns|socket\.assigns)\[:([a-zA-Z_][a-zA-Z0-9_?!]*)\]/
      |> Regex.scan(heex, capture: :all_but_first)
      |> List.flatten()

    at_reads ++ stream_reads ++ dot_reads ++ access_reads
  end

  defp issues_for_unused_writes(%{writes: writes, reads: reads}, issue_meta, ignored_assigns) do
    writes
    |> Map.values()
    |> Enum.reject(fn %{key: key, key_name: key_name} ->
      MapSet.member?(reads, key_name) or MapSet.member?(ignored_assigns, key)
    end)
    |> Enum.sort_by(& &1.line_no)
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp issue_for(%{key: key, line_no: line_no}, issue_meta) do
    trigger = inspect(key)

    format_issue(
      issue_meta,
      message:
        "LiveView assign `#{trigger}` is assigned in this module but is never read in this module's Elixir or HEEx source.",
      trigger: trigger,
      line_no: line_no
    )
  end

  defp exclude_path?(filename, params) do
    params
    |> Params.get(:excluded, __MODULE__)
    |> Enum.any?(&excluded_match?(&1, filename))
  end

  defp excluded_match?(%Regex{} = regex, filename), do: Regex.match?(regex, filename)
  defp excluded_match?(path, filename) when is_binary(path), do: filename == path or String.contains?(filename, path)
  defp excluded_match?(_path, _filename), do: false

  defp ignored_assigns(params) do
    params
    |> Params.get(:ignored_assigns, __MODULE__)
    |> MapSet.new()
    |> MapSet.put(:page_title)
  end

  defp custom_assign_functions(params) do
    params
    |> Params.get(:custom_assign_functions, __MODULE__)
    |> List.wrap()
  end
end
