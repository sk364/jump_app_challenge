defmodule SocialScribe.CrmSuggestions do
  @moduledoc """
  Generates and formats CRM contact update suggestions by combining
  AI-extracted data with existing contact information.

  Supports multiple CRM providers (HubSpot, Salesforce) through a unified API.
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi
  alias SocialScribe.Accounts.UserCredential

  @doc """
  Generates suggested updates for a CRM contact based on a meeting transcript.

  Returns a list of suggestion maps, each containing:
  - field: the CRM field name
  - label: human-readable field label
  - current_value: the existing value in the CRM (or nil)
  - new_value: the AI-suggested value
  - context: explanation of where this was found in the transcript
  - apply: boolean indicating whether to apply this update (default false)
  """
  def generate_suggestions(provider, %UserCredential{} = credential, contact_id, meeting) do
    config = provider_config(provider)

    with {:ok, contact} <- config.get_contact.(credential, contact_id),
         {:ok, ai_suggestions} <- config.generate_suggestions.(meeting) do
      suggestions =
        ai_suggestions
        |> Enum.map(fn suggestion ->
          field = suggestion.field
          current_value = get_contact_field(config, contact, field)

          %{
            field: field,
            label: Map.get(config.field_labels, field, field),
            current_value: current_value,
            new_value: suggestion.value,
            context: suggestion.context,
            apply: true,
            has_change: current_value != suggestion.value
          }
        end)
        |> Enum.filter(fn s -> s.has_change end)

      {:ok, %{contact: contact, suggestions: suggestions}}
    end
  end

  @doc """
  Generates suggestions without fetching contact data.
  Useful when contact hasn't been selected yet.
  """
  def generate_suggestions_from_meeting(provider, meeting) do
    config = provider_config(provider)

    case config.generate_suggestions.(meeting) do
      {:ok, ai_suggestions} ->
        suggestions =
          ai_suggestions
          |> Enum.map(fn suggestion ->
            %{
              field: suggestion.field,
              label: Map.get(config.field_labels, suggestion.field, suggestion.field),
              current_value: nil,
              new_value: suggestion.value,
              context: Map.get(suggestion, :context),
              timestamp: Map.get(suggestion, :timestamp),
              apply: true,
              has_change: true
            }
          end)

        {:ok, suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Merges AI suggestions with contact data to show current vs suggested values.
  """
  def merge_with_contact(provider, suggestions, contact) when is_list(suggestions) do
    config = provider_config(provider)

    Enum.map(suggestions, fn suggestion ->
      current_value = get_contact_field(config, contact, suggestion.field)

      %{suggestion | current_value: current_value, has_change: current_value != suggestion.new_value, apply: true}
    end)
    |> Enum.filter(fn s -> s.has_change end)
  end

  defp get_contact_field(config, contact, field) when is_map(contact) do
    field_atom = config.field_to_atom.(field)
    Map.get(contact, field_atom)
  rescue
    ArgumentError -> nil
  end

  defp get_contact_field(_, _, _), do: nil

  defp provider_config(:hubspot) do
    %{
      field_labels: %{
        "firstname" => "First Name",
        "lastname" => "Last Name",
        "email" => "Email",
        "phone" => "Phone",
        "mobilephone" => "Mobile Phone",
        "company" => "Company",
        "jobtitle" => "Job Title",
        "address" => "Address",
        "city" => "City",
        "state" => "State",
        "zip" => "ZIP Code",
        "country" => "Country",
        "website" => "Website",
        "linkedin_url" => "LinkedIn",
        "twitter_handle" => "Twitter"
      },
      get_contact: &HubspotApi.get_contact/2,
      generate_suggestions: &AIContentGeneratorApi.generate_hubspot_suggestions/1,
      field_to_atom: fn field ->
        String.to_existing_atom(field)
      end
    }
  end

  defp provider_config(:salesforce) do
    %{
      field_labels: %{
        "FirstName" => "First Name",
        "LastName" => "Last Name",
        "Email" => "Email",
        "Phone" => "Phone",
        "MobilePhone" => "Mobile Phone",
        "Department" => "Department",
        "Title" => "Job Title",
        "MailingStreet" => "Address",
        "MailingCity" => "City",
        "MailingState" => "State",
        "MailingPostalCode" => "ZIP Code",
        "MailingCountry" => "Country",
        "Description" => "Description"
      },
      get_contact: &SalesforceApi.get_contact/2,
      generate_suggestions: &AIContentGeneratorApi.generate_salesforce_suggestions/1,
      field_to_atom: &salesforce_field_to_atom/1
    }
  end

  defp salesforce_field_to_atom("FirstName"), do: :firstname
  defp salesforce_field_to_atom("LastName"), do: :lastname
  defp salesforce_field_to_atom("Email"), do: :email
  defp salesforce_field_to_atom("Phone"), do: :phone
  defp salesforce_field_to_atom("MobilePhone"), do: :mobilephone
  defp salesforce_field_to_atom("Department"), do: :company
  defp salesforce_field_to_atom("Title"), do: :jobtitle
  defp salesforce_field_to_atom("MailingStreet"), do: :address
  defp salesforce_field_to_atom("MailingCity"), do: :city
  defp salesforce_field_to_atom("MailingState"), do: :state
  defp salesforce_field_to_atom("MailingPostalCode"), do: :zip
  defp salesforce_field_to_atom("MailingCountry"), do: :country
  defp salesforce_field_to_atom("Description"), do: :description
  defp salesforce_field_to_atom(field), do: String.to_existing_atom(field)
end
