defmodule SocialScribeWeb.ChatLive.ChatPanelComponent do
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ChatLive.MessageComponents

  alias SocialScribe.Chat
  alias SocialScribe.Chat.CrmActionHandler

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       panel_open: false,
       active_tab: :chat,
       message_input: "",
       mention_query: nil,
       mention_results: [],
       mentioned_contacts: [],
       sending: false,
       pending_action: nil,
       conversations_list: []
     )}
  end

  @impl true
  def update(%{chat_response: message}, socket) do
    messages = socket.assigns.messages ++ [message]

    action =
      case CrmActionHandler.parse_action(message.content) do
        {:ok, action} -> action
        :no_action -> nil
      end

    {:ok,
     socket
     |> assign(:messages, messages)
     |> assign(:sending, false)
     |> assign(:pending_action, action)}
  end

  def update(%{contact_results: results}, socket) do
    {:ok, assign(socket, :mention_results, results)}
  end

  def update(%{crm_action_result: {status, _data}}, socket) do
    content =
      case status do
        :ok -> "Done! The contact has been updated successfully."
        :error -> "Sorry, I wasn't able to complete that update. Please try again."
      end

    {:ok, msg} =
      Chat.create_message(%{
        role: "assistant",
        content: content,
        conversation_id: socket.assigns.conversation.id,
        metadata: %{crm_action_result: status}
      })

    {:ok,
     socket
     |> assign(:messages, socket.assigns.messages ++ [msg])
     |> assign(:pending_action, nil)}
  end

  def update(assigns, socket) do
    conversation = assigns[:chat_conversation] || socket.assigns[:conversation]
    messages = assigns[:chat_messages] || socket.assigns[:messages] || []

    {:ok,
     socket
     |> assign(:current_user, assigns.current_user)
     |> assign(:conversation, conversation)
     |> assign(:messages, messages)
     |> assign(:connected_crms, assigns[:connected_crms] || socket.assigns[:connected_crms] || [])
     |> assign(:id, assigns.id)}
  end

  @impl true
  def handle_event("toggle_panel", _, socket) do
    open = !socket.assigns.panel_open

    socket =
      if open and socket.assigns.active_tab == :history do
        conversations = Chat.list_user_conversations(socket.assigns.current_user.id)
        assign(socket, :conversations_list, conversations)
      else
        socket
      end

    {:noreply, assign(socket, :panel_open, open)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)

    socket =
      if tab == :history do
        conversations = Chat.list_user_conversations(socket.assigns.current_user.id)
        assign(socket, :conversations_list, conversations)
      else
        socket
      end

    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event("new_chat", _, socket) do
    {:ok, conversation} = Chat.create_conversation(%{user_id: socket.assigns.current_user.id})

    {:noreply,
     socket
     |> assign(:conversation, conversation)
     |> assign(:messages, [])
     |> assign(:active_tab, :chat)
     |> assign(:pending_action, nil)}
  end

  def handle_event("select_conversation", %{"id" => id}, socket) do
    conversation = Chat.get_conversation_with_messages(id)

    {:noreply,
     socket
     |> assign(:conversation, conversation)
     |> assign(:messages, conversation.messages)
     |> assign(:active_tab, :chat)
     |> assign(:pending_action, nil)}
  end

  def handle_event("send_message", %{"message" => content}, socket) when content != "" do
    mentioned = socket.assigns.mentioned_contacts

    metadata =
      if mentioned != [] do
        %{"mentioned_contacts" => Enum.map(mentioned, &to_plain_map/1)}
      else
        %{}
      end

    {:ok, user_msg} =
      Chat.create_message(%{
        role: "user",
        content: content,
        conversation_id: socket.assigns.conversation.id,
        metadata: metadata
      })

    send(self(), {:generate_chat_response, socket.assigns.conversation.id, socket.assigns.current_user})

    {:noreply,
     socket
     |> assign(:messages, socket.assigns.messages ++ [user_msg])
     |> assign(:message_input, "")
     |> assign(:mentioned_contacts, [])
     |> assign(:mention_query, nil)
     |> assign(:mention_results, [])
     |> assign(:sending, true)}
  end

  def handle_event("send_message", _, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"value" => value}, socket) do
    mention_query = detect_mention(value)

    socket =
      if mention_query && String.length(mention_query) >= 2 do
        send(self(), {:chat_contact_search, mention_query, socket.assigns.current_user})
        assign(socket, :mention_query, mention_query)
      else
        socket
        |> assign(:mention_query, nil)
        |> assign(:mention_results, [])
      end

    {:noreply, assign(socket, :message_input, value)}
  end

  def handle_event("select_mention", params, socket) do
    contact = %{
      id: params["id"],
      name: params["name"],
      provider: params["provider"],
      email: params["email"]
    }

    input = socket.assigns.message_input
    new_input = replace_mention(input, "@#{socket.assigns.mention_query}", "@#{contact.name} ")

    {:noreply,
     socket
     |> assign(:mentioned_contacts, socket.assigns.mentioned_contacts ++ [contact])
     |> assign(:message_input, new_input)
     |> assign(:mention_query, nil)
     |> assign(:mention_results, [])}
  end

  def handle_event("confirm_crm_action", _, socket) do
    action = socket.assigns.pending_action

    if action do
      send(self(), {:execute_crm_action, action, socket.assigns.current_user})
    end

    {:noreply, assign(socket, :pending_action, nil)}
  end

  def handle_event("cancel_crm_action", _, socket) do
    {:ok, msg} =
      Chat.create_message(%{
        role: "assistant",
        content: "No problem, the update has been cancelled.",
        conversation_id: socket.assigns.conversation.id,
        metadata: %{}
      })

    {:noreply,
     socket
     |> assign(:messages, socket.assigns.messages ++ [msg])
     |> assign(:pending_action, nil)}
  end

  def handle_event("delete_conversation", %{"id" => id}, socket) do
    conversation = Chat.get_conversation!(id)
    Chat.delete_conversation(conversation)

    conversations = Chat.list_user_conversations(socket.assigns.current_user.id)

    socket =
      if socket.assigns.conversation && socket.assigns.conversation.id == String.to_integer(id) do
        case conversations do
          [first | _] ->
            loaded = Chat.get_conversation_with_messages(first.id)

            socket
            |> assign(:conversation, loaded)
            |> assign(:messages, loaded.messages)

          [] ->
            {:ok, new_conv} = Chat.create_conversation(%{user_id: socket.assigns.current_user.id})
            assign(socket, conversation: new_conv, messages: [])
        end
      else
        socket
      end

    {:noreply, assign(socket, :conversations_list, conversations)}
  end

  def handle_event("keydown", %{"key" => "Enter", "shiftKey" => false}, socket) do
    if socket.assigns.message_input != "" do
      handle_event("send_message", %{"message" => socket.assigns.message_input}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("keydown", _, socket), do: {:noreply, socket}

  defp detect_mention(text) do
    case Regex.run(~r/@(\w*)$/, text) do
      [_, query] -> query
      _ -> nil
    end
  end

  defp replace_mention(text, old, new) do
    case String.split(text, old, parts: 2) do
      [before, _after] -> before <> new
      _ -> text
    end
  end

  defp to_plain_map(%{__struct__: _} = struct) do
    struct |> Map.from_struct() |> stringify_keys()
  end

  defp to_plain_map(map) when is_map(map), do: stringify_keys(map)

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp all_mentioned_contacts(messages) do
    messages
    |> Enum.flat_map(fn msg ->
      case msg.metadata do
        %{"mentioned_contacts" => contacts} when is_list(contacts) -> contacts
        _ -> []
      end
    end)
    |> Enum.uniq_by(& &1["id"])
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
