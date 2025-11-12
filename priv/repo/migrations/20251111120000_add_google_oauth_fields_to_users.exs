defmodule Edoc.Repo.Migrations.AddGoogleOauthFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :google_uid, :string
      add :google_picture_url, :string
      add :google_access_token, :string
      add :google_refresh_token, :string
      add :google_token_expires_at, :utc_datetime
      add :google_scope, :string
    end

    create unique_index(:users, [:google_uid])
  end
end

