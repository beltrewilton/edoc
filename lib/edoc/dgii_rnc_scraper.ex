defmodule Edoc.DgiiRncScraper do
  @moduledoc """
  Scrapes the DGII RNC lookup page by reproducing its ASP.NET form submission.

  The flow is:

    1. Fetch the search page to capture hidden ASP.NET fields and session cookies.
    2. Submit the RNC/Cédula input together with the search button field.
    3. Return the result section as plain text with HTML tags removed.

  This module uses `Req` directly instead of a crawler because the target flow is
  a single form postback, not a multi-page crawl.
  """

  defmodule Result do
    @moduledoc "Normalized DGII RNC lookup result."

    @enforce_keys [:tax_id, :legal_name, :economic_activity, :local_administration]
    defstruct [:tax_id, :legal_name, :economic_activity, :local_administration]

    @type t :: %__MODULE__{
            tax_id: String.t(),
            legal_name: String.t(),
            economic_activity: String.t(),
            local_administration: String.t()
          }
  end

  @url "https://dgii.gov.do/app/WebApps/ConsultasWeb2/ConsultasWeb/consultas/rnc.aspx"
  @search_input_name "ctl00$cphMain$txtRNCCedula"
  @search_button_name "ctl00$cphMain$btnBuscarPorRNC"
  @result_heading "Resultados de la búsqueda"
  @field_labels %{
    tax_id: ["Cédula/RNC", "RNC/Cédula"],
    legal_name: ["Nombre/Razón Social"],
    economic_activity: ["Actividad Económica", "Actividad Economica"],
    local_administration: ["Administración Local", "Administracion Local"]
  }
  @not_found_messages [
    "No se encontraron datos",
    "No existen datos",
    "No hay datos para mostrar"
  ]
  @result_labels [
    "Cédula/RNC",
    "RNC/Cédula",
    "Nombre/Razón Social",
    "Nombre Comercial",
    "Categoría",
    "Régimen de pagos",
    "Estado",
    "Actividad Económica",
    "Actividad Economica",
    "Administración Local",
    "Administracion Local",
    "Facturador Electrónico",
    "Facturador Electronico"
  ]
  @result_selectors [
    "#cphMain_dvResultado",
    "#cphMain_tblResultado",
    "#cphMain_tblDatos",
    "#cphMain_upResultado",
    "#cphMain_pnlResultado",
    "#cphMain_divResultado"
  ]
  @default_user_agent [
    {"user-agent",
     "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
       "(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"},
    {"accept",
     "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"},
    {"accept-language", "es-DO,es;q=0.9,en;q=0.8"},
    {"cache-control", "no-cache"},
    {"pragma", "no-cache"}
  ]

  @type form_field :: {String.t(), String.t()}
  @type error ::
          :blank_identifier
          | :search_form_not_found
          | :result_not_found
          | {:http_error, pos_integer(), term()}
          | term()

  @doc """
  Looks up a DGII RNC/Cédula and returns a normalized result struct.

  Options:

    * `:url` - override the default DGII URL.
    * `:headers` - additional request headers.
    * `:req_options` - extra options passed to `Req`.
  """
  @spec lookup(String.t(), keyword()) :: {:ok, Result.t()} | {:error, error()}
  def lookup(identifier, opts \\ []) when is_binary(identifier) do
    with {:ok, normalized_identifier} <- normalize_identifier(identifier),
         {:ok, %Req.Response{} = response} <- fetch_search_page(opts),
         {:ok, payload} <- build_postback_payload(response.body, normalized_identifier),
         {:ok, html} <- submit_lookup(payload, response.headers, opts) do
      extract_result(html)
    end
  end

  @doc """
  Same as `lookup/2`, but raises on error.
  """
  @spec lookup!(String.t(), keyword()) :: Result.t()
  def lookup!(identifier, opts \\ []) when is_binary(identifier) do
    case lookup(identifier, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "DGII RNC lookup failed: #{inspect(reason)}"
    end
  end

  @doc """
  Builds the ASP.NET postback payload from the DGII lookup page HTML.
  """
  @spec build_postback_payload(String.t(), String.t()) ::
          {:ok, [form_field()]} | {:error, error()}
  def build_postback_payload(html, identifier)
      when is_binary(html) and is_binary(identifier) do
    with {:ok, document} <- Floki.parse_document(html),
         true <- search_form_present?(document) || {:error, :search_form_not_found} do
      hidden_fields =
        document
        |> Floki.find(~s(form input[type="hidden"][name]))
        |> Enum.map(fn input ->
          {attribute_value(input, "name"), attribute_value(input, "value")}
        end)

      payload =
        hidden_fields ++
          [
            {@search_input_name, identifier},
            {@search_button_name, button_value(document)}
          ]

      {:ok, payload}
    end
  end

  @doc """
  Extracts the DGII result section as plain text and strips all HTML tags.
  """
  @spec extract_result_text(String.t()) :: {:ok, String.t()} | {:error, error()}
  def extract_result_text(html) when is_binary(html) do
    with {:ok, document} <- Floki.parse_document(html) do
      text =
        document
        |> result_fragment_html()
        |> html_to_text()
        |> isolate_result_text()
        |> normalize_text()

      if text == "" do
        {:error, :result_not_found}
      else
        {:ok, text}
      end
    end
  end

  @doc """
  Extracts the DGII result section and parses it into a `Result` struct.
  """
  @spec extract_result(String.t()) :: {:ok, Result.t()} | {:error, error()}
  def extract_result(html) when is_binary(html) do
    with {:ok, text} <- extract_result_text(html) do
      text
      |> parse_result_text()
      |> case do
        {:ok, %Result{} = result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fetch_search_page(opts) do
    opts
    |> request_options()
    |> Keyword.put(:method, :get)
    |> Keyword.put(:url, request_url(opts))
    |> Req.request()
    |> normalize_http_result()
  end

  defp submit_lookup(payload, response_headers, opts) do
    headers =
      request_headers(opts) ++
        cookie_headers(response_headers) ++
        [{"content-type", "application/x-www-form-urlencoded"}, {"referer", request_url(opts)}]

    opts
    |> request_options()
    |> Keyword.put(:method, :post)
    |> Keyword.put(:url, request_url(opts))
    |> Keyword.put(:headers, headers)
    |> Keyword.put(:form, payload)
    |> Req.request()
    |> normalize_http_result()
    |> case do
      {:ok, %Req.Response{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_http_result({:ok, %Req.Response{status: status} = response})
       when status in 200..299 do
    {:ok, response}
  end

  defp normalize_http_result({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  defp normalize_http_result({:error, reason}), do: {:error, reason}

  defp request_options(opts) do
    req_options = Keyword.get(opts, :req_options, [])

    req_options
    |> Keyword.put_new(:redirect, true)
    |> maybe_put_finch()
  end

  defp maybe_put_finch(req_options) do
    if Process.whereis(Edoc.Finch) do
      Keyword.put_new(req_options, :finch, Edoc.Finch)
    else
      req_options
    end
  end

  defp request_url(opts), do: Keyword.get(opts, :url, @url)

  defp request_headers(opts) do
    @default_user_agent ++ Keyword.get(opts, :headers, [])
  end

  defp normalize_identifier(identifier) do
    trimmed_identifier = String.trim(identifier)
    digits_only = String.replace(trimmed_identifier, ~r/\D/u, "")

    cond do
      trimmed_identifier == "" ->
        {:error, :blank_identifier}

      String.length(digits_only) in [9, 11] ->
        {:ok, digits_only}

      true ->
        {:ok, trimmed_identifier}
    end
  end

  defp search_form_present?(document) do
    has_input? =
      document
      |> Floki.find(~s(form [name="#{@search_input_name}"]))
      |> Enum.any?()

    has_button? =
      document
      |> Floki.find(~s(form [name="#{@search_button_name}"]))
      |> Enum.any?()

    has_input? and has_button?
  end

  defp button_value(document) do
    document
    |> Floki.find(~s(form [name="#{@search_button_name}"]))
    |> List.first()
    |> case do
      nil -> "Buscar"
      node -> attribute_value(node, "value", "Buscar")
    end
  end

  defp attribute_value(node, attribute, default \\ "") do
    node
    |> Floki.attribute(attribute)
    |> List.first()
    |> case do
      nil -> default
      value -> value
    end
  end

  defp cookie_headers(response_headers) do
    cookies =
      response_headers
      |> Enum.filter(fn {key, _value} -> String.downcase(key) == "set-cookie" end)
      |> Enum.flat_map(fn {_key, value} ->
        value
        |> List.wrap()
        |> Enum.map(fn cookie ->
          cookie
          |> String.split(";", parts: 2)
          |> List.first()
        end)
      end)
      |> Enum.reject(&(&1 == ""))

    case cookies do
      [] -> []
      _ -> [{"cookie", Enum.join(cookies, "; ")}]
    end
  end

  defp result_fragment_html(document) do
    case Enum.find_value(@result_selectors, fn selector ->
           case Floki.find(document, selector) do
             [] -> nil
             nodes -> Floki.raw_html(nodes)
           end
         end) do
      nil -> Floki.raw_html(document)
      html -> html
    end
  end

  defp html_to_text(html) do
    case Floki.parse_document(html) do
      {:ok, document} -> Floki.text(document, sep: "\n")
      {:error, _reason} -> html
    end
  end

  defp isolate_result_text(text) do
    cond do
      String.contains?(text, @result_heading) ->
        [_before, after_heading] = String.split(text, @result_heading, parts: 2)
        after_heading

      first_label = first_present_label(text) ->
        {index, _length} = first_label
        binary_part(text, index, byte_size(text) - index)

      not_found_index = first_present_not_found_message(text) ->
        {index, _length} = not_found_index
        binary_part(text, index, byte_size(text) - index)

      true ->
        text
    end
  end

  defp parse_result_text(text) do
    lines =
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    result = %Result{
      tax_id: value_for(lines, Map.fetch!(@field_labels, :tax_id)),
      legal_name: value_for(lines, Map.fetch!(@field_labels, :legal_name)),
      economic_activity: value_for(lines, Map.fetch!(@field_labels, :economic_activity)),
      local_administration: value_for(lines, Map.fetch!(@field_labels, :local_administration))
    }

    if result_found?(result) do
      {:ok, result}
    else
      {:error, :result_not_found}
    end
  end

  defp value_for(lines, labels) do
    case Enum.find_index(lines, &(&1 in labels)) do
      nil ->
        nil

      index ->
        Enum.at(lines, index + 1)
    end
  end

  defp result_found?(%Result{} = result) do
    Enum.all?(
      [
        result.tax_id,
        result.legal_name,
        result.economic_activity,
        result.local_administration
      ],
      &is_binary/1
    )
  end

  defp first_present_label(text) do
    first_present_marker(text, @result_labels)
  end

  defp first_present_not_found_message(text) do
    first_present_marker(text, @not_found_messages)
  end

  defp first_present_marker(text, markers) do
    markers
    |> Enum.map(fn marker -> {:binary.match(text, marker), byte_size(marker)} end)
    |> Enum.reject(fn {match, _length} -> match == :nomatch end)
    |> Enum.map(fn {{index, _match_length}, marker_length} -> {index, marker_length} end)
    |> Enum.min_by(fn {index, _length} -> index end, fn -> nil end)
  end

  defp normalize_text(text) do
    text
    |> String.replace("\u00A0", " ")
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reject(&noise_line?/1)
    |> Enum.join("\n")
  end

  defp noise_line?(line) do
    line in [@result_heading, "Buscar", "Resultados de la búqueda"] or
      String.starts_with?(line, "Descargar Listado de todos los RNC") or
      String.starts_with?(line, "Imagen animada para indicar cargando")
  end
end
