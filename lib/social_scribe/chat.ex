defmodule SocialScribe.Chat do
  @moduledoc """
  The Chat context for managing conversations and messages.
  """

  import Ecto.Query, warn: false
  alias SocialScribe.Repo

  alias SocialScribe.Chat.Conversation
  alias SocialScribe.Chat.Message

  def list_user_conversations(user_id) do
    Conversation
    |> where(user_id: ^user_id)
    |> order_by(desc: :updated_at)
    |> Repo.all()
  end

  def get_conversation!(id), do: Repo.get!(Conversation, id)

  def get_conversation_with_messages(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload(messages: from(m in Message, order_by: [asc: m.inserted_at]))
  end

  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  def create_message(attrs) do
    result =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:message, Message.changeset(%Message{}, attrs))
      |> Ecto.Multi.update_all(
        :touch_conversation,
        fn %{message: message} ->
          from(c in Conversation,
            where: c.id == ^message.conversation_id,
            update: [set: [updated_at: ^DateTime.utc_now(:second)]]
          )
        end,
        []
      )
      |> Repo.transaction()

    case result do
      {:ok, %{message: message}} -> {:ok, message}
      {:error, :message, changeset, _} -> {:error, changeset}
    end
  end

  def list_conversation_messages(conversation_id) do
    Message
    |> where(conversation_id: ^conversation_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_or_create_active_conversation(user_id) do
    case list_user_conversations(user_id) do
      [conversation | _] -> {:ok, conversation}
      [] -> create_conversation(%{user_id: user_id})
    end
  end
end
