defmodule SocialScribe.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Accounts.User
  alias SocialScribe.Chat.Message

  schema "conversations" do
    field :title, :string, default: "New Chat"

    belongs_to :user, User
    has_many :messages, Message

    timestamps(type: :utc_datetime)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :user_id])
    |> validate_required([:user_id])
  end
end
