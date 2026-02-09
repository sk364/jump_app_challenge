defmodule SocialScribe.Chat.ContactSearch do
  @moduledoc """
  Searches contacts across connected CRMs (HubSpot and Salesforce) in parallel.
  """

  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApiBehaviour
  alias SocialScribe.SalesforceApiBehaviour

  def search(user, query) when byte_size(query) >= 2 do
    hubspot_task = Task.async(fn -> search_hubspot(user.id, query) end)
    salesforce_task = Task.async(fn -> search_salesforce(user.id, query) end)

    hubspot_results = Task.await(hubspot_task, 10_000)
    salesforce_results = Task.await(salesforce_task, 10_000)

    {:ok, hubspot_results ++ salesforce_results}
  end

  def search(_user, _query), do: {:ok, []}

  defp search_hubspot(user_id, query) do
    case Accounts.get_user_hubspot_credential(user_id) do
      nil ->
        []

      credential ->
        case HubspotApiBehaviour.search_contacts(credential, query) do
          {:ok, contacts} ->
            Enum.map(contacts, &Map.put(&1, :provider, "hubspot"))

          {:error, _} ->
            []
        end
    end
  end

  defp search_salesforce(user_id, query) do
    case Accounts.get_user_salesforce_credential(user_id) do
      nil ->
        []

      credential ->
        case SalesforceApiBehaviour.search_contacts(credential, query) do
          {:ok, contacts} ->
            Enum.map(contacts, &Map.put(&1, :provider, "salesforce"))

          {:error, _} ->
            []
        end
    end
  end
end
