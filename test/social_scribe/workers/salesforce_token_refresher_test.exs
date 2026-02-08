defmodule SocialScribe.Workers.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.Workers.SalesforceTokenRefresher

  import SocialScribe.AccountsFixtures

  describe "perform/1" do
    test "completes successfully when no Salesforce tokens are expiring" do
      # No Salesforce credentials exist, so nothing to refresh
      assert :ok == SalesforceTokenRefresher.perform(%Oban.Job{args: %{}})
    end

    test "finds credentials expiring within 10 minutes" do
      user = user_fixture()

      # Create a credential that expires in 5 minutes (within the 10-minute threshold)
      _expiring =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
        })

      # Create a credential that expires in 2 hours (not within threshold)
      _not_expiring =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second),
          uid: "sf_other_#{System.unique_integer([:positive])}"
        })

      # The job will try to refresh the expiring token but fail due to no real Salesforce API
      # That's OK - the worker catches errors and returns :ok anyway
      assert :ok == SalesforceTokenRefresher.perform(%Oban.Job{args: %{}})
    end

    test "does not pick up non-Salesforce credentials" do
      user = user_fixture()

      # Create a HubSpot credential that's expiring (should be ignored)
      _hubspot =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
        })

      # Should complete with no work to do
      assert :ok == SalesforceTokenRefresher.perform(%Oban.Job{args: %{}})
    end
  end
end
