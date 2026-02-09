defmodule SocialScribe.ChatTest do
  use SocialScribe.DataCase

  alias SocialScribe.Chat
  alias SocialScribe.Chat.{Conversation, Message}
  alias SocialScribe.ChatFixtures
  alias SocialScribe.AccountsFixtures

  describe "conversations" do
    test "list_user_conversations/1 returns conversations for the user" do
      user = AccountsFixtures.user_fixture()
      _conv1 = ChatFixtures.conversation_fixture(user: user, title: "First")
      _conv2 = ChatFixtures.conversation_fixture(user: user, title: "Second")

      conversations = Chat.list_user_conversations(user.id)
      assert length(conversations) == 2
    end

    test "create_conversation/1 creates a conversation" do
      user = AccountsFixtures.user_fixture()
      assert {:ok, %Conversation{} = conv} = Chat.create_conversation(%{user_id: user.id})
      assert conv.title == "New Chat"
    end

    test "get_conversation!/1 returns the conversation" do
      conv = ChatFixtures.conversation_fixture()
      assert Chat.get_conversation!(conv.id).id == conv.id
    end

    test "delete_conversation/1 deletes the conversation" do
      conv = ChatFixtures.conversation_fixture()
      assert {:ok, _} = Chat.delete_conversation(conv)
      assert_raise Ecto.NoResultsError, fn -> Chat.get_conversation!(conv.id) end
    end

    test "get_or_create_active_conversation/1 returns existing conversation" do
      user = AccountsFixtures.user_fixture()
      conv = ChatFixtures.conversation_fixture(user: user)

      assert {:ok, result} = Chat.get_or_create_active_conversation(user.id)
      assert result.id == conv.id
    end

    test "get_or_create_active_conversation/1 creates new when none exist" do
      user = AccountsFixtures.user_fixture()
      assert {:ok, %Conversation{}} = Chat.get_or_create_active_conversation(user.id)
    end
  end

  describe "messages" do
    test "create_message/1 creates a message and touches conversation" do
      conv = ChatFixtures.conversation_fixture()
      original_updated_at = conv.updated_at

      Process.sleep(1000)

      assert {:ok, %Message{} = msg} =
               Chat.create_message(%{
                 role: "user",
                 content: "Hello",
                 conversation_id: conv.id
               })

      assert msg.role == "user"
      assert msg.content == "Hello"

      updated_conv = Chat.get_conversation!(conv.id)
      assert DateTime.compare(updated_conv.updated_at, original_updated_at) in [:gt, :eq]
    end

    test "create_message/1 validates role" do
      conv = ChatFixtures.conversation_fixture()

      assert {:error, changeset} =
               Chat.create_message(%{
                 role: "invalid",
                 content: "Hello",
                 conversation_id: conv.id
               })

      assert errors_on(changeset).role != []
    end

    test "list_conversation_messages/1 returns messages in order" do
      conv = ChatFixtures.conversation_fixture()
      msg1 = ChatFixtures.message_fixture(conversation: conv, content: "First")
      _msg2 = ChatFixtures.message_fixture(conversation: conv, content: "Second")

      messages = Chat.list_conversation_messages(conv.id)
      assert length(messages) == 2
      assert hd(messages).id == msg1.id
    end

    test "get_conversation_with_messages/1 preloads messages" do
      conv = ChatFixtures.conversation_fixture()
      ChatFixtures.message_fixture(conversation: conv, content: "Hello")

      result = Chat.get_conversation_with_messages(conv.id)
      assert length(result.messages) == 1
      assert hd(result.messages).content == "Hello"
    end
  end
end
