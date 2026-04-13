defmodule Jump.CredoChecks.LiveViewFormCanBeRehydrated do
  @moduledoc """
  Ensures that all forms with `phx-submit` have both an `id` attribute and a `phx-change` attribute specified.

  This is critical for form rehydration, since LiveView can't maintain form state across
  deploys or reconnects without an ID and phx-change, leading to the form being totally reset.
  Forms without `phx-submit` are not LiveView forms and don't need these attributes.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      excluded: []
    ],
    explanations: [
      check: """
      Ensures that all forms with `phx-submit` have both an `id` and `phx-change` attribute specified.

      This is critical for form rehydration, since LiveView can't maintain form state across
      deploys or reconnects without an ID and phx-change, leading to the form being totally reset.
      Forms without `phx-submit` are not LiveView forms and don't need these attributes.

      ✅ Good:

          <.form id="user-form" phx-submit="save" phx-change="validate">`

      ❌ Bad (missing ID and phx-change):

          <.form phx-submit="save">
      """
    ]

  alias Credo.Check.Params

  @doc false
  @impl Credo.Check
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    if String.ends_with?(filename, ".ex") and not exclude_path?(filename, params) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
      |> Enum.uniq()
    else
      []
    end
  end

  # Check the ~H sigil source directly for forms without IDs
  defp traverse({:sigil_H, _meta, [{:<<>>, meta, [heex]}, []]} = node, issues, parent_issue_meta)
       when is_binary(heex) do
    source_file = Credo.IssueMeta.source_file(parent_issue_meta)
    line = meta[:line]
    issue_meta = Credo.IssueMeta.for(source_file, line: line)

    # Check the raw HEEX string for forms without IDs
    new_issues = check_heex_string_for_forms(heex, issue_meta, meta[:indentation], line)
    {node, issues ++ new_issues}
  end

  # Check embedded templates
  defp traverse({:embed_templates, _meta, template_patterns} = node, issues, issue_meta)
       when is_list(template_patterns) do
    source_file = Credo.IssueMeta.source_file(issue_meta)
    source_dir = Path.dirname(source_file.filename)

    # Find all .heex files in the templates directory
    new_issues =
      template_patterns
      |> Enum.flat_map(fn template_pattern ->
        source_dir
        |> Path.join(template_pattern)
        |> Path.wildcard()
        |> Enum.reject(&exclude_path?(&1, issue_meta))
        |> Enum.flat_map(fn heex_file ->
          check_heex_file(heex_file, issue_meta)
        end)
      end)
      |> Enum.uniq()

    {node, issues ++ new_issues}
  end

  defp traverse(node, issues, _issue_meta), do: {node, issues}

  # Check a HEEX string for forms without IDs
  defp check_heex_string_for_forms(heex_string, issue_meta, indentation, base_line) do
    # First, find all form tags and check if they have IDs (handling multiline tags)
    find_forms_without_ids(heex_string, base_line + 1, indentation, issue_meta)
  end

  # Find form tags and check if they have IDs, handling multiline tags
  defp find_forms_without_ids(heex_string, base_line, indentation, issue_meta) do
    # Define form patterns to check (in order of specificity)
    form_patterns = [
      {"<PetalComponents.Form.form", ~r/<PetalComponents\.Form\.form\b/i,
       "Form component <PetalComponents.Form.form> is missing 'id' attribute."},
      {"<Form.form", ~r/<Form\.form\b/i, "Form component <Form.form> is missing 'id' attribute."},
      {"<.form", ~r/<\.form\b/i, "Form component <.form> is missing 'id' attribute."},
      {"<form", ~r/<form\b/i, "Raw HTML <form> tag is missing 'id' attribute."}
    ]

    lines = heex_string |> String.split("\n") |> Enum.with_index(base_line)

    # Find all issues across all patterns, then deduplicate by line number
    # (keeping only the most specific pattern per line)
    form_patterns
    |> Enum.flat_map(fn {trigger, pattern, message} ->
      find_pattern_matches(lines, pattern, trigger, message, indentation, issue_meta)
    end)
    |> deduplicate_issues_by_line()
  end

  # Deduplicate issues by line number, keeping only the most specific pattern
  # (first pattern in the list, since they're ordered by specificity)
  defp deduplicate_issues_by_line(issues) do
    issues
    |> Enum.group_by(fn issue -> issue.line_no end)
    |> Enum.map(fn {_line_no, line_issues} -> List.first(line_issues) end)
    |> Enum.sort_by(fn issue -> issue.line_no end)
  end

  # Find all matches of a pattern and check if the tag has required attributes
  defp find_pattern_matches(lines, pattern, trigger, message, indentation, issue_meta) do
    lines
    |> Enum.reduce({[], nil}, fn {line, line_no}, {issues, current_tag} ->
      cond do
        # If we're tracking a tag, check if this line closes it or has required attributes
        current_tag != nil ->
          {tag_line, tag_line_no, tag_trigger, tag_message, has_phx_submit, has_id, has_phx_validate} =
            current_tag

          # Check for required attributes on this line
          has_phx_submit_on_line = has_phx_submit or Regex.match?(~r/\bphx-submit\s*=/i, line)
          has_id_on_line = has_id or Regex.match?(~r/\bid\s*=/i, line)
          has_phx_validate_on_line = has_phx_validate or Regex.match?(~r/\bphx-change\s*=/i, line)

          # Tag closes on this line
          if String.contains?(line, ">") do
            # Only report if tag has phx-submit but missing id or phx-change
            new_issues =
              if has_phx_submit_on_line do
                missing_attrs = []
                missing_attrs = if has_id_on_line, do: missing_attrs, else: ["id" | missing_attrs]

                missing_attrs =
                  if has_phx_validate_on_line, do: missing_attrs, else: ["phx-change" | missing_attrs]

                if Enum.empty?(missing_attrs) do
                  []
                else
                  attr_list = Enum.join(Enum.reverse(missing_attrs), " and ")

                  custom_message =
                    String.replace(
                      tag_message,
                      "'id' attribute",
                      "'#{attr_list}' #{if length(missing_attrs) == 1, do: "attribute", else: "attributes"}"
                    )

                  issue =
                    create_form_issue(
                      tag_line,
                      indentation,
                      tag_line_no,
                      issue_meta,
                      tag_trigger,
                      custom_message
                    )

                  [issue]
                end
              else
                []
              end

            {new_issues ++ issues, nil}
          else
            # Tag continues on next line, update tracking
            {issues,
             {tag_line, tag_line_no, tag_trigger, tag_message, has_phx_submit_on_line, has_id_on_line,
              has_phx_validate_on_line}}
          end

        # Check if this line starts a new tag
        Regex.match?(pattern, line) ->
          # Check if the tag has required attributes on the same line
          has_phx_submit_on_line = Regex.match?(~r/\bphx-submit\s*=/i, line)
          has_id_on_line = Regex.match?(~r/\bid\s*=/i, line)
          has_phx_validate_on_line = Regex.match?(~r/\bphx-change\s*=/i, line)
          # Check if the tag closes on the same line
          closes_on_line = String.contains?(line, ">")

          # Tag closes on same line
          if closes_on_line do
            # Only create issue if has phx-submit but missing id or phx-change
            new_issues =
              if has_phx_submit_on_line do
                missing_attrs = []
                missing_attrs = if has_id_on_line, do: missing_attrs, else: ["id" | missing_attrs]

                missing_attrs =
                  if has_phx_validate_on_line, do: missing_attrs, else: ["phx-change" | missing_attrs]

                if Enum.empty?(missing_attrs) do
                  []
                else
                  attr_list = Enum.join(Enum.reverse(missing_attrs), " and ")

                  custom_message =
                    String.replace(
                      message,
                      "'id' attribute",
                      "'#{attr_list}' #{if length(missing_attrs) == 1, do: "attribute", else: "attributes"}"
                    )

                  issue =
                    create_form_issue(
                      line,
                      indentation,
                      line_no,
                      issue_meta,
                      trigger,
                      custom_message
                    )

                  [issue]
                end
              else
                []
              end

            {new_issues ++ issues, nil}
          else
            # Tag continues on next line, track it
            {issues,
             {line, line_no, trigger, message, has_phx_submit_on_line, has_id_on_line, has_phx_validate_on_line}}
          end

        # No match on this line
        true ->
          {issues, current_tag}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp create_form_issue(line, indentation, line_no, issue_meta, trigger, message) do
    # Find the position of the form opening
    [before | _after] = String.split(line, trigger)

    format_issue(issue_meta,
      message: message,
      trigger: trigger,
      line_no: line_no,
      column: String.length(before) + (indentation || 0) + 1
    )
  end

  # Check a .heex file for forms without IDs
  # sobelow_skip ["Traversal.FileModule"]
  defp check_heex_file(heex_file, parent_issue_meta) do
    content = File.read!(heex_file)
    params = IssueMeta.params(parent_issue_meta)
    issue_category = Params.category(params, __MODULE__)
    exit_status_or_category = Params.exit_status(params, __MODULE__) || issue_category

    find_forms_without_ids_in_heex_file(
      content,
      heex_file,
      params,
      issue_category,
      exit_status_or_category
    )
  end

  # Find form tags in .heex files and check if they have IDs
  defp find_forms_without_ids_in_heex_file(content, heex_file, params, issue_category, exit_status_or_category) do
    # Define form patterns to check (in order of specificity)
    form_patterns = [
      {"<PetalComponents.Form.form", ~r/<PetalComponents\.Form\.form\b/i,
       "Form component <PetalComponents.Form.form> found without an 'id' attribute."},
      {"<Form.form", ~r/<Form\.form\b/i, "Form component <Form.form> found without an 'id' attribute."},
      {"<.form", ~r/<\.form\b/i, "Form component <.form> found without an 'id' attribute."},
      {"<form", ~r/<form\b/i, "Raw HTML <form> tag found without an 'id' attribute."}
    ]

    lines = content |> String.split("\n") |> Enum.with_index(1)

    # Find all issues across all patterns, then deduplicate by line number
    # (keeping only the most specific pattern per line)
    form_patterns
    |> Enum.flat_map(fn {trigger, pattern, message} ->
      find_pattern_matches_in_heex_file(
        lines,
        pattern,
        trigger,
        message,
        heex_file,
        params,
        issue_category,
        exit_status_or_category
      )
    end)
    |> deduplicate_issues_by_line()
  end

  # Find all matches of a pattern in .heex files and check if the tag has required attributes
  defp find_pattern_matches_in_heex_file(
         lines,
         pattern,
         trigger,
         message,
         heex_file,
         params,
         issue_category,
         exit_status_or_category
       ) do
    lines
    |> Enum.reduce({[], nil}, fn {line, line_no}, {issues, current_tag} ->
      cond do
        # If we're tracking a tag, check if this line closes it or has required attributes
        current_tag != nil ->
          {tag_line, tag_line_no, tag_trigger, tag_message, has_phx_submit, has_id, has_phx_validate} =
            current_tag

          # Check for required attributes on this line
          has_phx_submit_on_line = has_phx_submit or Regex.match?(~r/\bphx-submit\s*=/i, line)
          has_id_on_line = has_id or Regex.match?(~r/\bid\s*=/i, line)
          has_phx_validate_on_line = has_phx_validate or Regex.match?(~r/\bphx-change\s*=/i, line)

          # Tag closes on this line
          if String.contains?(line, ">") do
            # Only report if tag has phx-submit but missing id or phx-change
            new_issues =
              if has_phx_submit_on_line do
                missing_attrs = []
                missing_attrs = if has_id_on_line, do: missing_attrs, else: ["id" | missing_attrs]

                missing_attrs =
                  if has_phx_validate_on_line, do: missing_attrs, else: ["phx-change" | missing_attrs]

                if Enum.empty?(missing_attrs) do
                  []
                else
                  attr_list = Enum.join(Enum.reverse(missing_attrs), " and ")

                  custom_message =
                    String.replace(
                      tag_message,
                      "'id' attribute",
                      "'#{attr_list}' #{if length(missing_attrs) == 1, do: "attribute", else: "attributes"}"
                    )

                  issue =
                    create_heex_file_issue(
                      tag_line,
                      tag_line_no,
                      heex_file,
                      tag_trigger,
                      custom_message,
                      params,
                      issue_category,
                      exit_status_or_category
                    )

                  [issue]
                end
              else
                []
              end

            {new_issues ++ issues, nil}
          else
            # Tag continues on next line, update tracking
            {issues,
             {tag_line, tag_line_no, tag_trigger, tag_message, has_phx_submit_on_line, has_id_on_line,
              has_phx_validate_on_line}}
          end

        # Check if this line starts a new tag
        Regex.match?(pattern, line) ->
          # Check if the tag has required attributes on the same line
          has_phx_submit_on_line = Regex.match?(~r/\bphx-submit\s*=/i, line)
          has_id_on_line = Regex.match?(~r/\bid\s*=/i, line)
          has_phx_validate_on_line = Regex.match?(~r/\bphx-change\s*=/i, line)
          # Check if the tag closes on the same line
          closes_on_line = String.contains?(line, ">")

          # Tag closes on same line
          if closes_on_line do
            # Only create issue if has phx-submit but missing id or phx-change
            new_issues =
              if has_phx_submit_on_line do
                missing_attrs = []
                missing_attrs = if has_id_on_line, do: missing_attrs, else: ["id" | missing_attrs]

                missing_attrs =
                  if has_phx_validate_on_line, do: missing_attrs, else: ["phx-change" | missing_attrs]

                if Enum.empty?(missing_attrs) do
                  []
                else
                  attr_list = Enum.join(Enum.reverse(missing_attrs), " and ")

                  custom_message =
                    String.replace(
                      message,
                      "'id' attribute",
                      "'#{attr_list}' #{if length(missing_attrs) == 1, do: "attribute", else: "attributes"}"
                    )

                  issue =
                    create_heex_file_issue(
                      line,
                      line_no,
                      heex_file,
                      trigger,
                      custom_message,
                      params,
                      issue_category,
                      exit_status_or_category
                    )

                  [issue]
                end
              else
                []
              end

            {new_issues ++ issues, nil}
          else
            # Tag continues on next line, track it
            {issues,
             {line, line_no, trigger, message, has_phx_submit_on_line, has_id_on_line, has_phx_validate_on_line}}
          end

        # No match on this line
        true ->
          {issues, current_tag}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp create_heex_file_issue(
         line,
         line_no,
         heex_file,
         trigger,
         message,
         params,
         issue_category,
         exit_status_or_category
       ) do
    [before | _after] = String.split(line, trigger)

    %Issue{
      message: message,
      line_no: line_no,
      filename: heex_file,
      trigger: trigger,
      category: issue_category,
      check: __MODULE__,
      priority: Params.priority(params, __MODULE__),
      severity: Credo.Severity.default_value(),
      column: String.length(before) + 1,
      exit_status: Credo.Check.to_exit_status(exit_status_or_category)
    }
  end

  defp exclude_path?(path, issue_meta) when is_binary(path) and is_tuple(issue_meta) do
    params = Credo.IssueMeta.params(issue_meta)
    exclude_path?(path, params)
  end

  defp exclude_path?(filename, params) when is_binary(filename) and (is_list(params) or is_map(params)) do
    excluded_path_substrings = params |> Params.get(:excluded, __MODULE__) |> List.wrap()
    String.contains?(filename, excluded_path_substrings)
  end
end
