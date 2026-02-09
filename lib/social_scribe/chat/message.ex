defmodule SocialScribe.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Chat.Conversation

  @roles ~w(user assistant system)

  schema "chat_messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :conversation, Conversation

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :metadata, :conversation_id])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, @roles)
  end
end
