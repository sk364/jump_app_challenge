defmodule SocialScribe.Ueberauth.Strategy.Salesforce.OAuth do
  @moduledoc """
  OAuth2 client for Salesforce
  """
  use OAuth2.Strategy

  require Logger

  @defaults [
    strategy: __MODULE__,
    site: "https://login.salesforce.com",
    authorize_url: "/services/oauth2/authorize",
    token_url: "/services/oauth2/token",
    token_method: :post
  ]

  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])

    opts =
      @defaults
      |> Keyword.merge(config)
      |> Keyword.merge(opts)
      |> Keyword.put(:serializers, %{"application/json" => Jason})

    OAuth2.Client.new(opts)
  end

  def authorize_url!(params \\ []) do
    OAuth2.Client.authorize_url!(client(), params)
  end

  def get_token(params \\ [], headers \\ []) do
    Logger.info("Requesting token")

    oauth_client = client()

    token_params = params
    |> Keyword.put(:grant_type, "authorization_code")
    |> Keyword.put(:client_id, oauth_client.client_id)
    |> Keyword.put(:client_secret, oauth_client.client_secret)

    case OAuth2.Client.get_token(oauth_client, token_params, headers) do
      {:ok, client} ->
        # ALWAYS parse the token response since Salesforce sends it as JSON string
        parse_and_fix_token(client)

      error ->
        Logger.error("Token request failed")
        error
    end
  end

  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    client
    |> put_header("accept", "application/json")
    |> put_header("content-type", "application/x-www-form-urlencoded")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end

  # This function ALWAYS parses the token, whether it's a string or already parsed
  defp parse_and_fix_token(client) do
    access_token = client.token.access_token

    Logger.info("Parsing token response...")
    Logger.debug("Raw access_token: #{inspect(String.slice(to_string(access_token), 0..50))}...")

    # Check if it's a JSON string
    parsed_data = if is_binary(access_token) and String.starts_with?(access_token, "{") do
      Logger.info("Token is JSON string, parsing...")

      case Jason.decode(access_token) do
        {:ok, data} ->
          Logger.info("✓ Parsed JSON successfully")
          data
        {:error, error} ->
          Logger.error("Failed to parse JSON: #{inspect(error)}")
          nil
      end
    else
      Logger.info("Token already in correct format")
      nil
    end

    # If we successfully parsed JSON, rebuild the token
    if parsed_data do
      new_token = %OAuth2.AccessToken{
        access_token: parsed_data["access_token"],
        refresh_token: parsed_data["refresh_token"],
        expires_at: nil,
        token_type: parsed_data["token_type"] || "Bearer",
        other_params: %{
          "instance_url" => parsed_data["instance_url"],
          "id" => parsed_data["id"],
          "signature" => parsed_data["signature"],
          "scope" => parsed_data["scope"],
          "issued_at" => parsed_data["issued_at"]
        }
      }

      Logger.info("✓ Token rebuilt successfully")
      Logger.debug("Instance URL: #{new_token.other_params["instance_url"]}")
      Logger.debug("ID URL: #{new_token.other_params["id"]}")

      {:ok, %{client | token: new_token}}
    else
      # Return as-is if no parsing needed
      {:ok, client}
    end
  end
end
