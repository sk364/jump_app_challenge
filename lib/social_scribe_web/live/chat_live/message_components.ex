defmodule SocialScribeWeb.ChatLive.MessageComponents do
  use SocialScribeWeb, :html

  require Logger

  attr :datetime, :any, required: true

  def timestamp_divider(assigns) do
    ~H"""
    <div class="flex items-center gap-3 my-5">
      <div class="flex-1 h-px bg-gray-200"></div>
      <span class="text-xs text-gray-400 whitespace-nowrap">
        {format_timestamp(@datetime)}
      </span>
      <div class="flex-1 h-px bg-gray-200"></div>
    </div>
    """
  end

  attr :message, :map, required: true
  attr :all_mentioned_contacts, :list, default: []

  def chat_message(assigns) do
    cleaned_message = Map.update!(assigns.message, :content, &strip_json_action_block/1)
    assigns = assign(assigns, :content_parts, parse_mentions(cleaned_message, assigns.all_mentioned_contacts))

    ~H"""
    <%= if @message.role == "user" do %>
      <div class="flex justify-end mb-4">
        <div class="max-w-[80%] bg-gray-100 rounded-2xl rounded-br-sm px-4 py-3 text-[15px] leading-relaxed text-gray-900">
          <.rendered_content parts={@content_parts} />
        </div>
      </div>
    <% else %>
      <div class="mb-4">
        <div class="text-[15px] leading-relaxed text-gray-900">
          <.rendered_content parts={@content_parts} />
        </div>
        <.source_badges providers={source_providers(@content_parts)} />
      </div>
    <% end %>
    """
  end

  attr :parts, :list, required: true

  defp rendered_content(assigns) do
    ~H"""
    <span class=""><%= for part <- @parts do %><%= case part do %><% {:text, text} -> %>{text}<% {:mention, name, provider} -> %><.inline_mention name={name} provider={provider} /><% end %><% end %></span>
    """
  end

  attr :name, :string, required: true
  attr :provider, :string, required: true

  defp inline_mention(assigns) do
    assigns = assign(assigns, :initials, get_initials(assigns.name))
    assigns = assign(assigns, :hubspot_svg, hubspot_svg_path())
    assigns = assign(assigns, :salesforce_svg, salesforce_svg_path())

    ~H"""
    <span class="inline-flex items-center align-middle gap-1 rounded-full bg-white py-0.5 pl-0.5 pr-0.5"><span class="relative inline-flex flex-shrink-0" style="width:18px;height:18px"><span class={["inline-flex items-center justify-center rounded-full text-white text-[8px] font-semibold", avatar_color(@name)]} style="width:18px;height:18px">{@initials}</span><span class="absolute flex items-center justify-center rounded-full border border-white bg-white" style="width:11px;height:11px;bottom:-2px;right:-2px"><svg :if={@provider == "hubspot"} style="width:8px;height:8px" viewBox="0 0 24 24" fill="#ff7a59" xmlns="http://www.w3.org/2000/svg"><path d={@hubspot_svg}/></svg><svg :if={@provider == "salesforce"} style="width:8px;height:8px" viewBox="0 0 28 20" fill="#0176D3" xmlns="http://www.w3.org/2000/svg"><path d={@salesforce_svg}/></svg></span></span><span class="font-semibold text-gray-900 text-[13px]">{@name}</span></span>
    """
  end

  attr :name, :string, required: true
  attr :provider, :string, required: true

  def contact_avatar(assigns) do
    assigns = assign(assigns, :initials, get_initials(assigns.name))
    assigns = assign(assigns, :hubspot_svg, hubspot_svg_path())
    assigns = assign(assigns, :salesforce_svg, salesforce_svg_path())

    ~H"""
    <span class="relative inline-flex flex-shrink-0" style="width:24px;height:24px"><span class={["inline-flex items-center justify-center rounded-full text-white text-[10px] font-semibold", avatar_color(@name)]} style="width:24px;height:24px">{@initials}</span><span class="absolute flex items-center justify-center rounded-full border-2 border-white bg-white" style="width:13px;height:13px;bottom:-2px;right:-3px"><svg :if={@provider == "hubspot"} style="width:9px;height:9px" viewBox="0 0 24 24" fill="#ff7a59" xmlns="http://www.w3.org/2000/svg"><path d={@hubspot_svg}/></svg><svg :if={@provider == "salesforce"} style="width:9px;height:9px" viewBox="0 0 28 20" fill="#0176D3" xmlns="http://www.w3.org/2000/svg"><path d={@salesforce_svg}/></svg></span></span>
    """
  end

  attr :providers, :list, default: []

  def source_badges(assigns) do
    assigns = assign(assigns, :hubspot_svg, hubspot_svg_path())
    assigns = assign(assigns, :salesforce_svg, salesforce_svg_path())

    ~H"""
    <div :if={@providers != []} class="flex items-center gap-1.5 mt-2">
      <span class="text-xs text-gray-400">Sources</span>
      <span :for={provider <- @providers} class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-gray-100">
        <svg :if={provider == "hubspot"} style="width:12px;height:12px" viewBox="0 0 24 24" fill="#ff7a59" xmlns="http://www.w3.org/2000/svg"><path d={@hubspot_svg}/></svg>
        <svg :if={provider == "salesforce"} style="width:12px;height:12px" viewBox="0 0 28 20" fill="#0176D3" xmlns="http://www.w3.org/2000/svg"><path d={@salesforce_svg}/></svg>
      </span>
    </div>
    """
  end

  def typing_indicator(assigns) do
    ~H"""
    <div class="mb-4">
      <div class="flex gap-1.5 py-2">
        <span class="w-2 h-2 bg-gray-300 rounded-full animate-bounce [animation-delay:0ms]"></span>
        <span class="w-2 h-2 bg-gray-300 rounded-full animate-bounce [animation-delay:150ms]"></span>
        <span class="w-2 h-2 bg-gray-300 rounded-full animate-bounce [animation-delay:300ms]"></span>
      </div>
    </div>
    """
  end

  attr :contacts, :list, required: true
  attr :target, :any, required: true

  def mention_dropdown(assigns) do
    ~H"""
    <div
      :if={@contacts != []}
      class="absolute bottom-full left-0 right-0 mb-1 bg-white rounded-lg shadow-lg border border-gray-200 max-h-48 overflow-y-auto z-50"
    >
      <button
        :for={contact <- @contacts}
        type="button"
        phx-click="select_mention"
        phx-value-id={contact.id}
        phx-value-name={contact.display_name}
        phx-value-provider={contact.provider}
        phx-value-email={contact.email}
        phx-target={@target}
        class="w-full px-3 py-2 text-left hover:bg-gray-50 flex items-center gap-2 text-sm"
      >
        <.contact_avatar name={contact.display_name || ""} provider={contact.provider} />
        <span class="font-medium truncate">{contact.display_name}</span>
        <span :if={contact.email} class="text-gray-400 text-xs truncate">{contact.email}</span>
        <span class="text-gray-300 text-xs ml-auto capitalize">{contact.provider}</span>
      </button>
    </div>
    """
  end

  attr :action, :map, required: true
  attr :target, :any, required: true

  def crm_action_buttons(assigns) do
    ~H"""
    <div class="flex items-center gap-2 mt-2 p-3 bg-amber-50 rounded-lg border border-amber-200">
      <span class="text-sm text-amber-700 flex-1">Confirm CRM update?</span>
      <button
        phx-click="confirm_crm_action"
        phx-target={@target}
        class="px-3 py-1.5 text-xs font-medium bg-indigo-600 text-white rounded-md hover:bg-indigo-700"
      >
        Confirm
      </button>
      <button
        phx-click="cancel_crm_action"
        phx-target={@target}
        class="px-3 py-1.5 text-xs font-medium bg-gray-200 text-gray-700 rounded-md hover:bg-gray-300"
      >
        Cancel
      </button>
    </div>
    """
  end

  # Parses message content and splits it into text and mention parts.
  # For user messages: matches @Name using the message's own metadata.
  # For assistant messages: matches bare Name using all conversation contacts.
  defp parse_mentions(%{role: "user", content: content, metadata: %{"mentioned_contacts" => contacts}}, _all_contacts)
       when is_list(contacts) and contacts != [] do
    contact_map = build_contact_map(contacts)
    names = sorted_names(contact_map)
    dbg()

    case names do
      [] -> [{:text, content}]
      _ ->
        escaped = Enum.map(names, &Regex.escape/1)
        pattern = Regex.compile!("(@(?:#{Enum.join(escaped, "|")}))")
        split_with_pattern(content, pattern, contact_map, :with_at)
    end
  end

  defp parse_mentions(%{role: "assistant", content: content}, all_contacts)
       when is_list(all_contacts) and all_contacts != [] do
    contact_map = build_contact_map(all_contacts)
    names = sorted_names(contact_map)

    case names do
      [] -> [{:text, content}]
      _ ->
        escaped = Enum.map(names, &Regex.escape/1)
        # Match bare name (word boundary via lookahead/lookbehind not available, use capture group)
        pattern = Regex.compile!("((?:@)?(?:#{Enum.join(escaped, "|")}))")
        split_with_pattern(content, pattern, contact_map, :optional_at)
    end
  end

  defp parse_mentions(%{content: content}, _all_contacts), do: [{:text, content}]

  defp build_contact_map(contacts) do
    contacts
    |> Enum.map(fn c -> {c["name"], c["provider"]} end)
    |> Enum.reject(fn {name, _} -> is_nil(name) end)
    |> Map.new()
  end

  defp sorted_names(contact_map) do
    contact_map |> Map.keys() |> Enum.sort_by(&(-String.length(&1)))
  end

  defp split_with_pattern(content, pattern, contact_map, mode) do
    Regex.split(pattern, content, include_captures: true)
    |> Enum.map(fn part ->
      # Strip leading @ if present to get the bare name
      bare = String.replace_prefix(part, "@", "")

      if Map.has_key?(contact_map, bare) do
        provider = Map.get(contact_map, bare, "hubspot")
        {:mention, bare, provider}
      else
        case mode do
          :with_at ->
            # For user messages, also try with the @ still on
            {:text, part}

          :optional_at ->
            {:text, part}
        end
      end
    end)
  end

  defp strip_json_action_block(content) when is_binary(content) do
    content
    |> String.replace(~r/```json\s*\{[^`]*"action"\s*:\s*"update_contact"[^`]*\}\s*```/, "")
    |> String.trim_trailing()
  end

  defp strip_json_action_block(content), do: content

  defp source_providers(content_parts) do
    content_parts
    |> Enum.flat_map(fn
      {:mention, _name, provider} when is_binary(provider) -> [provider]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%I:%M%P – %B %d, %Y")
  end

  defp get_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp get_initials(_), do: "?"

  # Deterministic color based on name hash for consistent avatars
  @avatar_colors ~w(
    bg-rose-500 bg-pink-500 bg-fuchsia-500 bg-purple-500 bg-violet-500
    bg-indigo-500 bg-sky-500 bg-cyan-500 bg-teal-500 bg-emerald-500
  )

  defp avatar_color(name) when is_binary(name) do
    index = :erlang.phash2(name, length(@avatar_colors))
    Enum.at(@avatar_colors, index)
  end

  defp avatar_color(_), do: "bg-gray-500"

  defp hubspot_svg_path do
    "M18.164 7.93V5.084a2.198 2.198 0 001.267-1.984v-.066A2.2 2.2 0 0017.231.834h-.066a2.2 2.2 0 00-2.2 2.2v.066c0 .873.517 1.626 1.267 1.984V7.93a6.152 6.152 0 00-3.267 1.643l-6.6-5.133a2.726 2.726 0 00.067-.582A2.726 2.726 0 003.706 1.13a2.726 2.726 0 00-2.726 2.727 2.726 2.726 0 002.726 2.727c.483 0 .938-.126 1.333-.347l6.486 5.047a6.195 6.195 0 00-.556 2.572 6.18 6.18 0 00.56 2.572l-1.57 1.223a2.457 2.457 0 00-1.49-.504 2.468 2.468 0 00-2.468 2.468 2.468 2.468 0 002.468 2.468 2.468 2.468 0 002.468-2.468c0-.29-.05-.568-.142-.826l1.558-1.213a6.2 6.2 0 003.812 1.312 6.2 6.2 0 006.199-6.2 6.2 6.2 0 00-4.2-5.856zm-4.2 9.193a3.337 3.337 0 110-6.674 3.337 3.337 0 010 6.674z"
  end

  defp salesforce_svg_path do
    "M10.006 3.573a5.26 5.26 0 0 1 3.907-1.735 5.285 5.285 0 0 1 4.816 3.088 4.94 4.94 0 0 1 2.691-.793C24.01 4.133 26.4 6.42 26.4 9.24s-2.39 5.107-4.98 5.107a5.1 5.1 0 0 1-1.183-.14 4.623 4.623 0 0 1-3.986 2.44 4.55 4.55 0 0 1-2.14-.534 5.12 5.12 0 0 1-4.467 2.78 5.15 5.15 0 0 1-4.67-3.22 4.97 4.97 0 0 1-1.074.12C1.733 15.793 0 13.9 0 11.59s1.733-4.203 4.9-4.203c.733 0 1.423.193 2.023.546a4.93 4.93 0 0 1 3.083-4.36z"
  end
end
