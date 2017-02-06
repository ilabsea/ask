defmodule Ask.RespondentDispositionHistory do
  use Ask.Web, :model

  schema "respondent_disposition_history" do
    field :disposition, :string
    belongs_to :respondent, Ask.Respondent

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:disposition])
    |> validate_required([:disposition])
  end
end
