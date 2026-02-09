defmodule SocialScribe.Chat.ContactSearchTest do
  use SocialScribe.DataCase

  import Mox

  alias SocialScribe.Chat.ContactSearch
  alias SocialScribe.AccountsFixtures

  setup :set_mox_global
  setup :verify_on_exit!

  describe "search/2" do
    test "returns empty list for short queries" do
      user = AccountsFixtures.user_fixture()
      assert {:ok, []} = ContactSearch.search(user, "a")
    end

    test "searches hubspot when credential exists" do
      user = AccountsFixtures.user_fixture()
      AccountsFixtures.hubspot_credential_fixture(%{user_id: user.id})

      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, "john" ->
        {:ok, [%{id: "1", firstname: "John", lastname: "Doe", email: "john@test.com", display_name: "John Doe"}]}
      end)

      assert {:ok, results} = ContactSearch.search(user, "john")
      hubspot_results = Enum.filter(results, &(&1.provider == "hubspot"))
      assert length(hubspot_results) == 1
      assert hd(hubspot_results).display_name == "John Doe"
    end

    test "searches both CRMs in parallel" do
      user = AccountsFixtures.user_fixture()
      AccountsFixtures.hubspot_credential_fixture(%{user_id: user.id})
      AccountsFixtures.salesforce_credential_fixture(%{user_id: user.id})

      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, "test" ->
        {:ok, [%{id: "h1", display_name: "HubSpot Contact", email: "h@test.com"}]}
      end)

      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _cred, "test" ->
        {:ok, [%{id: "s1", display_name: "Salesforce Contact", email: "s@test.com"}]}
      end)

      assert {:ok, results} = ContactSearch.search(user, "test")
      assert length(results) == 2
      providers = Enum.map(results, & &1.provider)
      assert "hubspot" in providers
      assert "salesforce" in providers
    end

    test "handles API errors gracefully" do
      user = AccountsFixtures.user_fixture()
      AccountsFixtures.hubspot_credential_fixture(%{user_id: user.id})

      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, "error" ->
        {:error, :api_error}
      end)

      assert {:ok, []} = ContactSearch.search(user, "error")
    end
  end
end
