defmodule Edoc.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Edoc.Repo

  alias Edoc.Accounts.{User, UserToken, UserNotifier}
  alias Edoc.Accounts.Company
  alias Edoc.Accounts.Scope
  alias Ecto.Changeset
  alias Edoc.TenantContext
  alias Edoc.Transaction

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Edoc.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Edoc.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Tenant settings

  @doc """
  Returns a changeset for changing the user's tenant.
  """
  def change_user_tenant(user, attrs \\ %{}) do
    User.tenant_changeset(user, attrs)
  end

  @doc """
  Updates the user's tenant.
  """
  def update_user_tenant(user, attrs) do
    user
    |> User.tenant_changeset(attrs)
    |> Repo.update()
  end

  ## Google OAuth

  @doc """
  Upserts a user from Google OAuth userinfo and token map.

  Expected user_info keys: "sub" (google uid), "email", "name", "picture".
  Expected token map keys: "access_token", optionally "refresh_token", "expires_in", and "scope".

  This function ensures the user has a tenant (derived from email domain) and is confirmed.
  """
  def upsert_user_from_google(user_info, token_map)
      when is_map(user_info) and is_map(token_map) do
    google_uid = user_info["sub"] || user_info["id"]
    email = user_info["email"]
    name = user_info["name"] || email
    picture = user_info["picture"]

    # derive tenant from email domain, fallback to "public"
    tenant =
      case String.split(email || "", "@") do
        [_local, domain] when is_binary(domain) and byte_size(domain) > 0 -> domain
        _ -> "public"
      end

    expires_at =
      case token_map["expires_in"] do
        n when is_integer(n) ->
          DateTime.add(DateTime.utc_now(:second), n, :second)

        n when is_binary(n) ->
          case Integer.parse(n) do
            {int, _} -> DateTime.add(DateTime.utc_now(:second), int, :second)
            :error -> nil
          end

        _ ->
          nil
      end

    attrs = %{
      email: email,
      name: name,
      tenant: tenant,
      google_uid: google_uid,
      google_picture_url: picture,
      google_access_token: token_map["access_token"],
      google_refresh_token: token_map["refresh_token"],
      google_token_expires_at: expires_at,
      google_scope: token_map["scope"],
      confirmed_at: DateTime.utc_now(:second)
    }

    Repo.transact(fn ->
      user =
        Repo.get_by(User, google_uid: google_uid) || Repo.get_by(User, email: email) || %User{}

      case (user.__struct__ == User && user.id && :update) || :insert do
        :update -> Repo.update(User.google_oauth_changeset(user, attrs))
        :insert -> Repo.insert(User.google_oauth_changeset(user, attrs))
      end
    end)
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  ## Companies (multi-tenant)

  @doc """
  Returns an Ecto changeset for a new company.
  """
  def change_company(company \\ %Company{}, attrs \\ %{}) do
    Company.changeset(company, attrs)
  end

  @doc """
  Creates a company in the current tenant, associating it to the current user.

  Always pass the current_scope as the first argument to respect authorization
  and scoping rules. The insert is executed with the tenant prefix.
  """
  def create_company(%Scope{user: %User{} = user}, attrs) when is_map(attrs) do
    tenant = TenantContext.get_tenant()
    IO.inspect(tenant, label: "Company tenant? ")

    %Company{}
    |> Company.changeset(attrs)
    |> Changeset.put_assoc(:users, [user])
    |> Repo.insert(prefix: tenant)
  end

  def create_company(_scope, _attrs), do: {:error, :unauthorized}

  @doc """
  Lists companies for the current user in the current tenant.
  """
  def list_companies(%Scope{user: %User{} = user}) do
    tenant = TenantContext.get_tenant()

    user
    |> Ecto.assoc(:company)
    |> Repo.all(prefix: tenant)
  end

  def list_companies(_), do: []

  @doc """
  Gets a single company by id in the current tenant.
  """
  def get_company!(id) do
    tenant = TenantContext.get_tenant()
    Repo.get!(Company, id, prefix: tenant)
  end

  @doc """
  Gets a company that belongs to the given scope's user in the current tenant.

  Raises if the company is not found or not accessible to the scope.
  """
  def get_company_for_scope!(%Scope{user: %User{} = user}, company_id) do
    tenant = TenantContext.get_tenant()

    user
    |> Ecto.assoc(:company)
    |> where([c], c.id == ^company_id)
    |> Repo.one!(prefix: tenant)
  end

  def get_company_for_scope!(_, _), do: raise(Ecto.NoResultsError, queryable: Company)

  @doc """
  Lists transactions for a company that belongs to the given scope.
  """
  def list_company_transactions(%Scope{} = _scope, %Company{} = company) do
    tenant = TenantContext.get_tenant()

    Transaction
    |> where(company_id: ^company.id)
    |> order_by(desc: :inserted_at)
    |> Repo.all(prefix: tenant)
  end

  def list_company_transactions(%Scope{} = scope, company_id) when is_binary(company_id) do
    company = get_company_for_scope!(scope, company_id)
    list_company_transactions(scope, company)
  end

  def list_company_transactions(_, _), do: []

  @doc """
  Placeholder connect action for a company.
  """
  def connect_company(%Scope{user: %User{}}, %Company{} = _company) do
    {:ok, :placeholder}
  end

  def connect_company(_, _), do: {:error, :unauthorized}

  @doc """
  Mark a company's `connected` flag. Requires a valid current scope.

  Uses the current tenant prefix from `TenantContext`.
  """
  def mark_company_connected(%Scope{user: %User{}}, %Company{} = company, connected \\ true) do
    tenant = TenantContext.get_tenant()

    company
    |> Changeset.change(%{connected: connected})
    |> Repo.update(prefix: tenant)
  end

  def mark_company_connected(_, _, _), do: {:error, :unauthorized}
end
