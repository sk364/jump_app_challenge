defmodule SocialScribe.Chat.CrmActionHandler do
  @moduledoc """
  Parses and executes CRM actions from AI responses.
  Handles the two-step flow: AI suggests update → user confirms → system executes.
  """

  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApiBehaviour
  alias SocialScribe.SalesforceApiBehaviour

  @action_regex ~r/```json\s*(\{[^`]+\})\s*```/

  def parse_action(ai_response) do
    case Regex.run(@action_regex, ai_response) do
      [_full, json_str] ->
        case Jason.decode(json_str) do
          {:ok, %{"action" => "update_contact"} = action} -> {:ok, action}
          {:ok, _} -> :no_action
          {:error, _} -> :no_action
        end

      nil ->
        :no_action
    end
  end

  def execute_action(
        %{
          "action" => "update_contact",
          "contact_id" => contact_id,
          "provider" => provider,
          "field" => field,
          "value" => value
        },
        user
      ) do
    case provider do
      "hubspot" -> execute_hubspot_update(user, contact_id, field, value)
      "salesforce" -> execute_salesforce_update(user, contact_id, field, value)
      _ -> {:error, "Unknown CRM provider: #{provider}"}
    end
  end

  def execute_action(_, _), do: {:error, "Invalid action format"}

  def format_confirmation(action) do
    provider = action["provider"]
    "Update #{provider}: set **#{humanize_field(action["field"])}** to \"#{action["value"]}\""
  end

  defp humanize_field(field) when is_binary(field) do
    field
    |> String.replace(~r/[_-]/, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp humanize_field(field), do: inspect(field)

  defp execute_hubspot_update(user, contact_id, field, value) do
    case Accounts.get_user_hubspot_credential(user.id) do
      nil ->
        {:error, "No HubSpot connection found"}

      credential ->
        HubspotApiBehaviour.update_contact(credential, contact_id, %{field => value})
    end
  end

  defp execute_salesforce_update(user, contact_id, field, value) do
    case Accounts.get_user_salesforce_credential(user.id) do
      nil ->
        {:error, "No Salesforce connection found"}

      credential ->
        api_field = to_salesforce_field(field)
        SalesforceApiBehaviour.update_contact(credential, contact_id, %{api_field => value})
    end
  end

  # The AI sees atom-style keys (phone, firstname) from formatted contact data,
  # but Salesforce API requires PascalCase field names (Phone, FirstName).
  defp to_salesforce_field("firstname"), do: "FirstName"
  defp to_salesforce_field("lastname"), do: "LastName"
  defp to_salesforce_field("email"), do: "Email"
  defp to_salesforce_field("phone"), do: "Phone"
  defp to_salesforce_field("mobilephone"), do: "MobilePhone"
  defp to_salesforce_field("company"), do: "Department"
  defp to_salesforce_field("jobtitle"), do: "Title"
  defp to_salesforce_field("address"), do: "MailingStreet"
  defp to_salesforce_field("city"), do: "MailingCity"
  defp to_salesforce_field("state"), do: "MailingState"
  defp to_salesforce_field("zip"), do: "MailingPostalCode"
  defp to_salesforce_field("country"), do: "MailingCountry"
  defp to_salesforce_field("description"), do: "Description"
  defp to_salesforce_field(field), do: field
end
