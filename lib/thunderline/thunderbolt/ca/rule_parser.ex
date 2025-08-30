defmodule Thunderline.Thunderbolt.CA.RuleParser do
  @moduledoc "Parser for concise CA rule specification lines using NimbleParsec. Canonical module under Thunderbolt domain."
  import NimbleParsec

  defstruct born: [], survive: [], rate_hz: 30, seed: nil, zone: nil, rest: nil

  # Helpers
  digit = ascii_string([?0..?9], min: 1)
  ws = ignore(optional(ascii_string([?\s, ?\t], min: 1)))

  rule_seq = ascii_string([?0..?9], min: 1)

  born = ignore(ascii_char([?b, ?B])) |> concat(rule_seq) |> tag(:born)
  survive = ignore(ascii_char([?s, ?S])) |> concat(rule_seq) |> tag(:survive)

  rule_core = born |> ignore(string("/")) |> concat(survive) |> label("B#/S# rule sequence")

  int = ascii_string([?0..?9], min: 1) |> map({String, :to_integer, []})

  rate_kv =
    ignore(choice([string("rate"), string("RATE"), string("Rate")]))
    |> ignore(string("="))
    |> concat(int)
    |> optional(ignore(choice([string("Hz"), string("hz"), string("HZ")])))
    |> tag(:rate)

  seed_kv =
    ignore(choice([string("seed"), string("SEED"), string("Seed")]))
    |> ignore(string("="))
    |> ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_, ?-], min: 1)
    |> tag(:seed)

  zone_kv =
    ignore(choice([string("zone"), string("ZONE"), string("Zone")]))
    |> ignore(string("="))
    |> ascii_string([?a..?z, ?A..?Z, ?0..?9], min: 1)
    |> tag(:zone)

  assignment = choice([rate_kv, seed_kv, zone_kv])

  parser =
    ws
    |> concat(rule_core)
    |> repeat(ws |> concat(assignment))
    |> optional(ws)
    |> eos()

  defparsec :parse_line, parser

  @doc "High-level parse returning struct or {:error, reason}"
  def parse(str) when is_binary(str) do
    case parse_line(str) do
      {:ok, parts, _, _, _, _} ->
        struct = build(parts)
        emit_parse_event(str, struct)
        {:ok, struct}

      {:error, reason, rest, _, _, _} ->
        {:error, %{message: reason, rest: rest}}
    end
  end

  defp build(parts) do
    born_seq = parts |> Enum.find_value([], fn {:born, seq} -> digits(seq); _ -> nil end)
    survive_seq = parts |> Enum.find_value([], fn {:survive, seq} -> digits(seq); _ -> nil end)
    rate = parts |> Enum.find_value(nil, fn {:rate, v} -> v; _ -> nil end)
    seed = parts |> Enum.find_value(nil, fn {:seed, v} -> v; _ -> nil end)
    zone = parts |> Enum.find_value(nil, fn {:zone, v} -> v; _ -> nil end)

    %__MODULE__{born: born_seq, survive: survive_seq, rate_hz: rate || 30, seed: seed, zone: zone}
  end

  defp digits(seq) when is_binary(seq), do: seq |> String.graphemes() |> Enum.map(&String.to_integer/1)

  defp emit_parse_event(original, %__MODULE__{} = rule) do
    payload = %{
      born: rule.born,
      survive: rule.survive,
      rate_hz: rule.rate_hz,
      seed: rule.seed,
      zone: rule.zone,
      original: original
    }

    case Thunderline.Event.new(name: "evt.action.ca.rule_parsed", source: :bolt, payload: payload) do
      {:ok, ev} ->
        _ = Task.start(fn -> Thunderline.EventBus.emit(ev) end)
        :ok

      {:error, _} ->
        :error
    end
  rescue
    _ -> :ok
  end
end
