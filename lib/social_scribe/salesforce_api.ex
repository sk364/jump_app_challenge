defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contacts operations.
  Implements automatic token refresh on 401/expired token errors.
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @api_version "v60.0"

  @contact_fields [
    "Id",
    "FirstName",
    "LastName",
    "Email",
    "Phone",
    "MobilePhone",
    "Title",
    "Department",
    "AccountId",
    "MailingStreet",
    "MailingCity",
    "MailingState",
    "MailingPostalCode",
    "MailingCountry",
    "Description"
  ]

  defp client(access_token, instance_url) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "#{instance_url}/services/data/#{@api_version}"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  @doc """
  Searches for contacts by query string using SOSL.
  Returns up to 10 matching contacts with basic properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred, instance_url ->
      escaped_query = escape_sosl_query(query)
      fields = Enum.join(@contact_fields, ", ")

      sosl =
        "FIND {#{escaped_query}} IN ALL FIELDS RETURNING Contact(#{fields}) LIMIT 10"

      encoded_sosl = URI.encode(sosl)

      case Tesla.get(client(cred.token, instance_url), "/search/?q=#{encoded_sosl}") do
        {:ok, %Tesla.Env{status: 200, body: %{"searchRecords" => records}}} ->
          contacts = Enum.map(records, &format_contact/1)
          {:ok, contacts}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Gets a single contact by ID with all properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def get_contact(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred, instance_url ->
      fields_param = Enum.join(@contact_fields, ",")
      url = "/sobjects/Contact/#{contact_id}?fields=#{fields_param}"

      case Tesla.get(client(cred.token, instance_url), url) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          {:ok, format_contact(body)}

        {:ok, %Tesla.Env{status: 404, body: _body}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Updates a contact's properties.
  `updates` should be a map of Salesforce field names to new values.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) do
    with_token_refresh(credential, fn cred, instance_url ->
      case Tesla.patch(
             client(cred.token, instance_url),
             "/sobjects/Contact/#{contact_id}",
             updates
           ) do
        {:ok, %Tesla.Env{status: 204}} ->
          # Salesforce returns 204 No Content on successful update, fetch the updated contact
          get_contact_direct(cred, instance_url, contact_id)

        {:ok, %Tesla.Env{status: 404, body: _body}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Batch updates multiple properties on a contact.
  This is a convenience wrapper around update_contact/3.
  """
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    updates_map =
      updates_list
      |> Enum.filter(fn update -> update[:apply] == true end)
      |> Enum.reduce(%{}, fn update, acc ->
        Map.put(acc, update.field, update.new_value)
      end)

    if map_size(updates_map) > 0 do
      update_contact(credential, contact_id, updates_map)
    else
      {:ok, :no_updates}
    end
  end

  # Direct get without token refresh wrapper (used after update)
  defp get_contact_direct(credential, instance_url, contact_id) do
    fields_param = Enum.join(@contact_fields, ",")
    url = "/sobjects/Contact/#{contact_id}?fields=#{fields_param}"

    case Tesla.get(client(credential.token, instance_url), url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, format_contact(body)}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  # Format a Salesforce contact response into a cleaner structure
  defp format_contact(%{"Id" => id} = record) do
    %{
      id: id,
      firstname: record["FirstName"],
      lastname: record["LastName"],
      email: record["Email"],
      phone: record["Phone"],
      mobilephone: record["MobilePhone"],
      company: record["Department"],
      jobtitle: record["Title"],
      address: record["MailingStreet"],
      city: record["MailingCity"],
      state: record["MailingState"],
      zip: record["MailingPostalCode"],
      country: record["MailingCountry"],
      display_name: format_display_name(record)
    }
  end

  defp format_contact(_), do: nil

  defp format_display_name(record) do
    firstname = record["FirstName"] || ""
    lastname = record["LastName"] || ""
    email = record["Email"] || ""

    name = String.trim("#{firstname} #{lastname}")

    if name == "" do
      email
    else
      name
    end
  end

  # Escape special SOSL characters
  defp escape_sosl_query(query) do
    query
    |> String.replace(~r/[?&|!{}[\]()^~*:\\"'+\-]/, fn char -> "\\#{char}" end)
  end

  # Wrapper that handles token refresh on auth errors.
  # The callback receives (credential, instance_url) since Salesforce uses per-org instance URLs.
  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    with {:ok, credential} <- SalesforceTokenRefresher.ensure_valid_token(credential),
         {:ok, instance_url} <- SalesforceTokenRefresher.get_instance_url(credential) do
      case api_call.(credential, instance_url) do
        {:error, {:api_error, status, body}} when status in [401, 403] ->
          if is_token_error?(body) do
            Logger.info("Salesforce token expired, refreshing and retrying...")
            retry_with_fresh_token(credential, api_call)
          else
            Logger.error("Salesforce API error: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          end

        other ->
          other
      end
    end
  end

  defp retry_with_fresh_token(credential, api_call) do
    case SalesforceTokenRefresher.refresh_credential(credential) do
      {:ok, refreshed_credential} ->
        case SalesforceTokenRefresher.get_instance_url(refreshed_credential) do
          {:ok, instance_url} ->
            case api_call.(refreshed_credential, instance_url) do
              {:error, {:api_error, status, body}} ->
                Logger.error(
                  "Salesforce API error after refresh: #{status} - #{inspect(body)}"
                )

                {:error, {:api_error, status, body}}

              {:error, {:http_error, reason}} ->
                Logger.error("Salesforce HTTP error after refresh: #{inspect(reason)}")
                {:error, {:http_error, reason}}

              success ->
                success
            end

          {:error, reason} ->
            Logger.error("Failed to get Salesforce instance URL: #{inspect(reason)}")
            {:error, {:instance_url_error, reason}}
        end

      {:error, refresh_error} ->
        Logger.error("Failed to refresh Salesforce token: #{inspect(refresh_error)}")
        {:error, {:token_refresh_failed, refresh_error}}
    end
  end

  defp is_token_error?(body) when is_list(body) do
    Enum.any?(body, &is_token_error?/1)
  end

  defp is_token_error?(%{"errorCode" => "INVALID_SESSION_ID"}), do: true

  defp is_token_error?(%{"message" => msg}) when is_binary(msg) do
    String.contains?(String.downcase(msg), [
      "session expired",
      "invalid session",
      "unauthorized",
      "expired access"
    ])
  end

  defp is_token_error?(_), do: false
end
