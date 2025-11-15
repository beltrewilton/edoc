defmodule Edoc.OdooAutomationClient do
  @moduledoc """
  Elixir version of the Python OdooAutomationClient, using explicit uid context.

  Flow:
      alias Edoc.OdooAutomationClient,  as: Odoo
      client = Odoo.new()
      uid = Odoo.authenticate!(client)
      field_id = Odoo.create_edoc_field(client, uid)
      Odoo.create_edoc_selection_values(client, uid, field_id)
      field_id = Odoo.create_edoc_field(client, uid, "x_studio_e_doc_bill", "Tipo de e-DOC Gastos", "Identificadorde Gastos del tipo de e-DOC requerido para factura electrónica.")
      Odoo.create_edoc_selection_values(client, uid, field_id, false)
      Odoo.create_edoc_view_inheritance(client, uid)
      Odoo.create_state_change_automation(client, uid, "Automation-DGII", "Send Webhook Notification (dgii-gw)", "account.move", "posted")

      invoice_items = Odoo.get_invoice_data(client, uid, 5523)


      # RESET:
      # Studio: remove field from the UI
      # Technical > Automation > Automation Rules: delete Automation-DGII-Gateway
      #                              deleted-child: Send Webhook Notification (dgii-gw)
      # Technical > Database estructure > Fields : delete x_studio_e_doc (Journal Entry)
      # Technical > User interface > Views: delete account_move_form_edoc_field
      # Technical > Views : search `account.move.form`,
      #         Inherited Views (tab) - delete Odoo Studio: account.move.form customization
      #         Test: From invoice > go to studio


  All calls that hit Odoo (XML-RPC /object) receive `uid` explicitly.
  """

  defstruct [:url, :db, :user, :apikey]

  @type t :: %__MODULE__{
          url: String.t(),
          db: String.t(),
          user: String.t(),
          apikey: String.t()
        }

  @common_path "/xmlrpc/2/common"
  @object_path "/xmlrpc/2/object"

  @url System.fetch_env!("ODOO_URL")
  @db System.fetch_env!("ODOO_DB")
  @user System.fetch_env!("ODOO_USER")
  @apikey System.fetch_env!("ODOO_APIKEY")

  @automation_name "Automation-DGII-Gateway"
  @action_server_name "Send Webhook Notification (dgii-gw)"
  @target_model "account.move"
  @target_state "posted"

  @spec new(String.t(), String.t(), String.t(), String.t()) :: t()
  def new(url \\ @url, db \\ @db, user \\ @user, apikey \\ @apikey) do
    %__MODULE__{
      url: String.trim_trailing(url, "/"),
      db: db,
      user: user,
      apikey: apikey
    }
  end

  # ---------------------------------------------------------------------------
  # Low-level XML-RPC helpers
  # ---------------------------------------------------------------------------

  defp common_url(%__MODULE__{url: base}), do: base <> @common_path
  defp object_url(%__MODULE__{url: base}), do: base <> @object_path

  defp xmlrpc_call!(url, method_name, params) do
    body =
      %XMLRPC.MethodCall{method_name: method_name, params: params}
      |> XMLRPC.encode!()

    resp =
      Req.post!(
        url: url,
        body: body,
        headers: [{"content-type", "text/xml"}]
      )

    case XMLRPC.decode!(resp.body) do
      %XMLRPC.MethodResponse{param: param} ->
        param

      %XMLRPC.Fault{fault_code: code, fault_string: reason} ->
        raise "XML-RPC fault calling #{method_name}: #{code} #{reason}"

      other ->
        raise "Unexpected XML-RPC response for #{method_name}: #{inspect(other)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Auth
  # ---------------------------------------------------------------------------

  @doc """
  Authenticate and return uid.

  Call this once and reuse `uid` in subsequent calls.
  """
  @spec authenticate!(t()) :: integer()
  def authenticate!(%__MODULE__{} = client) do
    params = [client.db, client.user, client.apikey, %{}]
    uid = xmlrpc_call!(common_url(client), "authenticate", params)

    IO.puts("Authenticated user id: #{inspect(uid)}")

    case uid do
      false -> raise "Authentication failed."
      nil -> raise "Authentication failed."
      _ -> uid
    end
  end

  # ---------------------------------------------------------------------------
  # execute_kw!
  # ---------------------------------------------------------------------------

  @doc """
  Low-level helper to call execute_kw with current db/uid/apikey.
  """
  @spec execute_kw!(t(), integer(), String.t(), String.t(), list(), map()) :: any()
  def execute_kw!(%__MODULE__{} = client, uid, model, method, args \\ [], kwargs \\ %{}) do
    params = [client.db, uid, client.apikey, model, method, args, kwargs]
    xmlrpc_call!(object_url(client), "execute_kw", params)
  end

  # ---------------------------------------------------------------------------
  # Helpers mirroring the Python methods (all receive uid)
  # ---------------------------------------------------------------------------

  @doc """
  Return the ir.model record for a given model (e.g. 'account.move').
  """
  @spec get_model(t(), integer(), String.t()) :: map()
  def get_model(%__MODULE__{} = client, uid, model_name) do
    args = [[["model", "=", model_name]]]
    kwargs = %{fields: ["id", "model", "name"], limit: 1}

    records = execute_kw!(client, uid, "ir.model", "search_read", args, kwargs)

    case records do
      [rec | _] -> rec
      [] -> raise "Model #{model_name} not found"
    end
  end

  @doc """
  Return ir.model.fields record for a given model_id + field name.
  """
  @spec get_field(t(), integer(), integer(), String.t()) :: map()
  def get_field(%__MODULE__{} = client, uid, model_id, field_name) do
    args = [[["model_id", "=", model_id], ["name", "=", field_name]]]
    kwargs = %{fields: ["id", "name", "ttype", "model_id"], limit: 1}

    records = execute_kw!(client, uid, "ir.model.fields", "search_read", args, kwargs)

    case records do
      [rec | _] -> rec
      [] -> raise "Field '#{field_name}' not found for model_id #{model_id}"
    end
  end

  @doc """
  Return ir.model.fields.selection record for given field & technical value.
  """
  @spec get_selection_value(t(), integer(), integer(), String.t()) :: map()
  def get_selection_value(%__MODULE__{} = client, uid, field_id, value) do
    args = [[["field_id", "=", field_id], ["value", "=", value]]]
    kwargs = %{fields: ["id", "name", "value"], limit: 1}

    records =
      execute_kw!(
        client,
        uid,
        "ir.model.fields.selection",
        "search_read",
        args,
        kwargs
      )

    case records do
      [rec | _] -> rec
      [] -> raise "Selection value '#{value}' not found for field_id #{field_id}"
    end
  end

  @doc """
  Fetch and print the first base.automation record.
  """
  @spec get_first_automation(t(), integer()) :: map()
  def get_first_automation(%__MODULE__{} = client, uid) do
    records =
      execute_kw!(client, uid, "base.automation", "search_read", [[]], %{limit: 1})

    case records do
      [] ->
        raise "No base.automation records found"

      [record | _] ->
        IO.puts("################ First base.automation record: ##################")

        record
        |> Enum.each(fn {field_name, value} ->
          IO.puts("#{field_name}: #{inspect(value)}")
        end)

        record
    end
  end

  @doc """
  Print Odoo server version and related info (no auth required).
  """
  @spec show_odoo_server_info(t()) :: map()
  def show_odoo_server_info(%__MODULE__{} = client) do
    info = xmlrpc_call!(common_url(client), "version", [])

    IO.puts("######## Odoo server info ########")

    info
    |> Enum.each(fn {key, value} ->
      IO.puts("#{key}: #{inspect(value)}")
    end)

    info
  end

  @doc """
  Return {ids, names} for selected fields of given model_id (default: account.move).
  """
  @spec get_account_move_field_ids_and_names(
          t(),
          integer(),
          integer(),
          String.t()
        ) :: {list(integer()), list(String.t())}
  def get_account_move_field_ids_and_names(
        %__MODULE__{} = client,
        uid,
        model_id,
        _target_model \\ "account.move"
      ) do
    allowed_fields = [
      "amount_paid",
      "amount_residual",
      "amount_tax",
      "amount_total",
      "amount_untaxed",
      "commercial_partner_id",
      "company_id",
      "display_name",
      "invoice_date",
      "invoice_date_due",
      "invoice_origin",
      "invoice_partner_display_name",
      "invoice_line_ids",
      "line_ids",
      "name",
      "partner_id",
      "payment_reference",
      "payment_state",
      "ref",
      "status_in_payment",
      "tax_totals",
      "transaction_ids",
      "x_studio_e_doc_inv",
      "x_studio_e_doc_bill"
    ]

    domain = [
      ["model_id", "=", model_id],
      ["name", "in", allowed_fields]
    ]

    args = [domain]
    kwargs = %{fields: ["id", "name", "field_description"], limit: 1000}

    fields = execute_kw!(client, uid, "ir.model.fields", "search_read", args, kwargs)

    ids = Enum.map(fields, & &1["id"])

    names =
      Enum.map(fields, fn f ->
        Map.get(f, "field_description") || Map.get(f, "name")
      end)

    {ids, names}
  end

  @doc """
  Print ir.actions.server record for given ID (default: 629).
  """
  @spec show_server_action(t(), integer(), integer()) :: :ok
  def show_server_action(%__MODULE__{} = client, uid, action_id \\ 629) do
    args = [[action_id]]

    kwargs = %{
      fields: ["id", "state", "name", "model_id", "webhook_url", "webhook_field_ids"]
    }

    records = execute_kw!(client, uid, "ir.actions.server", "read", args, kwargs)

    case records do
      [] ->
        IO.puts("No ir.actions.server found with id #{action_id}")
        :ok

      [record | _] ->
        IO.puts("######## ir.actions.server id=#{action_id} ########")

        Enum.each(record, fn {field_name, value} ->
          IO.puts("#{field_name}: #{inspect(value)}")
        end)

        :ok
    end
  end

  @doc """
  Create ir.actions.server with webhook state and return its id.
  """
  @spec create_action_server(t(), integer(), integer(), String.t(), String.t(), String.t()) :: integer()
  def create_action_server(
        %__MODULE__{} = client,
        uid,
        model_id,
        action_server_name,
        user_id,
        company_id
      ) do
    {webhook_field_ids, _names} =
      get_account_move_field_ids_and_names(client, uid, model_id, "account.move")

    url         = System.fetch_env!("WEBHOOK_URL")
    webhook_url = "#{url}/#{user_id}/#{company_id}"

    base_vals = %{
      name: action_server_name,
      state: "webhook",
      model_id: model_id,
      webhook_url: webhook_url,
      webhook_field_ids: webhook_field_ids
    }

    execute_kw!(client, uid, "ir.actions.server", "create", [base_vals])
  end

  # ---------------------------------------------------------------------------
  # Automation creation
  # ---------------------------------------------------------------------------

  @doc """
  Create a base.automation that triggers on a specific state for a model's 'state' field.
  """
  @spec create_state_change_automation(
          t(),
          integer(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: integer()
  def create_state_change_automation(
        %__MODULE__{} = client,
        uid,
        automation_name,
        action_server_name,
        target_model,
        user_id,
        company_id,
        target_state \\ "draft"
      ) do
    # 1) Get model
    model_rec = get_model(client, uid, target_model)
    model_id = model_rec["id"]

    # 2) Get 'state' field
    state_field = get_field(client, uid, model_id, "state")
    trigger_field_id = state_field["id"]

    IO.puts("trigger_field_id: #{trigger_field_id}")
    IO.puts("trigger_field_name: #{state_field["name"]}")

    # 3) Get selection value for target_state
    selection = get_selection_value(client, uid, trigger_field_id, target_state)
    trg_selection_field_id = selection["id"]

    IO.puts("trg_selection_field_id: #{trg_selection_field_id}")

    # 4) Create server action
    action_id = create_action_server(client, uid, model_id, action_server_name, user_id, company_id)

    base_vals = %{
      name: automation_name,
      active: true,
      model_id: model_id,
      trigger: "on_state_set",
      trg_selection_field_id: trg_selection_field_id,
      trigger_field_ids: [trigger_field_id],
      action_server_ids: [action_id]
    }

    execute_kw!(client, uid, "base.automation", "create", [base_vals])
  end

  @doc """
  Discover all fields on account.move with their technical name and type.
  """
  @spec list_account_move_fields(t(), integer()) :: map()
  def list_account_move_fields(%__MODULE__{} = client, uid) do
    fields =
      execute_kw!(
        client,
        uid,
        "account.move",
        "fields_get",
        [],
        %{attributes: ["type", "string"]}
      )

    IO.puts("######## account.move fields (name -> type) ########")

    fields
    |> Map.keys()
    |> Enum.sort()
    |> Enum.each(fn fname ->
      meta = fields[fname]
      ftype = meta["type"]
      label = meta["string"]

      fname_padded = String.pad_trailing(fname, 40)
      type_padded = String.pad_trailing(ftype || "", 10)

      IO.puts("#{fname_padded} #{type_padded} (#{label})")
    end)

    fields
  end

  @doc """
  Debug meta info for x_studio_e_doc (or any selection) field.
  """
  @spec debug_edoc_field_meta(t(), integer(), String.t(), String.t()) :: :ok
  def debug_edoc_field_meta(
        %__MODULE__{} = client,
        uid,
        model_name \\ "account.move",
        field_name \\ "x_studio_e_doc_inv"
      ) do
    model = get_model(client, uid, model_name)
    field = get_field(client, uid, model["id"], field_name)

    IO.inspect(field, label: "field")

    selection_rows =
      execute_kw!(
        client,
        uid,
        "ir.model.fields.selection",
        "search_read",
        [[["field_id", "=", field["id"]]]],
        %{fields: ["id", "value", "name", "sequence"], order: "sequence"}
      )

    IO.inspect(selection_rows, label: "selection_rows")
    :ok
  end

  @doc """
  Fetch account.move.line records by a list of IDs.
  """
  @spec get_move_lines_by_ids(
          t(),
          integer(),
          list(integer()) | nil,
          list(String.t()) | nil
        ) :: list(map())
  def get_move_lines_by_ids(_client, _uid, nil, _fields), do: []
  def get_move_lines_by_ids(_client, _uid, [], _fields), do: []

  def get_move_lines_by_ids(
        %__MODULE__{} = client,
        uid,
        line_ids,
        fields \\ nil
      ) do
    kwargs =
      case fields do
        nil -> %{}
        list when is_list(list) -> %{fields: list}
      end

    execute_kw!(client, uid, "account.move.line", "read", [line_ids], kwargs)
  end

  @doc """
  Create x_studio_e_doc custom selection field on given model (default: account.move).
  """
  @spec create_edoc_field(t(), integer(), String.t(), String.t(), String.t(), String.t()) ::
          integer()
  def create_edoc_field(
        %__MODULE__{} = client,
        uid,
        field_name \\ "x_studio_e_doc_inv",
        field_description \\ "Tipo de e-DOC",
        help \\ "Identificador del tipo de e-DOC requerido para factura electrónica.",
        model_name \\ "account.move"
      ) do
    model = get_model(client, uid, model_name)
    model_id = model["id"]

    vals = %{
      name: field_name,
      field_description: field_description,
      model_id: model_id,
      ttype: "selection",
      required: true,
      store: true,
      help: help,
      state: "manual"
    }

    field_id = execute_kw!(client, uid, "ir.model.fields", "create", [vals])

    IO.puts("Created field #{field_name} id: #{field_id}")
    field_id
  end

  @doc """
  Create selection values for the given x_studio_e_doc field id.
  """
  @spec create_edoc_selection_values(t(), integer(), integer(), boolean()) :: list(integer())
  def create_edoc_selection_values(%__MODULE__{} = client, uid, field_id, is_invoice? \\ true) do
    options =
      if is_invoice?,
        do: [
          {"E31", "E31 Factura de Crédito Fiscal Electrónica"},
          {"E32", "E32 Factura de Consumo Electrónica"},
          {"E33", "E33 Nota de Débito Electrónica"},
          {"E34", "E34 Nota de Crédito Electrónica"},
          {"E44", "E44 Comprobante Electrónico para Regímenes Especiales"},
          {"E45", "E45 Comprobante Electrónico Gubernamental"},
          {"E46", "E46 Comprobante Electrónico para Exportaciones"}
        ],
        else: [
          {"E41", "E41 Comprobante Electrónico de Compras"},
          {"E43", "E43 Comprobante Electrónico para Gastos Menores"},
          {"E47", "E47 Comprobante Electrónico para Pagos al Exterior"}
        ]

    {selection_ids, _seq} =
      Enum.map_reduce(options, 1, fn {value, name}, sequence ->
        vals = %{
          field_id: field_id,
          value: value,
          name: name,
          sequence: sequence
        }

        selection_id =
          execute_kw!(
            client,
            uid,
            "ir.model.fields.selection",
            "create",
            [vals]
          )

        {selection_id, sequence + 1}
      end)

    IO.puts("Created selection rows: #{inspect(selection_ids)}")
    selection_ids
  end

  @doc """
  Get the base account.move main form view (non-inherited).
  """
  @spec get_account_move_main_form_view(t(), integer()) :: map()
  def get_account_move_main_form_view(%__MODULE__{} = client, uid) do
    domain = [
      ["model", "=", "account.move"],
      ["type", "=", "form"],
      ["inherit_id", "=", false]
    ]

    views =
      execute_kw!(
        client,
        uid,
        "ir.ui.view",
        "search_read",
        [domain],
        %{fields: ["id", "name"], limit: 1}
      )

    case views do
      [view | _] -> view
      [] -> raise "Base account.move form view not found"
    end
  end

  @doc """
  Create an inherited view that injects x_studio_e_doc into account.move form.
  """
  @spec create_edoc_view_inheritance(t(), integer(), String.t()) :: integer()
  def create_edoc_view_inheritance(
        %__MODULE__{} = client,
        uid,
        name \\ "account_move_form_edoc_fields"
      ) do
    base_view = get_account_move_main_form_view(client, uid)
    inherit_id = base_view["id"]

    arch = """
    <data>
        <xpath expr="//form[1]/sheet[1]/notebook[1]/page[@name='other_info']/group[1]/group[@name='sale_info_group']/label[1]" position="before">
            <field
                name="x_studio_e_doc_inv"
                help="Identificador del tipo de e-DOC requerido para factura electronica."
                invisible="move_type not in ('out_invoice', 'out_refund', 'out_receipt')"
                readonly="state in ['posted', 'cancel']"
                style="font-weight:bold;"
              />
        </xpath>

        <xpath expr="//form[1]/sheet[1]/notebook[1]/page[@name='other_info']/group[1]/group[@name='accounting_info_group']/field[@name='company_id']" position="after">
          <field
                name="x_studio_e_doc_bill"
                help="Identificadorde Gastos del tipo de e-DOC requerido para factura electrónica."
                invisible="move_type not in ('in_invoice', 'in_refund', 'in_receipt')"
                readonly="state in ['posted', 'cancel']"
                style="font-weight:bold;"
            />
        </xpath>
    </data>
    """

    # <data>
    #   <xpath expr="//form[1]/sheet[1]/notebook[1]/page[@name='other_info']/group[1]/group[@name='sale_info_group']/label[1]" position="before">
    #     <field name="x_studio_field_invoice" help="This is a field in the invoice"/>
    #   </xpath>
    #   <xpath expr="//form[1]/sheet[1]/notebook[1]/page[@name='other_info']/group[1]/group[@name='accounting_info_group']/field[@name='company_id']" position="after">
    #     <field name="x_studio_field_bill" help="This is the help for field bill"/>
    #   </xpath>
    # </data>

    vals = %{
      name: name,
      model: "account.move",
      type: "form",
      inherit_id: inherit_id,
      arch_base: arch
    }

    view_id = execute_kw!(client, uid, "ir.ui.view", "create", [vals])
    IO.puts("Created inherited view id: #{view_id}")
    view_id
  end

  @doc """
  Inspect the inherited view that injects x_studio_e_doc into account.move.
  """
  @spec get_edoc_view_inheritance(t(), integer(), integer() | nil) :: map() | nil
  def get_edoc_view_inheritance(%__MODULE__{} = client, uid, name, view_id \\ nil) do
    domain =
      if view_id do
        [["id", "=", view_id]]
      else
        [
          ["name", "=", name],
          ["model", "=", "account.move"]
        ]
      end

    views =
      execute_kw!(
        client,
        uid,
        "ir.ui.view",
        "search_read",
        [domain],
        %{
          fields: [
            "id",
            "name",
            "model",
            "inherit_id",
            "active",
            "arch_base",
            "arch_db"
          ],
          limit: 1
        }
      )

    case views do
      [] ->
        IO.puts("No edoc inherited view found for domain: #{inspect(domain)}")
        nil

      [view | _] ->
        IO.puts("######## #{name} ########")

        view
        |> Enum.each(fn
          {"arch_base", val} ->
            IO.puts("\n--- arch_base ---")
            IO.puts(val)

          {"arch_db", val} ->
            IO.puts("\n--- arch_db ---")
            IO.puts(val)

          {key, val} ->
            IO.puts("#{key}: #{inspect(val)}")
        end)

        view
    end
  end

  @doc """
  Retrieve invoice (account.move) data by ID, plus its move lines.
  """
  @spec get_invoice_data(
          t(),
          integer(),
          integer(),
          list(String.t()) | nil,
          list(String.t()) | nil
        ) :: %{invoice: map(), lines: list(map())} | nil
  def get_invoice_data(
        %__MODULE__{} = client,
        uid,
        invoice_id,
        invoice_fields \\ nil,
        line_fields \\ nil
      ) do
    invoice_fields =
      invoice_fields ||
        [
          "id",
          "name",
          "move_type",
          "state",
          "partner_id",
          "invoice_date",
          "invoice_date_due",
          "amount_untaxed",
          "amount_tax",
          "amount_total",
          "currency_id",
          "payment_state",
          "invoice_origin",
          "ref"
        ]

    invoices =
      execute_kw!(
        client,
        uid,
        "account.move",
        "read",
        [[invoice_id]],
        %{fields: invoice_fields}
      )

    case invoices do
      [] ->
        nil

      [invoice | _] ->
        line_fields =
          line_fields ||
            [
              "id",
              "name",
              "account_id",
              "product_id",
              "quantity",
              "price_unit",
              "discount",
              "price_subtotal",
              "debit",
              "credit",
              "tax_ids"
            ]

        lines =
          execute_kw!(
            client,
            uid,
            "account.move.line",
            "search_read",
            [[["move_id", "=", invoice_id]]],
            %{fields: line_fields}
          )

        %{invoice: invoice, lines: lines}
    end
  end

  @doc """
  Append a string to the invoice 'name' and 'payment_reference' fields.
  """
  @spec append_to_invoice_name(
          t(),
          integer(),
          integer(),
          String.t(),
          String.t()
        ) :: String.t()
  def append_to_invoice_name(
        %__MODULE__{} = client,
        uid,
        invoice_id,
        extra_text,
        sep \\ " "
      ) do
    records =
      execute_kw!(
        client,
        uid,
        "account.move",
        "read",
        [[invoice_id]],
        %{fields: ["name", "payment_reference"]}
      )

    case records do
      [] ->
        raise "Invoice (account.move) id #{invoice_id} not found"

      [record | _] ->
        current_name = "" #Map.get(record, "name") || ""
        current_reference = "" # Map.get(record, "payment_reference") || ""

        new_name =
          if current_name != "" do
            current_name <> sep <> extra_text
          else
            extra_text
          end

        new_reference =
          if current_reference != "" do
            current_reference <> sep <> extra_text
          else
            extra_text
          end

        _ =
          execute_kw!(
            client,
            uid,
            "account.move",
            "write",
            # [[invoice_id], %{name: new_name, payment_reference: new_reference}]
            [[invoice_id], %{ref: new_reference}]
          )

        IO.puts(
          "Updated invoice #{invoice_id} name: #{inspect(current_name)} -> #{inspect(new_name)}"
        )

        new_name
    end
  end
end
