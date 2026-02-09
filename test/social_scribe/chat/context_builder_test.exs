defmodule SocialScribe.Chat.ContextBuilderTest do
  use SocialScribe.DataCase

  import Mox

  alias SocialScribe.Chat.ContextBuilder
  alias SocialScribe.AccountsFixtures

  setup :set_mox_global
  setup :verify_on_exit!

  describe "build_system_prompt/2" do
    test "includes meeting assistant role" do
      user = AccountsFixtures.user_fixture()
      prompt = ContextBuilder.build_system_prompt(user)

      assert prompt =~ "meeting assistant"
    end

    test "fetches full contact details from hubspot when mentioned" do
      user = AccountsFixtures.user_fixture()
      AccountsFixtures.hubspot_credential_fixture(%{user_id: user.id})

      expect(SocialScribe.HubspotApiMock, :get_contact, fn _cred, "123" ->
        {:ok,
         %{
           id: "123",
           firstname: "John",
           lastname: "Doe",
           email: "john@test.com",
           phone: "555-1234",
           company: "Acme Corp",
           jobtitle: "CEO"
         }}
      end)

      contacts = [
        %{"id" => "123", "name" => "John Doe", "provider" => "hubspot", "email" => "john@test.com"}
      ]

      prompt = ContextBuilder.build_system_prompt(user, contacts)

      assert prompt =~ "555-1234"
      assert prompt =~ "Acme Corp"
      assert prompt =~ "CEO"
      assert prompt =~ "hubspot"
    end

    test "fetches full contact details from salesforce when mentioned" do
      user = AccountsFixtures.user_fixture()
      AccountsFixtures.salesforce_credential_fixture(%{user_id: user.id})

      expect(SocialScribe.SalesforceApiMock, :get_contact, fn _cred, "456" ->
        {:ok,
         %{
           id: "456",
           firstname: "Jane",
           lastname: "Smith",
           email: "jane@test.com",
           phone: "555-5678",
           company: "BigCo",
           jobtitle: "CTO"
         }}
      end)

      contacts = [
        %{
          "id" => "456",
          "name" => "Jane Smith",
          "provider" => "salesforce",
          "email" => "jane@test.com"
        }
      ]

      prompt = ContextBuilder.build_system_prompt(user, contacts)

      assert prompt =~ "555-5678"
      assert prompt =~ "BigCo"
      assert prompt =~ "salesforce"
    end

    test "falls back to basic info when API call fails" do
      user = AccountsFixtures.user_fixture()
      AccountsFixtures.hubspot_credential_fixture(%{user_id: user.id})

      expect(SocialScribe.HubspotApiMock, :get_contact, fn _cred, "999" ->
        {:error, :not_found}
      end)

      contacts = [
        %{
          "id" => "999",
          "name" => "Unknown Person",
          "provider" => "hubspot",
          "email" => "unknown@test.com"
        }
      ]

      prompt = ContextBuilder.build_system_prompt(user, contacts)

      assert prompt =~ "Unknown Person"
      assert prompt =~ "unknown@test.com"
    end

    test "includes update_contact JSON instruction" do
      user = AccountsFixtures.user_fixture()
      prompt = ContextBuilder.build_system_prompt(user)

      assert prompt =~ "update_contact"
    end
  end
end
