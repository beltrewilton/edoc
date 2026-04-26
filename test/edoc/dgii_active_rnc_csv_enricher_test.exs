defmodule Edoc.DgiiActiveRncCsvEnricherTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Edoc.DgiiActiveRncCsvEnricher
  alias Edoc.DgiiRncScraper.Result

  test "streams active rows, enriches them, and writes a CSV incrementally" do
    input_path = unique_tmp_path("active_rncs_input.csv")
    output_path = unique_tmp_path("active_rncs_output.csv")

    csv = """
    RNC,RAZON SOCIAL,ACTIVIDAD ECONOMICA,FECHA DE INICIO OPERACIONES,ESTADO,REGIMEN DE PAGO
    "001","ACME, SRL","SERVICIOS ""PLUS""","01/01/2020","ACTIVO","NORMAL"
    "002","INACTIVA SRL","SERVICIOS","","SUSPENDIDO","NORMAL"
    "003","OTRA ACTIVA","OTROS","","ACTIVO","NORMAL"
    """

    File.write!(input_path, csv)

    lookup_fun = fn
      "001" ->
        {:ok,
         %Result{
           tax_id: "001-0000000-1",
           legal_name: "ACME, SRL",
           economic_activity: "SERVICIOS PLUS",
           local_administration: "ADM LOCAL 1",
           electronic_invoicer: "Sí"
         }}

      "003" ->
        {:error, :not_found}
    end

    sleep_parent = self()

    progress_output =
      capture_io(fn ->
        assert {:ok, summary} =
                 DgiiActiveRncCsvEnricher.enrich_active_rncs(input_path,
                   output_path: output_path,
                   lookup_fun: lookup_fun,
                   sleep_fun: fn milliseconds -> send(sleep_parent, {:slept, milliseconds}) end,
                   sleep_range: 7..7,
                   input_encoding: :utf8
                 )

        assert summary.total_rows == 3
        assert summary.active_rows == 2
        assert summary.written_rows == 2
        assert summary.successful_lookups == 1
        assert summary.failed_lookups == 1
        assert summary.skipped_rows == 1
        assert summary.output_path == output_path
      end)

    assert progress_output =~ "1/2 - 50.0%"
    assert progress_output =~ "2/2 - 100.0%"

    assert_received {:slept, 7}
    assert_received {:slept, 7}

    output = File.read!(output_path)
    lines = String.split(output, "\n", trim: true)

    assert length(lines) == 3
    assert Enum.at(lines, 0) =~ ~s("DGII_LOOKUP_STATUS","DGII_TAX_ID")
    assert Enum.at(lines, 1) =~ ~s("001","ACME, SRL","SERVICIOS ""PLUS""","01/01/2020","ACTIVO","NORMAL","ok","001-0000000-1","ACME, SRL","SERVICIOS PLUS","ADM LOCAL 1","Sí","")
    assert Enum.at(lines, 2) =~ ~s("003","OTRA ACTIVA","OTROS","","ACTIVO","NORMAL","error","","","","","",":not_found")
  end

  test "decodes latin1 input by default" do
    input_path = unique_tmp_path("active_rncs_latin1_input.csv")
    output_path = unique_tmp_path("active_rncs_latin1_output.csv")

    csv = """
    RNC,RAZÓN SOCIAL,ACTIVIDAD ECONÓMICA,FECHA DE INICIO OPERACIONES,ESTADO,RÉGIMEN DE PAGO
    "004","PEÑA SRL","PRÉSTAMO","","ACTIVO","NORMAL"
    """

    File.write!(input_path, :unicode.characters_to_binary(csv, :utf8, :latin1))

    assert {:ok, summary} =
             DgiiActiveRncCsvEnricher.enrich_active_rncs(input_path,
               output_path: output_path,
               lookup_fun: fn "004" ->
                 {:ok,
                  %Result{
                    tax_id: "004-0000000-4",
                    legal_name: "PEÑA SRL",
                    economic_activity: "PRÉSTAMO",
                    local_administration: "ADM LOCAL PEÑA",
                    electronic_invoicer: "No"
                  }}
               end,
               sleep_fun: fn _milliseconds -> :ok end,
               sleep_range: 0..0
             )

    assert summary.active_rows == 1

    output = File.read!(output_path)
    assert output =~ "RAZÓN SOCIAL"
    assert output =~ "PRÉSTAMO"
    assert output =~ "ADM LOCAL PEÑA"
  end

  test "returns an error when required headers are missing" do
    input_path = unique_tmp_path("active_rncs_missing_headers.csv")
    output_path = unique_tmp_path("active_rncs_missing_headers_output.csv")

    File.write!(input_path, "RNC,NOMBRE\n\"001\",\"ACME\"\n")

    assert {:error, {:missing_headers, ["ESTADO"]}} =
             DgiiActiveRncCsvEnricher.enrich_active_rncs(input_path,
               output_path: output_path,
               input_encoding: :utf8
             )
  end

  defp unique_tmp_path(filename) do
    Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}_#{filename}")
  end
end
