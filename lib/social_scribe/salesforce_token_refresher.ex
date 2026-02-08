defmodule SocialScribe.SalesforceTokenRefresher do
  @moduledoc """
  Refreshes Salesforce OAuth tokens and resolves instance URLs.
  """

  @salesforce_token_url "https://login.salesforce.com/services/oauth2/token"

  require Logger

  def client do
    Tesla.client([
      {Tesla.Middleware.FormUrlencoded,
       encode: &Plug.Conn.Query.encode/1, decode: &Plug.Conn.Query.decode/1},
      Tesla.Middleware.JSON
    ])
  end

  @doc """
  Refreshes a Salesforce access token using the refresh token.
  Returns {:ok, response_body} with new access_token, instance_url, etc.
  """
  def refresh_token(refresh_token_string) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    client_id = config[:client_id]
    client_secret = config[:client_secret]

    body = %{
      grant_type: "refresh_token",
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token_string
    }

    case Tesla.post(client(), @salesforce_token_url, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {status, error_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refreshes the token for a Salesforce credential and updates it in the database.
  Note: Salesforce refresh token responses do not include a new refresh_token,
  so the existing one is preserved.
  """
  def refresh_credential(credential) do
    alias SocialScribe.Accounts

    case refresh_token(credential.refresh_token) do
      {:ok, response} ->
        attrs = %{
          token: response["access_token"],
          # Salesforce does not rotate refresh tokens on refresh
          refresh_token: credential.refresh_token,
          # Salesforce tokens typically expire in ~2 hours but don't include expires_in;
          # default to 2 hours from now
          expires_at:
            DateTime.add(
              DateTime.utc_now(),
              response["expires_in"] || 7200,
              :second
            )
        }

        Accounts.update_user_credential(credential, attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ensures a credential has a valid (non-expired) token.
  Refreshes if expired or about to expire (within 5 minutes).
  """
  def ensure_valid_token(credential) do
    buffer_seconds = 300

    if DateTime.compare(
         credential.expires_at,
         DateTime.add(DateTime.utc_now(), buffer_seconds, :second)
       ) == :lt do
      refresh_credential(credential)
    else
      {:ok, credential}
    end
  end

  @doc """
  Gets the Salesforce instance URL for a credential by calling the identity endpoint.
  The instance URL is needed for all Salesforce REST API calls.
  """
  def get_instance_url(credential) do
    # Use the token to query the Salesforce identity endpoint at login.salesforce.com
    # which returns the instance_url for the authenticated user's org
    identity_client =
      Tesla.client([
        Tesla.Middleware.JSON,
        {Tesla.Middleware.Headers,
         [
           {"Authorization", "Bearer #{credential.token}"}
         ]}
      ])

    case Tesla.get(identity_client, "https://login.salesforce.com/services/oauth2/userinfo") do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        # The userinfo response includes profile URL like "https://yourinstance.my.salesforce.com/..."
        # Extract instance URL from the profile or organization_id
        instance_url = extract_instance_url(body)

        if instance_url do
          {:ok, instance_url}
        else
          {:error, :instance_url_not_found}
        end

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Failed to get Salesforce instance URL: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp extract_instance_url(%{"urls" => urls}) when is_map(urls) do
    # Salesforce userinfo returns URLs like:
    # "profile" => "https://yourinstance.my.salesforce.com/005xx000001..."
    # Extract the base URL from any of the provided URLs
    url_string =
      urls["profile"] || urls["enterprise"] || urls["rest"] || urls["partner"]

    if url_string do
      uri = URI.parse(url_string)
      "#{uri.scheme}://#{uri.host}"
    else
      nil
    end
  end

  defp extract_instance_url(%{"profile" => profile_url}) when is_binary(profile_url) do
    uri = URI.parse(profile_url)
    "#{uri.scheme}://#{uri.host}"
  end

  defp extract_instance_url(_), do: nil
end
