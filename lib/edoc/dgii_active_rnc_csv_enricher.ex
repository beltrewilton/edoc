defmodule Edoc.DgiiActiveRncCsvEnricher do
  @moduledoc """
  Streams a CSV file, keeps rows whose `ESTADO` is `ACTIVO`, enriches each `RNC`
  with `Edoc.DgiiRncScraper.lookup/1`, and writes the original row plus fetched
  DGII data to a new CSV.

  The input file is processed line by line so large exports can be handled
  without loading the whole dataset into memory. Each active row is appended to
  the output file as soon as its lookup completes.

  The DGII export uses ISO-8859-1, so that is the default input encoding.
  """

  alias Edoc.DgiiRncScraper
  alias Edoc.DgiiRncScraper.Result

  @required_headers ["RNC", "ESTADO"]
  @dgii_headers [
    "DGII_LOOKUP_STATUS",
    "DGII_TAX_ID",
    "DGII_LEGAL_NAME",
    "DGII_ECONOMIC_ACTIVITY",
    "DGII_LOCAL_ADMINISTRATION",
    "DGII_ELECTRONIC_INVOICER",
    "DGII_LOOKUP_ERROR"
  ]
  @summary_keys [
    :input_path,
    :output_path,
    :total_rows,
    :active_rows,
    :written_rows,
    :successful_lookups,
    :failed_lookups,
    :skipped_rows
  ]

  @type lookup_result :: {:ok, Result.t()} | {:error, term()}
  @type summary :: %{
          input_path: Path.t(),
          output_path: Path.t(),
          total_rows: non_neg_integer(),
          active_rows: non_neg_integer(),
          written_rows: non_neg_integer(),
          successful_lookups: non_neg_integer(),
          failed_lookups: non_neg_integer(),
          skipped_rows: non_neg_integer()
        }

  @doc """
  Enriches the active rows from `input_path` and writes the result to `output_path`.

  Options:

    * `:output_path` - destination CSV path. Defaults to `<input>_active_enriched.csv`.
    * `:lookup_fun` - function used for DGII lookups. Defaults to `&Edoc.DgiiRncScraper.lookup/1`.
    * `:sleep_fun` - function used to sleep between requests. Defaults to `&Process.sleep/1`.
    * `:sleep_range` - inclusive range in milliseconds. Defaults to `700..2000`.
    * `:input_encoding` - source file encoding. Defaults to `:latin1`.
  Returns a summary with counts and the output path.
  """
  @spec enrich_active_rncs(Path.t(), keyword()) :: {:ok, summary()} | {:error, term()}
  def enrich_active_rncs(input_path, opts \\ []) when is_binary(input_path) do
    output_path = Keyword.get(opts, :output_path, default_output_path(input_path))
    lookup_fun = Keyword.get(opts, :lookup_fun, &DgiiRncScraper.lookup/1)
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    sleep_range = Keyword.get(opts, :sleep_range, 700..2000)
    input_encoding = Keyword.get(opts, :input_encoding, :latin1)

    with {:ok, total_active_rows} <- count_active_rows(input_path, input_encoding),
         :ok <- validate_sleep_range(sleep_range),
         :ok <- File.mkdir_p(Path.dirname(output_path)) do
      with_devices(input_path, output_path, fn input_device, output_device ->
        input_device
        |> IO.binstream(:line)
        |> Stream.with_index(1)
        |> Enum.reduce_while(
          initial_state(
            input_path,
            output_path,
            lookup_fun,
            sleep_fun,
            sleep_range,
            input_encoding,
            total_active_rows
          ),
          fn {raw_line, line_number}, state ->
            process_line(raw_line, line_number, output_device, state)
          end
        )
        |> finalize_result()
      end)
    end
  end

  defp with_devices(input_path, output_path, fun) do
    case File.open(input_path, [:read, :binary]) do
      {:ok, input_device} ->
        case File.open(output_path, [:write, :binary]) do
          {:ok, output_device} ->
            try do
              fun.(input_device, output_device)
            after
              File.close(input_device)
              File.close(output_device)
            end

          {:error, reason} ->
            File.close(input_device)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp initial_state(
         input_path,
         output_path,
         lookup_fun,
         sleep_fun,
         sleep_range,
         input_encoding,
         total_active_rows
       ) do
    %{
      input_path: input_path,
      output_path: output_path,
      lookup_fun: lookup_fun,
      sleep_fun: sleep_fun,
      sleep_range: sleep_range,
      input_encoding: input_encoding,
      total_active_rows: total_active_rows,
      headers: nil,
      header_count: 0,
      rnc_index: nil,
      estado_index: nil,
      total_rows: 0,
      active_rows: 0,
      written_rows: 0,
      successful_lookups: 0,
      failed_lookups: 0,
      skipped_rows: 0
    }
  end

  defp process_line(raw_line, line_number, output_device, state) do
    decoded_line = decode_line(raw_line, state.input_encoding)

    if String.trim(decoded_line) == "" do
      {:cont, state}
    else
      case parse_csv_line(decoded_line) do
        {:ok, fields} ->
          process_fields(fields, line_number, output_device, state)

        {:error, reason} ->
          {:halt, {:error, {:csv_parse_error, line_number, reason}}}
      end
    end
  end

  defp process_fields(fields, _line_number, output_device, %{headers: nil} = state) do
    headers = Enum.map(fields, &normalize_header/1)

    case validate_headers(headers) do
      :ok ->
        output_headers = headers ++ @dgii_headers
        :ok = write_csv_row(output_device, output_headers)

        {:cont,
         state
         |> Map.put(:headers, headers)
         |> Map.put(:header_count, length(headers))
         |> Map.put(:rnc_index, index_for!(headers, "RNC"))
         |> Map.put(:estado_index, index_for!(headers, "ESTADO"))}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp process_fields(fields, line_number, output_device, state) do
    if length(fields) != state.header_count do
      {:halt, {:error, {:unexpected_column_count, line_number, state.header_count, length(fields)}}}
    else
      total_rows = state.total_rows + 1

      if active_status?(Enum.at(fields, state.estado_index, "")) do
        sleep_ms = Enum.random(state.sleep_range)
        state.sleep_fun.(sleep_ms)

        rnc =
          fields
          |> Enum.at(state.rnc_index, "")
          |> String.trim()

        lookup_result = state.lookup_fun.(rnc)

        {lookup_columns, success?} = lookup_columns(lookup_result)
        :ok = write_csv_row(output_device, fields ++ lookup_columns)

        updated_state =
          state
          |> Map.put(:total_rows, total_rows)
          |> increment(:active_rows)
          |> increment(:written_rows)
          |> increment(if(success?, do: :successful_lookups, else: :failed_lookups))
          |> render_fetch_progress()

        {:cont, updated_state}
      else
        updated_state =
          state
          |> Map.put(:total_rows, total_rows)
          |> increment(:skipped_rows)

        {:cont, updated_state}
      end
    end
  end

  defp finalize_result({:error, _reason} = error), do: error

  defp finalize_result(state) do
    maybe_finish_progress(state)
    {:ok, Map.take(state, @summary_keys)}
  end

  defp count_active_rows(input_path, input_encoding) do
    case File.open(input_path, [:read, :binary]) do
      {:ok, input_device} ->
        try do
          input_device
          |> IO.binstream(:line)
          |> Stream.with_index(1)
          |> Enum.reduce_while(%{headers: nil, estado_index: nil, active_rows: 0}, fn {raw_line, line_number},
                                                                                      state ->
            decoded_line = decode_line(raw_line, input_encoding)

            if String.trim(decoded_line) == "" do
              {:cont, state}
            else
              case parse_csv_line(decoded_line) do
                {:ok, fields} ->
                  count_active_fields(fields, line_number, state)

                {:error, reason} ->
                  {:halt, {:error, {:csv_parse_error, line_number, reason}}}
              end
            end
          end)
          |> case do
            %{active_rows: active_rows} -> {:ok, active_rows}
            {:error, _reason} = error -> error
          end
        after
          File.close(input_device)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp count_active_fields(fields, _line_number, %{headers: nil} = state) do
    headers = Enum.map(fields, &normalize_header/1)

    case validate_headers(headers) do
      :ok ->
        {:cont, %{state | headers: headers, estado_index: index_for!(headers, "ESTADO")}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp count_active_fields(fields, line_number, state) do
    if length(fields) != length(state.headers) do
      {:halt, {:error, {:unexpected_column_count, line_number, length(state.headers), length(fields)}}}
    else
      active_rows =
        if active_status?(Enum.at(fields, state.estado_index, "")) do
          state.active_rows + 1
        else
          state.active_rows
        end

      {:cont, %{state | active_rows: active_rows}}
    end
  end

  defp validate_headers(headers) do
    missing_headers = Enum.reject(@required_headers, &(&1 in headers))

    case missing_headers do
      [] -> :ok
      _ -> {:error, {:missing_headers, missing_headers}}
    end
  end

  defp validate_sleep_range(first..last//step)
       when is_integer(first) and is_integer(last) and is_integer(step) and step > 0 and first >= 0 and
              last >= first do
    :ok
  end

  defp validate_sleep_range(_sleep_range), do: {:error, :invalid_sleep_range}

  defp default_output_path(input_path) do
    dir = Path.dirname(input_path)
    basename = Path.rootname(Path.basename(input_path))
    Path.join(dir, "#{basename}_active_enriched.csv")
  end

  defp decode_line(raw_line, encoding) do
    raw_line
    |> :unicode.characters_to_binary(encoding, :utf8)
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
  end

  defp normalize_header(header) do
    header
    |> String.trim()
    |> String.trim_leading("\uFEFF")
  end

  defp index_for!(headers, header_name) do
    Enum.find_index(headers, &(&1 == header_name))
  end

  defp active_status?(value) do
    value
    |> String.trim()
    |> String.upcase()
    |> Kernel.==("ACTIVO")
  end

  defp lookup_columns({:ok, %Result{} = result}) do
    {[
       "ok",
       result.tax_id || "",
       result.legal_name || "",
       result.economic_activity || "",
       result.local_administration || "",
       result.electronic_invoicer || "",
       ""
     ], true}
  end

  defp lookup_columns({:error, reason}) do
    {["error", "", "", "", "", "", inspect(reason)], false}
  end

  defp render_fetch_progress(%{active_rows: current, total_active_rows: total} = state)
       when total > 0 do
    percent = current / total * 100
    progress = "#{current}/#{total} - #{format_percent(percent)}%"

    if current == total do
      IO.write("\r#{progress}\n")
    else
      IO.write("\r#{progress}")
    end

    state
  end

  defp render_fetch_progress(state), do: state

  defp increment(state, key) do
    Map.update!(state, key, &(&1 + 1))
  end

  defp maybe_finish_progress(%{total_active_rows: 0}) do
    IO.puts("0/0 - 0.0%")
  end

  defp maybe_finish_progress(_state), do: :ok

  defp format_percent(percent) do
    :erlang.float_to_binary(percent, decimals: 1)
  end

  defp write_csv_row(device, fields) do
    encoded_row =
      fields
      |> Enum.map(&encode_csv_field/1)
      |> Enum.intersperse(",")
      |> IO.iodata_to_binary()

    IO.binwrite(device, [encoded_row, "\n"])
  end

  defp encode_csv_field(value) do
    escaped_value =
      value
      |> to_string()
      |> String.replace("\"", "\"\"")

    [?\", escaped_value, ?\"]
  end

  defp parse_csv_line(line) do
    do_parse_csv_line(line, [], [], false)
  end

  defp do_parse_csv_line(<<>>, current_field, fields, false) do
    {:ok, Enum.reverse([current_field_to_binary(current_field) | fields])}
  end

  defp do_parse_csv_line(<<>>, _current_field, _fields, true), do: {:error, :unterminated_quoted_field}

  defp do_parse_csv_line(<<?", ?", rest::binary>>, current_field, fields, true) do
    do_parse_csv_line(rest, [?" | current_field], fields, true)
  end

  defp do_parse_csv_line(<<?", rest::binary>>, current_field, fields, true) do
    do_parse_csv_line(rest, current_field, fields, false)
  end

  defp do_parse_csv_line(<<?", rest::binary>>, [], fields, false) do
    do_parse_csv_line(rest, [], fields, true)
  end

  defp do_parse_csv_line(<<?,, rest::binary>>, current_field, fields, false) do
    field = current_field_to_binary(current_field)
    do_parse_csv_line(rest, [], [field | fields], false)
  end

  defp do_parse_csv_line(<<char::utf8, rest::binary>>, current_field, fields, in_quotes?) do
    do_parse_csv_line(rest, [char | current_field], fields, in_quotes?)
  end

  defp current_field_to_binary(current_field) do
    current_field
    |> Enum.reverse()
    |> to_string()
  end
end
