defmodule SocialScribe.Chat.CrmActionHandlerTest do
  use SocialScribe.DataCase

  alias SocialScribe.Chat.CrmActionHandler

  describe "parse_action/1" do
    test "parses valid update_contact action from AI response" do
      response = """
      Sure, I can update that for you.
      ```json
      {"action": "update_contact", "contact_id": "123", "provider": "hubspot", "field": "phone", "value": "555-1234"}
      ```
      """

      assert {:ok, action} = CrmActionHandler.parse_action(response)
      assert action["action"] == "update_contact"
      assert action["contact_id"] == "123"
      assert action["provider"] == "hubspot"
      assert action["field"] == "phone"
      assert action["value"] == "555-1234"
    end

    test "returns :no_action when no JSON block found" do
      assert :no_action == CrmActionHandler.parse_action("Just a normal response.")
    end

    test "returns :no_action for non-update_contact actions" do
      response = """
      ```json
      {"action": "something_else", "data": "value"}
      ```
      """

      assert :no_action == CrmActionHandler.parse_action(response)
    end

    test "returns :no_action for invalid JSON" do
      response = """
      ```json
      {invalid json here}
      ```
      """

      assert :no_action == CrmActionHandler.parse_action(response)
    end
  end

  describe "format_confirmation/1" do
    test "formats a readable confirmation message" do
      action = %{
        "action" => "update_contact",
        "contact_id" => "123",
        "provider" => "salesforce",
        "field" => "Phone",
        "value" => "555-9999"
      }

      result = CrmActionHandler.format_confirmation(action)
      assert result =~ "salesforce"
      assert result =~ "Phone"
      assert result =~ "555-9999"
    end
  end
end
