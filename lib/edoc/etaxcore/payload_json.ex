defmodule Edoc.Etaxcore.PayloadJson do
  @moduledoc """
  JSON encoding helpers for eTaxCore payloads.
  """

  @top_level_order ~w(
    encabezado
    detallesItems
    subtotales
    descuentosORecargos
    paginacion
    informacionReferencia
    fechaHoraFirma
  )

  @encabezado_order ~w(
    version
    idDoc
    emisor
    comprador
    informacionesAdicionales
    transporte
    totales
    codigoSeguridadeCF
    otraMoneda
  )

  @id_doc_order ~w(
    tipoeCF
    encf
    indicadorNotaCredito
    fechaVencimientoSecuencia
    indicadorEnvioDiferido
    indicadorMontoGravado
    indicadorServicioTodoIncluido
    tipoIngresos
    tipoPago
    fechaLimitePago
    FechaLimitePago
    terminoPago
    tablaFormasPago
    tipoCuentaPago
    numeroCuentaPago
    bancoPago
    fechaDesde
    fechaHasta
    totalPaginas
  )

  @forma_pago_order ~w(formaPago montoPago)

  @emisor_order ~w(
    rncEmisor
    razonSocialEmisor
    nombreComercial
    sucursal
    direccionEmisor
    municipio
    provincia
    tablaTelefonoEmisor
    correoEmisor
    webSite
    actividadEconomica
    codigoVendedor
    numeroFacturaInterna
    numeroPedidoInterno
    zonaVenta
    rutaVenta
    informacionAdicionalEmisor
    fechaEmision
  )

  @comprador_order ~w(
    rncComprador
    identificadorExtranjero
    razonSocialComprador
    contactoComprador
    tablaTelefonoComprador
    correoComprador
    direccionComprador
    municipioComprador
    provinciaComprador
    fechaEntrega
    contactoEntrega
    direccionEntrega
    telefonoAdicional
    fechaOrdenCompra
    numeroOrdenCompra
    codigoInternoComprador
    responsablePago
    informacionAdicionalComprador
  )

  @informaciones_adicionales_order ~w(
    fechaEmbarque
    numeroEmbarque
    numeroContenedor
    numeroReferencia
    pesoBruto
    pesoNeto
    unidadPesoBruto
    unidadPesoNeto
    cantidadBulto
    unidadBulto
    volumenBulto
    unidadVolumen
  )

  @transporte_order ~w(
    paisDestino
    conductor
    documentoTransporte
    ficha
    placa
    rutaTransporte
    zonaTransporte
    numeroAlbaran
  )

  @totales_order ~w(
    montoGravadoTotal
    montoGravadoI1
    montoGravadoI2
    montoGravadoI3
    montoExento
    itbis1
    itbis2
    itbis3
    totalITBIS
    totalITBIS1
    totalITBIS2
    totalITBIS3
    montoImpuestoAdicional
    impuestosAdicionales
    montoTotal
    montoNoFacturable
    montoPeriodo
    saldoAnterior
    montoAvancePago
    valorPagar
    totalITBISRetenido
    totalISRRetencion
    totalITBISPercepcion
    totalISRPercepcion
  )

  @impuesto_adicional_order ~w(
    tipoImpuesto
    tasaImpuestoAdicional
    montoImpuestoSelectivoConsumoEspecifico
    montoImpuestoSelectivoConsumoAdvalorem
    otrosImpuestosAdicionales
  )

  @otra_moneda_order ~w(
    tipoMoneda
    tipoCambio
    montoGravadoTotalOtraMoneda
    montoGravado1OtraMoneda
    montoGravado2OtraMoneda
    montoGravado3OtraMoneda
    montoExentoOtraMoneda
    totalITBISOtraMoneda
    totalITBIS1OtraMoneda
    totalITBIS2OtraMoneda
    totalITBIS3OtraMoneda
    montoImpuestoAdicionalOtraMoneda
    impuestosAdicionalesOtraMoneda
    montoTotalOtraMoneda
  )

  @impuesto_adicional_otra_moneda_order ~w(
    tipoImpuestoOtraMoneda
    tasaImpuestoAdicionalOtraMoneda
    montoImpuestoSelectivoConsumoEspecificoOtraMoneda
    montoImpuestoSelectivoConsumoAdvaloremOtraMoneda
    otrosImpuestosAdicionalesOtraMoneda
  )

  @detalle_item_order ~w(
    numeroLinea
    tablaCodigosItem
    indicadorFacturacion
    retencion
    nombreItem
    indicadorBienoServicio
    descripcionItem
    cantidadItem
    unidadMedida
    cantidadReferencia
    unidadReferencia
    tablaSubcantidad
    gradosAlcohol
    precioUnitarioReferencia
    fechaElaboracion
    fechaVencimientoItem
    mineria
    precioUnitarioItem
    descuentoMonto
    tablaSubDescuento
    recargoMonto
    tablaSubRecargo
    tablaImpuestoAdicional
    otraMonedaDetalle
    montoItem
  )

  @codigo_item_order ~w(tipoCodigo codigoItem)
  @retencion_order ~w(indicadorAgenteRetencionoPercepcion montoITBISRetenido montoISRRetenido)
  @subcantidad_order ~w(subcantidad codigoSubcantidad)
  @mineria_order ~w(pesoNetoKilogramo pesoNetoMineria tipoAfiliacion liquidacion)
  @subdescuento_order ~w(tipoSubDescuento subDescuentoPorcentaje montoSubDescuento)
  @subrecargo_order ~w(tipoSubRecargo subRecargoPorcentaje montoSubRecargo)
  @tabla_impuesto_adicional_order ~w(tipoImpuesto)

  @otra_moneda_detalle_order ~w(
    precioOtraMoneda
    descuentoOtraMoneda
    recargoOtraMoneda
    montoItemOtraMoneda
  )

  @subtotal_order ~w(
    numeroSubTotal
    descripcionSubtotal
    orden
    subTotalMontoGravadoTotal
    subTotalMontoGravadoI1
    subTotalMontoGravadoI2
    subTotalMontoGravadoI3
    subTotaITBIS
    subTotaITBIS1
    subTotaITBIS2
    subTotaITBIS3
    subTotalImpuestoAdicional
    subTotalExento
    montoSubTotal
    lineas
  )

  @descuento_recargo_order ~w(
    numeroLinea
    tipoAjuste
    indicadorNorma1007
    descripcionDescuentooRecargo
    tipoValor
    valorDescuentooRecargo
    montoDescuentooRecargo
    montoDescuentooRecargoOtraMoneda
    indicadorFacturacionDescuentooRecargo
  )

  @paginacion_order ~w(
    paginaNo
    noLineaDesde
    noLineaHasta
    subtotalMontoGravadoPagina
    subtotalMontoGravado1Pagina
    subtotalMontoGravado2Pagina
    subtotalMontoGravado3Pagina
    subtotalExentoPagina
    subtotalItbisPagina
    subtotalItbis1Pagina
    subtotalItbis2Pagina
    subtotalItbis3Pagina
    subtotalImpuestoAdicionalPagina
    subtotalImpuestoAdicional
    montoSubtotalPagina
    subtotalMontoNoFacturablePagina
  )

  @subtotal_impuesto_adicional_order ~w(
    subtotalImpuestoSelectivoConsumoEspecificoPagina
    subtotalOtrosImpuesto
  )

  @informacion_referencia_order ~w(
    ncfModificado
    rncOtroContribuyente
    fechaNCFModificado
    codigoModificacion
    razonModificacion
  )

  @spec encode!(map(), keyword()) :: String.t()
  def encode!(payload, opts \\ []) when is_map(payload) do
    payload
    |> ordered_payload()
    |> Jason.encode!(opts)
  end

  @spec encode(map(), keyword()) :: {:ok, String.t()} | {:error, Jason.EncodeError.t()}
  def encode(payload, opts \\ []) when is_map(payload) do
    payload
    |> ordered_payload()
    |> Jason.encode(opts)
  end

  @spec ordered_payload(map()) :: Jason.OrderedObject.t()
  def ordered_payload(payload) when is_map(payload) do
    ordered_object(payload, [])
  end

  defp ordered_value(value, path) when is_map(value), do: ordered_object(value, path)

  defp ordered_value(value, path) when is_list(value),
    do: Enum.map(value, &ordered_value(&1, path))

  defp ordered_value(value, _path), do: value

  defp ordered_object(payload, path) do
    order = key_order(path)
    ordered_keys = Enum.filter(order, &Map.has_key?(payload, &1))
    remaining_keys = payload |> Map.keys() |> Kernel.--(ordered_keys) |> Enum.sort()

    (ordered_keys ++ remaining_keys)
    |> Enum.map(fn key -> {key, ordered_value(Map.fetch!(payload, key), path ++ [key])} end)
    |> Jason.OrderedObject.new()
  end

  defp key_order([]), do: @top_level_order
  defp key_order(["encabezado"]), do: @encabezado_order
  defp key_order(["encabezado", "idDoc"]), do: @id_doc_order
  defp key_order(["encabezado", "idDoc", "tablaFormasPago"]), do: @forma_pago_order
  defp key_order(["encabezado", "emisor"]), do: @emisor_order
  defp key_order(["encabezado", "comprador"]), do: @comprador_order
  defp key_order(["encabezado", "informacionesAdicionales"]), do: @informaciones_adicionales_order
  defp key_order(["encabezado", "transporte"]), do: @transporte_order
  defp key_order(["encabezado", "totales"]), do: @totales_order
  defp key_order(["encabezado", "totales", "impuestosAdicionales"]), do: @impuesto_adicional_order
  defp key_order(["encabezado", "otraMoneda"]), do: @otra_moneda_order

  defp key_order(["encabezado", "otraMoneda", "impuestosAdicionalesOtraMoneda"]),
    do: @impuesto_adicional_otra_moneda_order

  defp key_order(["detallesItems"]), do: @detalle_item_order
  defp key_order(["detallesItems", "tablaCodigosItem"]), do: @codigo_item_order
  defp key_order(["detallesItems", "retencion"]), do: @retencion_order
  defp key_order(["detallesItems", "tablaSubcantidad"]), do: @subcantidad_order
  defp key_order(["detallesItems", "mineria"]), do: @mineria_order
  defp key_order(["detallesItems", "tablaSubDescuento"]), do: @subdescuento_order
  defp key_order(["detallesItems", "tablaSubRecargo"]), do: @subrecargo_order
  defp key_order(["detallesItems", "tablaImpuestoAdicional"]), do: @tabla_impuesto_adicional_order
  defp key_order(["detallesItems", "otraMonedaDetalle"]), do: @otra_moneda_detalle_order
  defp key_order(["subtotales"]), do: @subtotal_order
  defp key_order(["descuentosORecargos"]), do: @descuento_recargo_order
  defp key_order(["paginacion"]), do: @paginacion_order

  defp key_order(["paginacion", "subtotalImpuestoAdicional"]),
    do: @subtotal_impuesto_adicional_order

  defp key_order(["informacionReferencia"]), do: @informacion_referencia_order
  defp key_order(_path), do: []
end