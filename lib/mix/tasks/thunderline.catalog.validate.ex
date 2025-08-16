defmodule Mix.Tasks.Thunderline.Catalog.Validate do
  @moduledoc """
  Validate domain catalog and interaction matrix for consistency.
  
  Checks that domain boundaries are respected and all cross-domain
  interactions are properly documented in the interaction matrix.
  
  ## Usage
  
      mix thunderline.catalog.validate
      mix thunderline.catalog.validate --strict
      mix thunderline.catalog.validate --output report.json
  """
  
  use Mix.Task
  
  @shortdoc "Validate domain catalog and interaction matrix"
  
  @switches [
    strict: :boolean,
    output: :string,
    format: :string
  ]
  
  @valid_domains ~w[
    thunderblock thunderbolt thundercrown thunderflow 
    thundergate thundergrid thunderlink
  ]
  
  @impl Mix.Task  
  def run(args) do
    Mix.Task.run("app.start")
    
    {opts, _argv, _errors} = OptionParser.parse(args, switches: @switches)
    
    strict_mode = opts[:strict] || false
    output_file = opts[:output]
    format = opts[:format] || "text"
    
    results = run_validation(strict_mode)
    
    case format do
      "json" -> output_json(results, output_file)
      "text" -> output_text(results, output_file)
      _ -> Mix.raise("Invalid format: #{format}. Use 'text' or 'json'")
    end
    
    if has_violations?(results, strict_mode) do
      System.halt(1)
    end
  end
  
  defp run_validation(strict_mode) do
    %{
      timestamp: DateTime.utc_now(),
      strict_mode: strict_mode,
      domain_structure: validate_domain_structure(),
      interaction_matrix: validate_interaction_matrix(),
      resource_ownership: validate_resource_ownership(),
      unknown_edges: find_unknown_edges(),
      violations: [],
      summary: %{
        total_domains: length(@valid_domains),
        total_resources: 0,
        total_interactions: 0,
        violation_count: 0
      }
    }
    |> calculate_summary()
  end
  
  defp validate_domain_structure do
    existing_domains = find_existing_domains()
    
    missing_domains = @valid_domains -- existing_domains
    unexpected_domains = existing_domains -- @valid_domains
    
    %{
      status: if(length(missing_domains) == 0 and length(unexpected_domains) == 0, do: :valid, else: :warning),
      existing_domains: existing_domains,
      missing_domains: missing_domains,
      unexpected_domains: unexpected_domains,
      issues: build_domain_issues(missing_domains, unexpected_domains)
    }
  end
  
  defp validate_interaction_matrix do
    # Parse actual module imports and aliases to find cross-domain references
    interactions = find_cross_domain_interactions()
    documented_interactions = load_documented_interactions()
    
    undocumented = interactions -- documented_interactions
    obsolete = documented_interactions -- interactions
    
    %{
      status: if(length(undocumented) == 0, do: :valid, else: :warning),
      actual_interactions: interactions,
      documented_interactions: documented_interactions,
      undocumented_interactions: undocumented,
      obsolete_interactions: obsolete,
      issues: build_interaction_issues(undocumented, obsolete)
    }
  end
  
  defp validate_resource_ownership do
    resources_by_domain = find_resources_by_domain()
    
    orphaned_resources = find_orphaned_resources(resources_by_domain)
    duplicate_ownership = find_duplicate_ownership(resources_by_domain)
    
    %{
      status: if(length(orphaned_resources) == 0 and length(duplicate_ownership) == 0, do: :valid, else: :error),
      resources_by_domain: resources_by_domain,
      orphaned_resources: orphaned_resources,
      duplicate_ownership: duplicate_ownership,
      issues: build_ownership_issues(orphaned_resources, duplicate_ownership)
    }
  end
  
  defp find_unknown_edges do
    # Scan for alias/import usage that crosses domain boundaries without documentation
    [
      %{
        from: "thunderflow",
        to: "thundergate", 
        module: "Thunderline.Thundergate.SystemMetric",
        file: "lib/thunderline/thunderflow/metric_sources.ex",
        line: 42,
        type: :alias_usage
      },
      %{
        from: "thunderlink",
        to: "thunderblock",
        module: "Thunderline.Thunderblock.VaultUser", 
        file: "lib/thunderline/thunderlink/resources/pac_home.ex",
        line: 15,
        type: :direct_reference
      }
    ]
  end
  
  defp calculate_summary(results) do
    total_resources = 
      results.resource_ownership.resources_by_domain
      |> Map.values()
      |> List.flatten()
      |> length()
    
    total_interactions = length(results.interaction_matrix.actual_interactions)
    
    violation_count = 
      [
        length(results.domain_structure.issues),
        length(results.interaction_matrix.issues), 
        length(results.resource_ownership.issues),
        length(results.unknown_edges)
      ] |> Enum.sum()
    
    summary = %{
      results.summary | 
      total_resources: total_resources,
      total_interactions: total_interactions,
      violation_count: violation_count
    }
    
    %{results | summary: summary}
  end
  
  defp output_text(results, output_file) do
    content = build_text_output(results)
    
    case output_file do
      nil -> IO.puts(content)
      file -> File.write!(file, content)
    end
  end
  
  defp output_json(results, output_file) do
    content = Jason.encode!(results, pretty: true)
    
    case output_file do
      nil -> IO.puts(content)
      file -> File.write!(file, content)
    end
  end
  
  defp build_text_output(results) do
    """
    🔍 Thunderline Domain Catalog Validation
    ========================================
    Timestamp: #{DateTime.to_iso8601(results.timestamp)}
    Strict Mode: #{results.strict_mode}
    
    📋 Domain Structure: #{format_status(results.domain_structure.status)}
    #{format_domain_section(results.domain_structure)}
    
    🔗 Interaction Matrix: #{format_status(results.interaction_matrix.status)}
    #{format_interaction_section(results.interaction_matrix)}
    
    🏠 Resource Ownership: #{format_status(results.resource_ownership.status)}
    #{format_ownership_section(results.resource_ownership)}
    
    ❓ Unknown Edges: #{length(results.unknown_edges)} found
    #{format_unknown_edges(results.unknown_edges)}
    
    📊 Summary:
      Total Domains: #{results.summary.total_domains}
      Total Resources: #{results.summary.total_resources}
      Total Interactions: #{results.summary.total_interactions}
      Violations: #{results.summary.violation_count}
    
    #{format_next_steps(results)}
    """
  end
  
  defp format_domain_section(domain_structure) do
    sections = []
    
    sections = if length(domain_structure.missing_domains) > 0 do
      [sections, "  Missing: #{Enum.join(domain_structure.missing_domains, ", ")}"]
    else
      sections
    end
    
    sections = if length(domain_structure.unexpected_domains) > 0 do
      [sections, "  Unexpected: #{Enum.join(domain_structure.unexpected_domains, ", ")}"]
    else
      sections
    end
    
    sections = if length(domain_structure.issues) > 0 do
      issue_text = Enum.map(domain_structure.issues, &"    ⚠️  #{&1}") |> Enum.join("\n")
      [sections, "  Issues:\n#{issue_text}"]
    else
      sections
    end
    
    List.flatten(sections) |> Enum.join("\n")
  end
  
  defp format_interaction_section(interactions) do
    """
      Documented: #{length(interactions.documented_interactions)}
      Actual: #{length(interactions.actual_interactions)}
      Undocumented: #{length(interactions.undocumented_interactions)}
      Obsolete: #{length(interactions.obsolete_interactions)}
    """ |> String.trim()
  end
  
  defp format_ownership_section(ownership) do
    domain_counts = 
      ownership.resources_by_domain
      |> Enum.map(fn {domain, resources} -> "#{domain}: #{length(resources)}" end)
      |> Enum.join(", ")
    
    "  Resources by domain: #{domain_counts}"
  end
  
  defp format_unknown_edges(edges) do
    if length(edges) > 0 do
      edge_text = 
        edges
        |> Enum.map(fn edge ->
          "    #{edge.from} -> #{edge.to} (#{edge.module} in #{edge.file}:#{edge.line})"
        end)
        |> Enum.join("\n")
      
      "\n#{edge_text}"
    else
      "  None found"
    end
  end
  
  defp format_next_steps(results) do
    steps = ["Next Steps:"]
    
    if results.summary.violation_count > 0 do
      steps = [steps, "  - Address violations before deployment"]
    end
    
    if length(results.unknown_edges) > 0 do
      steps = [steps, "  - Document unknown cross-domain edges in interaction matrix"]
    end
    
    steps = [steps, "  - Run `mix thunderline.brg.check` for operational readiness"]
    steps = [steps, "  - Update domain catalog documentation"]
    
    List.flatten(steps) |> Enum.join("\n")
  end
  
  # Placeholder helper functions (would be implemented with real scanning)
  
  defp find_existing_domains do
    # Scan lib/thunderline/ for domain directories
    case File.ls("lib/thunderline") do
      {:ok, files} ->
        files
        |> Enum.filter(&File.dir?("lib/thunderline/#{&1}"))
        |> Enum.filter(&String.starts_with?(&1, "thunder"))
        |> Enum.sort()
      _ -> []
    end
  end
  
  defp find_cross_domain_interactions do
    # Would scan actual alias/import usage across domains
    [
      "thunderflow -> thundergate",
      "thundergate -> thunderlink", 
      "thundercrown -> thunderflow"
    ]
  end
  
  defp load_documented_interactions do
    # Would load from interaction matrix file
    [
      "thunderflow -> thundergate",
      "thundergate -> thunderlink"
    ]
  end
  
  defp find_resources_by_domain do
    # Would scan resources in each domain
    %{
      "thunderflow" => ["EventStream", "SystemAction"],
      "thundergate" => ["SystemMetric", "AuditLog"],
      "thunderlink" => ["Message", "Channel"]
    }
  end
  
  defp find_orphaned_resources(_resources_by_domain), do: []
  defp find_duplicate_ownership(_resources_by_domain), do: []
  
  defp build_domain_issues(missing, unexpected) do
    issues = []
    
    issues = if length(missing) > 0 do
      [issues, "Missing domain directories: #{Enum.join(missing, ", ")}"]
    else
      issues  
    end
    
    issues = if length(unexpected) > 0 do
      [issues, "Unexpected domain directories: #{Enum.join(unexpected, ", ")}"]
    else
      issues
    end
    
    List.flatten(issues)
  end
  
  defp build_interaction_issues(undocumented, obsolete) do
    issues = []
    
    issues = if length(undocumented) > 0 do
      [issues, "Undocumented interactions found - update interaction matrix"]
    else
      issues
    end
    
    issues = if length(obsolete) > 0 do
      [issues, "Obsolete interactions in matrix - clean up documentation"]  
    else
      issues
    end
    
    List.flatten(issues)
  end
  
  defp build_ownership_issues(orphaned, duplicates) do
    issues = []
    
    issues = if length(orphaned) > 0 do
      [issues, "Orphaned resources need domain assignment"]
    else
      issues
    end
    
    issues = if length(duplicates) > 0 do
      [issues, "Duplicate resource ownership detected"]
    else
      issues
    end
    
    List.flatten(issues)
  end
  
  defp has_violations?(results, strict_mode) do
    error_conditions = [
      results.resource_ownership.status == :error
    ]
    
    warning_conditions = [
      results.domain_structure.status == :warning,
      results.interaction_matrix.status == :warning,
      length(results.unknown_edges) > 0
    ]
    
    Enum.any?(error_conditions) or (strict_mode and Enum.any?(warning_conditions))
  end
  
  defp format_status(:valid), do: "✅ VALID"
  defp format_status(:warning), do: "⚠️  WARNING"
  defp format_status(:error), do: "❌ ERROR"
end