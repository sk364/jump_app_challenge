defmodule Ueberauth.Strategy.Salesforce do
  @moduledoc """
  Salesforce Strategy for Ueberauth with PKCE support.
  """
  use Ueberauth.Strategy,
    oauth2_module: Ueberauth.Strategy.Salesforce.OAuth,
    ignores_csrf_attack: true,
    default_scope: "api refresh_token"

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  require Logger

  # Define the OAuth module as a module attribute
  @oauth_module Ueberauth.Strategy.Salesforce.OAuth

  def handle_request!(conn) do
    scopes = conn.params["scope"] || "api refresh_token"

    code_verifier = generate_code_verifier()
    code_challenge = generate_code_challenge(code_verifier)

    opts = [
      redirect_uri: callback_url(conn),
      scope: scopes,
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    ]

    redirect_url = @oauth_module.authorize_url!(opts)

    conn
    |> put_session(:salesforce_code_verifier, code_verifier)
    |> redirect!(redirect_url)
  end

  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    exchange_token(conn, code)
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No authorization code")])
  end

  def handle_cleanup!(conn) do
    conn
    |> put_private(:salesforce_user, nil)
    |> put_private(:salesforce_token, nil)
    |> delete_session(:salesforce_code_verifier)
  end

  def uid(conn) do
    user = conn.private[:salesforce_user] || %{}
    user["user_id"] || user["id"]
  end

  def credentials(conn) do
    token = conn.private[:salesforce_token]

    %Credentials{
      token: token.access_token,
      refresh_token: token.refresh_token,
      expires: token.expires_at != nil,
      expires_at: token.expires_at,
      other: %{
        instance_url: token.other_params["instance_url"],
        id: token.other_params["id"]
      }
    }
  end

  def info(conn) do
    user = conn.private[:salesforce_user] || %{}

    %Info{
      email: user["email"],
      first_name: user["first_name"],
      last_name: user["last_name"],
      name: user["display_name"] || build_name(user),
      image: get_in(user, ["photos", "picture"]),
      urls: %{profile: get_in(user, ["urls", "profile"])}
    }
  end

  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private[:salesforce_token],
        user: conn.private[:salesforce_user]
      }
    }
  end

  # Private functions

  defp exchange_token(conn, code) do
    code_verifier = get_session(conn, :salesforce_code_verifier)

    params = [
      code: code,
      redirect_uri: callback_url(conn),
      code_verifier: code_verifier
    ]

    # Use the module attribute directly
    case @oauth_module.get_token(params) do
      {:ok, %{token: token} = client} ->
        Logger.info("✓ Token received")

        case get_user(client) do
          user when is_map(user) and map_size(user) > 0 ->
            conn
            |> delete_session(:salesforce_code_verifier)
            |> put_private(:salesforce_token, token)
            |> put_private(:salesforce_user, user)

          _ ->
            set_errors!(conn, [error("user_error", "Failed to get user")])
        end

      {:error, _} ->
        set_errors!(conn, [error("token_error", "Failed to get token")])
    end
  end

  defp get_user(client) do
    id_url = client.token.other_params["id"]

    case OAuth2.Client.get(client, id_url) do
      {:ok, %OAuth2.Response{body: user}} when is_map(user) ->
        user

      _ ->
        Logger.error("Failed to get user")
        %{}
    end
  end

  defp build_name(user) when is_map(user) do
    first = user["first_name"]
    last = user["last_name"]

    cond do
      first && last -> "#{first} #{last}"
      first -> first
      last -> last
      true -> nil
    end
  end

  defp build_name(_), do: nil

  defp generate_code_verifier do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  defp generate_code_challenge(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end
end
