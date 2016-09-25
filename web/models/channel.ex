defmodule Ask.Channel do
  use Ask.Web, :model

  schema "channels" do
    field :name, :string
    field :type, :string
    field :provider, :string
    field :settings, :map
    belongs_to :user, Ask.User

    timestamps()
  end

  @doc """
  Returns a new instance of the runtime channel implementation (Ask.Runtime.Channel)
  """
  def runtime_channel(channel) do
    provider(channel.provider).new(channel.settings)
  end

  @doc """
  Returns the runtime chanel provider (module) by name
  """
  def provider(name) do
    channel_config = Application.get_env(:ask, :channel)
    channel_config[:providers][name]
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:name, :type, :provider, :settings, :user_id])
    |> validate_required([:name, :type, :provider, :settings, :user_id])
    |> assoc_constraint(:user)
  end
end
