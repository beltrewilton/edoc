defmodule Edoc.DgiiRncScraperTest do
  use ExUnit.Case, async: true

  alias Edoc.DgiiRncScraper
  alias Edoc.DgiiRncScraper.Result

  describe "build_postback_payload/2" do
    test "keeps asp.net hidden fields and search button values" do
      html = """
      <html>
        <body>
          <form method="post" action="./rnc.aspx" id="form1">
            <input type="hidden" name="__VIEWSTATE" value="view-state-token" />
            <input type="hidden" name="__EVENTVALIDATION" value="event-validation-token" />
            <input type="text" name="ctl00$cphMain$txtRNCCedula" value="" />
            <input type="submit" name="ctl00$cphMain$btnBuscarPorRNC" value="Buscar" />
          </form>
        </body>
      </html>
      """

      assert {:ok, payload} = DgiiRncScraper.build_postback_payload(html, "132620951")

      assert {"__VIEWSTATE", "view-state-token"} in payload
      assert {"__EVENTVALIDATION", "event-validation-token"} in payload
      assert {"ctl00$cphMain$txtRNCCedula", "132620951"} in payload
      assert {"ctl00$cphMain$btnBuscarPorRNC", "Buscar"} in payload
    end

    test "returns an error when the search form is missing" do
      html = """
      <html>
        <body>
          <h1>Acceso denegado</h1>
        </body>
      </html>
      """

      assert {:error, :search_form_not_found} =
               DgiiRncScraper.build_postback_payload(html, "132620951")
    end
  end

  describe "extract_result_text/1" do
    test "strips tags and keeps the result block text" do
      html = """
      <html>
        <body>
          <div id="cphMain_dvResultado">
            <h5>Resultados de la búsqueda</h5>
            <table>
              <tr><th>Cédula/RNC</th><td>132620951</td></tr>
              <tr><th>Nombre/Razón Social</th><td>KOI CORPORATION BY SAIKOV SRL</td></tr>
              <tr><th>Nombre Comercial</th><td>KOI CORPORATION BY SAIKOV</td></tr>
              <tr><th>Estado</th><td>ACTIVO</td></tr>
            </table>
          </div>
        </body>
      </html>
      """

      assert {:ok, text} = DgiiRncScraper.extract_result_text(html)

      refute text =~ "<table>"
      assert text =~ "Cédula/RNC"
      assert text =~ "132620951"
      assert text =~ "Nombre/Razón Social"
      assert text =~ "KOI CORPORATION BY SAIKOV SRL"
      assert text =~ "Estado"
      assert text =~ "ACTIVO"
    end

    test "returns not found messages as plain text" do
      html = """
      <html>
        <body>
          <div>
            <h5>Resultados de la búsqueda</h5>
            <span>No se encontraron datos para la búsqueda realizada.</span>
          </div>
        </body>
      </html>
      """

      assert {:ok, text} = DgiiRncScraper.extract_result_text(html)
      assert text == "No se encontraron datos para la búsqueda realizada."
    end
  end

  describe "extract_result/1" do
    test "returns a normalized struct for successful lookups" do
      html = """
      <html>
        <body>
          <div id="cphMain_dvResultado">
            <h5>Resultados de la búsqueda</h5>
            <div>Error:</div>
            <div>RNC pendiente de solicitar su Adecuación o Transformación.</div>
            <div>Mensaje:</div>
            <div>RNC cumplió con la Adecuación/Transformación o no la requiere.</div>
            <table>
              <tr><th>Cédula/RNC</th><td>132-62095-1</td></tr>
              <tr><th>Nombre/Razón Social</th><td>KOI CORPORATION BY SAIKOV SRL</td></tr>
              <tr><th>Actividad Economica</th><td>SERVICIOS DE TELEMARKETING Y/O PROFESIONAL MERCADEO</td></tr>
              <tr><th>Administracion Local</th><td>ADM LOCAL LOS PRÓCERES</td></tr>
              <tr><th>Facturador Electronico</th><td>Sí</td></tr>
            </table>
          </div>
        </body>
      </html>
      """

      assert {:ok,
              %Result{
                tax_id: "132-62095-1",
                legal_name: "KOI CORPORATION BY SAIKOV SRL",
                economic_activity: "SERVICIOS DE TELEMARKETING Y/O PROFESIONAL MERCADEO",
                local_administration: "ADM LOCAL LOS PRÓCERES",
                electronic_invoicer: "Sí"
              }} = DgiiRncScraper.extract_result(html)
    end

    test "returns not found when dgii only shows advisory messages" do
      html = """
      <html>
        <body>
          <div id="cphMain_dvResultado">
            <h5>Resultados de la búsqueda</h5>
            <div>Error:</div>
            <div>RNC pendiente de solicitar su Adecuación o Transformación.</div>
            <div>Favor hacer su solicitud y evite inactivación y multas.</div>
            <div>Mensaje:</div>
            <div>RNC cumplió con la Adecuación/Transformación o no la requiere.</div>
          </div>
        </body>
      </html>
      """

      assert {:error, :result_not_found} = DgiiRncScraper.extract_result(html)
    end
  end
end
