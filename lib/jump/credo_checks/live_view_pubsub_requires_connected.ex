defmodule Jump.CredoChecks.LiveViewPubSubRequiresConnected do
  @moduledoc """
  Flags `Phoenix.PubSub` calls in a LiveView `mount/3` that are not wrapped in `connected?(socket)`.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      custom_pubsub_functions: []
    ],
    explanations: [
      check: """
      LiveView `mount/3` runs twice: once for the disconnected static render and
      once when the WebSocket connects. `Phoenix.PubSub` subscriptions in the
      disconnected mount attach to a process that is about to die, so they should
      only run when the socket is connected.

          # ❌ Bad — subscribes during the disconnected mount *and* after the WebSocket connects
          def mount(_params, _session, socket) do
            PubSub.subscribe("my-topic")
            {:ok, socket}
          end

          # ✅ Good — only subscribes once the LiveView is connected
          def mount(_params, _session, socket) do
            if connected?(socket) do
              PubSub.subscribe("my-topic")
            end

            {:ok, socket}
          end
      """,
      params: [
        custom_pubsub_functions: """
        Additional functions that wrap `Phoenix.PubSub.subscribe/{2,3}`.
        Each entry is `{module, function}` for qualified calls, `{function, arity}`
        for local/imported calls, or `{module, function, arity}` to also constrain
        arity.

        Example:

            {Jump.CredoChecks.LiveViewPubSubRequiresConnected,
             custom_pubsub_functions: [
               {MyAppWeb.PubSub, :subscribe},
               {:subscribe_user_events, 1}
             ]}

        ...would match:

            MyAppWeb.PubSub.subscribe("topic")
            subscribe_user_events(socket)
        """
      ]
    ]

  alias Credo.Check.Params

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = Credo.SourceFile.ast(source_file)
    customs = params |> Params.get(:custom_pubsub_functions, __MODULE__) |> List.wrap()
    refs = collect_pubsub_refs(ast, customs)

    {_ast, issues} = Macro.prewalk(ast, [], &traverse_mount(&1, &2, refs, issue_meta))
    Enum.reverse(issues)
  end

  defp collect_pubsub_refs(ast, customs) do
    initial = %{aliases: %{}, imported_modules: MapSet.new(), customs: customs}

    {_ast, refs} =
      Macro.prewalk(ast, initial, fn
        {:alias, _, args} = node, acc ->
          {node, add_aliases(acc, args)}

        {:import, _, [{:__aliases__, _, parts} | _]} = node, acc ->
          {node, add_import(acc, parts)}

        node, acc ->
          {node, acc}
      end)

    refs
  end

  defp add_aliases(acc, [{:__aliases__, _, parts}]) when is_list(parts) do
    put_alias(acc, [List.last(parts)], parts)
  end

  defp add_aliases(acc, [{:__aliases__, _, parts}, opts]) when is_list(parts) and is_list(opts) do
    as_parts =
      case Keyword.get(opts, :as) do
        {:__aliases__, _, as} -> as
        _ -> [List.last(parts)]
      end

    put_alias(acc, as_parts, parts)
  end

  defp add_aliases(acc, [{{:., _, [{:__aliases__, _, prefix}, :{}]}, _, aliases}]) when is_list(prefix) do
    Enum.reduce(aliases, acc, fn
      {:__aliases__, _, nested}, acc when is_list(nested) -> put_alias(acc, nested, prefix ++ nested)
      _, acc -> acc
    end)
  end

  defp add_aliases(acc, _args), do: acc

  defp put_alias(acc, alias_parts, full_parts) do
    if Enum.all?(alias_parts, &is_atom/1) and Enum.all?(full_parts, &is_atom/1) do
      %{acc | aliases: Map.put(acc.aliases, alias_parts, Module.concat(full_parts))}
    else
      acc
    end
  end

  defp add_import(acc, parts) do
    if Enum.all?(parts, &is_atom/1) do
      %{acc | imported_modules: MapSet.put(acc.imported_modules, Module.concat(parts))}
    else
      acc
    end
  end

  defp traverse_mount({kind, _meta, [head, body]} = node, issues, refs, issue_meta) when kind in [:def, :defp] do
    if mount_3?(head) do
      mount_body = Keyword.get(List.wrap(body), :do)
      new_issues = find_unguarded_pubsub(mount_body, refs, issue_meta, _connected? = false)
      {node, new_issues ++ issues}
    else
      {node, issues}
    end
  end

  defp traverse_mount(node, issues, _refs, _issue_meta), do: {node, issues}

  defp mount_3?({:when, _, [head, _guard]}), do: mount_3?(head)
  defp mount_3?({:mount, _, args}) when is_list(args), do: length(args) == 3
  defp mount_3?(_), do: false

  defp find_unguarded_pubsub(nil, _refs, _issue_meta, _connected?), do: []

  defp find_unguarded_pubsub(ast, refs, issue_meta, connected?) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        walk_mount_body(node, issues, refs, issue_meta, connected?)
      end)

    issues
  end

  # `if`/`unless` with a connected? condition: walk branches ourselves so the
  # `else` is not treated as connected just because the `do` is.
  defp walk_mount_body({kind, _, [condition, blocks]}, issues, refs, issue_meta, connected?)
       when kind in [:if, :unless] and is_list(blocks) do
    polarity = connected_polarity(condition)
    {do_connected?, else_connected?} = branch_connected(kind, polarity, connected?)

    issues =
      issues ++
        find_unguarded_pubsub(Keyword.get(blocks, :do), refs, issue_meta, do_connected?) ++
        find_unguarded_pubsub(Keyword.get(blocks, :else), refs, issue_meta, else_connected?)

    {{:__block__, [], []}, issues}
  end

  defp walk_mount_body(node, issues, refs, issue_meta, false) do
    if pubsub_call?(node, refs) do
      {node, [issue_for(node, issue_meta) | issues]}
    else
      {node, issues}
    end
  end

  defp walk_mount_body(node, issues, _refs, _issue_meta, true) do
    {node, issues}
  end

  defp branch_connected(_kind, _polarity, true), do: {true, true}

  defp branch_connected(:if, :connected, false), do: {true, false}
  defp branch_connected(:if, :disconnected, false), do: {false, true}
  defp branch_connected(:if, :unknown, false), do: {false, false}

  defp branch_connected(:unless, :connected, false), do: {false, true}
  defp branch_connected(:unless, :disconnected, false), do: {true, false}
  defp branch_connected(:unless, :unknown, false), do: {false, false}

  defp connected_polarity(condition) do
    cond do
      connected_call?(condition) -> :connected
      negated_connected?(condition) -> :disconnected
      conjunct_connected?(condition) -> :connected
      true -> :unknown
    end
  end

  defp negated_connected?({:!, _, [inner]}), do: connected_call?(inner)
  defp negated_connected?({:not, _, [inner]}), do: connected_call?(inner)
  defp negated_connected?(_), do: false

  defp conjunct_connected?({op, _, [left, right]}) when op in [:&&, :and] do
    connected_call?(left) or connected_call?(right) or conjunct_connected?(left) or conjunct_connected?(right)
  end

  defp conjunct_connected?(_), do: false

  defp connected_call?({:connected?, _, args}) when is_list(args), do: true

  defp connected_call?({{:., _, [_mod, :connected?]}, _, args}) when is_list(args), do: true

  defp connected_call?(_), do: false

  defp pubsub_call?({{:., _, [mod, fun]}, _, args}, refs) when is_atom(fun) and is_list(args) do
    resolved = resolve_module(mod, refs)

    (resolved == Phoenix.PubSub and fun == :subscribe) or
      custom_qualified_call?(refs.customs, resolved, fun, length(args))
  end

  defp pubsub_call?({fun, _, args}, refs) when is_atom(fun) and is_list(args) do
    phoenix_pubsub_imported?(refs, fun) or custom_bare_call?(refs, fun, length(args))
  end

  defp pubsub_call?(_node, _refs), do: false

  defp phoenix_pubsub_imported?(%{imported_modules: imported}, fun) do
    fun == :subscribe and MapSet.member?(imported, Phoenix.PubSub)
  end

  defp custom_qualified_call?(customs, module, fun, arity) when is_atom(module) do
    Enum.any?(customs, fn
      {^module, ^fun} -> true
      {^module, ^fun, expected} when is_integer(expected) -> expected == arity
      _ -> false
    end)
  end

  defp custom_qualified_call?(_customs, _module, _fun, _arity), do: false

  defp custom_bare_call?(refs, fun, arity) do
    Enum.any?(refs.customs, fn
      {^fun, expected} when is_integer(expected) ->
        expected == arity

      {module, ^fun} when is_atom(module) ->
        MapSet.member?(refs.imported_modules, module)

      {module, ^fun, expected} when is_atom(module) and is_integer(expected) ->
        expected == arity and MapSet.member?(refs.imported_modules, module)

      _ ->
        false
    end)
  end

  defp resolve_module({:__aliases__, _, parts}, refs) when is_list(parts) do
    cond do
      not Enum.all?(parts, &is_atom/1) ->
        nil

      Map.has_key?(refs.aliases, parts) ->
        refs.aliases[parts]

      true ->
        case parts do
          [first | rest] when rest != [] ->
            case Map.get(refs.aliases, [first]) do
              nil -> Module.concat(parts)
              prefix -> Module.concat([prefix | rest])
            end

          _ ->
            Module.concat(parts)
        end
    end
  end

  defp resolve_module(_mod, _refs), do: nil

  defp issue_for(node, issue_meta) do
    {trigger, line_no} = trigger_and_line(node)

    format_issue(
      issue_meta,
      message:
        "Wrap Phoenix.PubSub calls from LiveView `mount/3` callback with `if connected?(socket)` " <>
          "so they only run on the connected (WebSocket) mount.",
      trigger: trigger,
      line_no: line_no
    )
  end

  defp trigger_and_line({{:., meta, [{:__aliases__, _, parts}, fun]}, call_meta, _args}) do
    {"#{Enum.join(parts, ".")}.#{fun}", call_meta[:line] || meta[:line]}
  end

  defp trigger_and_line({fun, meta, _args}) when is_atom(fun) do
    {"#{fun}", meta[:line]}
  end
end
