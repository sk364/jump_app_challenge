defmodule SocialScribe.ChatFixtures do
  @moduledoc """
  Test fixtures for the Chat context.
  """

  alias SocialScribe.Chat

  def conversation_fixture(attrs \\ %{}) do
    user = attrs[:user] || SocialScribe.AccountsFixtures.user_fixture()

    {:ok, conversation} =
      Chat.create_conversation(%{
        title: attrs[:title] || "Test Conversation",
        user_id: user.id
      })

    conversation
  end

  def message_fixture(attrs \\ %{}) do
    conversation =
      attrs[:conversation] || conversation_fixture(user: attrs[:user])

    {:ok, message} =
      Chat.create_message(%{
        role: attrs[:role] || "user",
        content: attrs[:content] || "Test message content",
        conversation_id: conversation.id,
        metadata: attrs[:metadata] || %{}
      })

    message
  end
end
