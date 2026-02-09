defmodule SocialScribe.Chat.ContextBuilder do
  @moduledoc """
  Builds AI context from the user's meetings and mentioned contacts.
  Fetches full contact records from CRM APIs to provide complete data to the AI.
  """

  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApiBehaviour
  alias SocialScribe.SalesforceApiBehaviour
  alias SocialScribe.Meetings

  def build_system_prompt(user, mentioned_contacts \\ []) do
    meetings = Meetings.list_user_meetings(user)
    meetings_context = format_meetings(Enum.take(meetings, 10))
    contacts_context = fetch_and_format_contacts(user, mentioned_contacts)

    """
    You are a helpful meeting assistant for the user. You have access to their meeting data and CRM contacts.

    #{meetings_context}
    #{contacts_context}

    When the user asks about a contact, use the CRM data provided above to answer. Include specific field values like phone numbers, emails, company, job title, etc.
    When the user asks about meetings, reference specific details from the meeting data above.
    When the user asks to update a CRM contact field:
    1. Respond with a friendly, human-readable confirmation message. For example: "Sure! I'll update John Doe's phone number to 555-1234. Please confirm to proceed."
    2. Do NOT show IDs, provider names, or technical details to the user.
    3. At the very end of your response, include a hidden action block (the user won't see this) like:
    ```json
    {"action": "update_contact", "contact_id": "<id>", "provider": "<hubspot|salesforce>", "field": "<field_name>", "value": "<new_value>"}
    ```
    4. For the "field" value, use the exact field key shown in the contact data above (e.g. "jobtitle", "phone", "country", "mobilephone", "company", "zip"). Any field listed in the contact data can be updated, including fields marked "Not set".
    Only include the JSON block when the user explicitly asks to update or change a field. Otherwise, respond conversationally. Never show raw JSON, IDs, or technical details in the conversational part of your response.
    """
  end

  defp fetch_and_format_contacts(_user, []), do: ""

  defp fetch_and_format_contacts(user, mentioned_contacts) do
    contact_details =
      mentioned_contacts
      |> Enum.map(fn contact ->
        fetch_full_contact(user, contact)
      end)
      |> Enum.reject(&is_nil/1)

    case contact_details do
      [] -> ""
      details -> "## CRM Contact Details\n" <> Enum.join(details, "\n\n")
    end
  end

  defp fetch_full_contact(user, %{"id" => id, "provider" => "hubspot"} = contact) do
    case Accounts.get_user_hubspot_credential(user.id) do
      nil ->
        format_basic_contact(contact)

      credential ->
        case HubspotApiBehaviour.get_contact(credential, id) do
          {:ok, full_contact} ->
            format_full_contact(full_contact, "hubspot")

          {:error, _} ->
            format_basic_contact(contact)
        end
    end
  end

  defp fetch_full_contact(user, %{"id" => id, "provider" => "salesforce"} = contact) do
    case Accounts.get_user_salesforce_credential(user.id) do
      nil ->
        format_basic_contact(contact)

      credential ->
        case SalesforceApiBehaviour.get_contact(credential, id) do
          {:ok, full_contact} ->
            format_full_contact(full_contact, "salesforce")

          {:error, _} ->
            format_basic_contact(contact)
        end
    end
  end

  defp fetch_full_contact(_user, contact), do: format_basic_contact(contact)

  defp format_full_contact(contact, provider) do
    labels = field_labels(provider)

    fields =
      contact
      |> Enum.reject(fn {k, _v} -> k in [:id, :display_name] end)
      |> Enum.map(fn {k, v} ->
        display_value = if is_nil(v) or v == "", do: "Not set", else: v
        label = Map.get(labels, k, to_string(k))
        "  #{k} (#{label}): #{display_value}"
      end)
      |> Enum.join("\n")

    "### Contact (#{provider}, ID: #{contact[:id] || contact["id"]})\n#{fields}"
  end

  defp field_labels("salesforce") do
    %{
      firstname: "First Name",
      lastname: "Last Name",
      email: "Email",
      phone: "Phone",
      mobilephone: "Mobile Phone",
      company: "Department",
      jobtitle: "Job Title",
      address: "Mailing Street",
      city: "Mailing City",
      state: "Mailing State",
      zip: "ZIP/Postal Code",
      country: "Mailing Country",
      description: "Description"
    }
  end

  defp field_labels("hubspot") do
    %{
      firstname: "First Name",
      lastname: "Last Name",
      email: "Email",
      phone: "Phone",
      mobilephone: "Mobile Phone",
      company: "Company",
      jobtitle: "Job Title",
      address: "Address",
      city: "City",
      state: "State",
      zip: "ZIP Code",
      country: "Country",
      website: "Website",
      linkedin_url: "LinkedIn",
      twitter_handle: "Twitter"
    }
  end

  defp field_labels(_), do: %{}

  defp format_basic_contact(contact) do
    "### Contact (#{contact["provider"]}, ID: #{contact["id"]})\n" <>
      "  Name: #{contact["name"] || "Unknown"}\n" <>
      "  Email: #{contact["email"] || "N/A"}"
  end

  defp format_meetings([]), do: "The user has no recorded meetings yet."

  defp format_meetings(meetings) do
    meeting_summaries =
      meetings
      |> Enum.map(fn meeting ->
        transcript_excerpt = get_transcript_excerpt(meeting)

        participants =
          case meeting.meeting_participants do
            [] -> "No participants recorded"
            parts -> Enum.map_join(parts, ", ", & &1.name)
          end

        """
        - "#{meeting.title}" (#{format_date(meeting.recorded_at)})
          Participants: #{participants}
          #{transcript_excerpt}
        """
      end)
      |> Enum.join("\n")

    "## Recent Meetings\n#{meeting_summaries}"
  end

  defp get_transcript_excerpt(%{meeting_transcript: nil}), do: ""

  defp get_transcript_excerpt(%{meeting_transcript: %{content: content}}) when is_map(content) do
    case content do
      %{"text" => text} when is_binary(text) ->
        excerpt = String.slice(text, 0, 500)
        "Transcript excerpt: #{excerpt}..."

      _ ->
        ""
    end
  end

  defp get_transcript_excerpt(_), do: ""

  defp format_date(nil), do: "Unknown date"

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end
end
