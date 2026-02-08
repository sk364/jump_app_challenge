defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceSuggestions

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "Department",
          label: "Department",
          current_value: nil,
          new_value: "Engineering",
          context: "Works in Engineering",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003xx000001",
        phone: nil,
        company: "Engineering",
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      # Only phone should remain since Department maps to :company which already matches
      assert length(result) == 1
      assert hd(result).field == "Phone"
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "Email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003xx000001",
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{id: "003xx000001", email: "test@example.com"}

      result = SalesforceSuggestions.merge_with_contact([], contact)

      assert result == []
    end
  end

  describe "field_labels" do
    test "common fields have human-readable labels" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "003xx000001", phone: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Phone"
    end
  end
end
