defmodule SocialScribeWeb.LiveHooks.ChatHook do
  @moduledoc """
  LiveView hook that handles async chat operations.
  Intercepts chat-related messages so individual LiveViews don't need their own handlers.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias SocialScribe.Accounts
  alias SocialScribe.Chat
  alias SocialScribe.Chat.ContactSearch
  alias SocialScribe.Chat.ContextBuilder
  alias SocialScribe.Chat.CrmActionHandler
  alias SocialScribe.AIContentGeneratorApi

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      user = socket.assigns.current_user
      {:ok, conversation} = Chat.get_or_create_active_conversation(user.id)
      messages = Chat.list_conversation_messages(conversation.id)

      connected_crms = get_connected_crms(user.id)

      socket =
        socket
        |> assign(:chat_conversation, conversation)
        |> assign(:chat_messages, messages)
        |> assign(:chat_connected_crms, connected_crms)
        |> attach_hook(:chat_handler, :handle_info, &handle_chat_info/2)

      {:cont, socket}
    else
      socket =
        socket
        |> assign(:chat_conversation, nil)
        |> assign(:chat_messages, [])
        |> assign(:chat_connected_crms, [])

      {:cont, socket}
    end
  end

  defp handle_chat_info({:generate_chat_response, conversation_id, user}, socket) do
    Task.start(fn ->
      messages = Chat.list_conversation_messages(conversation_id)
      mentioned_contacts = extract_mentioned_contacts(messages)
      system_prompt = ContextBuilder.build_system_prompt(user, mentioned_contacts)

      case AIContentGeneratorApi.chat_response(messages, %{system_prompt: system_prompt}) do
        {:ok, response} ->
          {:ok, assistant_msg} =
            Chat.create_message(%{
              role: "assistant",
              content: response,
              conversation_id: conversation_id,
              metadata: %{}
            })

          send(socket.root_pid, {:chat_response_received, assistant_msg})

        {:error, _reason} ->
          {:ok, error_msg} =
            Chat.create_message(%{
              role: "assistant",
              content: "I'm sorry, I encountered an error processing your request. Please try again.",
              conversation_id: conversation_id,
              metadata: %{error: true}
            })

          send(socket.root_pid, {:chat_response_received, error_msg})
      end
    end)

    {:halt, socket}
  end

  defp handle_chat_info({:chat_contact_search, query, user}, socket) do
    Task.start(fn ->
      {:ok, results} = ContactSearch.search(user, query)
      send(socket.root_pid, {:chat_contact_results, results})
    end)

    {:halt, socket}
  end

  defp handle_chat_info({:execute_crm_action, action, user}, socket) do
    Task.start(fn ->
      case CrmActionHandler.execute_action(action, user) do
        {:ok, _} ->
          send(socket.root_pid, {:crm_action_result, :ok, action})

        {:error, reason} ->
          send(socket.root_pid, {:crm_action_result, :error, reason})
      end
    end)

    {:halt, socket}
  end

  defp handle_chat_info({:chat_response_received, message}, socket) do
    Phoenix.LiveView.send_update(
      SocialScribeWeb.ChatLive.ChatPanelComponent,
      id: "ask-anything-panel",
      chat_response: message
    )

    {:halt, socket}
  end

  defp handle_chat_info({:chat_contact_results, results}, socket) do
    Phoenix.LiveView.send_update(
      SocialScribeWeb.ChatLive.ChatPanelComponent,
      id: "ask-anything-panel",
      contact_results: results
    )

    {:halt, socket}
  end

  defp handle_chat_info({:crm_action_result, status, data}, socket) do
    Phoenix.LiveView.send_update(
      SocialScribeWeb.ChatLive.ChatPanelComponent,
      id: "ask-anything-panel",
      crm_action_result: {status, data}
    )

    {:halt, socket}
  end

  defp handle_chat_info(_msg, socket), do: {:cont, socket}

  defp extract_mentioned_contacts(messages) do
    messages
    |> Enum.flat_map(fn msg ->
      case msg.metadata do
        %{"mentioned_contacts" => contacts} when is_list(contacts) -> contacts
        _ -> []
      end
    end)
    |> Enum.uniq_by(& &1["id"])
  end

  defp get_connected_crms(user_id) do
    crms = []
    crms = if Accounts.get_user_hubspot_credential(user_id), do: [:hubspot | crms], else: crms
    crms = if Accounts.get_user_salesforce_credential(user_id), do: [:salesforce | crms], else: crms
    Enum.reverse(crms)
  end
end
