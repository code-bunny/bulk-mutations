require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  describe "GET /" do
    context "default state" do
      it "returns 200" do
        get root_path
        expect(response).to have_http_status(:ok)
      end

      it "defaults to the operations tab" do
        get root_path
        expect(response.body).to include("tab.active")
        expect(response.body).to include("Bulk Operations")
      end
    end

    context "tab switching" do
      it "shows the operations tab when tab=operations" do
        get root_path(tab: "operations")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Bulk Operations")
      end

      it "shows the fields tab when tab=fields" do
        get root_path(tab: "fields")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Custom Fields")
      end

      it "falls back to operations for an unknown tab param" do
        get root_path(tab: "nonsense")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Bulk Operations")
      end
    end

    context "with bulk operations" do
      before { create_list(:bulk_operation, 3) }

      it "shows each operation" do
        get root_path(tab: "operations")
        expect(response.body).to include("Completed")
      end

      it "shows the reset button" do
        get root_path(tab: "operations")
        expect(response.body).to include("Reset operations")
      end
    end

    context "with no bulk operations" do
      it "does not show the reset button" do
        get root_path(tab: "operations")
        expect(response.body).not_to include("Reset operations")
      end

      it "shows the empty state message" do
        get root_path(tab: "operations")
        expect(response.body).to include("No bulk operations yet")
      end
    end

    context "with custom fields" do
      before { create_list(:custom_field, 3) }

      it "shows custom fields on the fields tab" do
        get root_path(tab: "fields")
        expect(response.body).to include("Field 1")
      end
    end

    context "with no custom fields" do
      it "shows the empty state on the fields tab" do
        get root_path(tab: "fields")
        expect(response.body).to include("No custom fields yet")
      end
    end

    context "pagination" do
      it "paginates bulk operations at 15 per page" do
        create_list(:bulk_operation, 20)
        get root_path(tab: "operations")
        expect(response.body).to include("›")
        expect(response.body).to include("1–15 of 20")
      end

      it "shows the second page of bulk operations" do
        create_list(:bulk_operation, 20)
        get root_path(tab: "operations", page: 2)
        expect(response.body).to include("16–20 of 20")
      end

      it "does not show pagination with 15 or fewer records" do
        create_list(:bulk_operation, 15)
        get root_path(tab: "operations")
        expect(response.body).not_to include("1–15 of 15")
      end

      it "paginates custom fields at 15 per page" do
        create_list(:custom_field, 20)
        get root_path(tab: "fields")
        expect(response.body).to include("1–15 of 20")
      end
    end
  end

  describe "DELETE /bulk_operations/reset" do
    context "with existing bulk operations" do
      before { create_list(:bulk_operation, 5) }

      it "deletes all bulk operations" do
        expect { delete reset_bulk_operations_path }.to change { BulkOperation.count }.from(5).to(0)
      end

      it "redirects to the operations tab" do
        delete reset_bulk_operations_path
        expect(response).to redirect_to(root_path(tab: "operations"))
      end
    end

    context "with no bulk operations" do
      it "redirects without error" do
        delete reset_bulk_operations_path
        expect(response).to redirect_to(root_path(tab: "operations"))
      end
    end

    it "does not touch custom fields" do
      create_list(:custom_field, 3)
      create_list(:bulk_operation, 2)

      delete reset_bulk_operations_path

      expect(CustomField.count).to eq(3)
    end
  end

  describe "DELETE /custom_fields/reset" do
    context "with existing custom fields" do
      before do
        create_list(:custom_field, 4)
      end

      it "deletes all custom fields" do
        expect { delete reset_custom_fields_path }.to change { CustomField.count }.from(4).to(0)
      end

      it "deletes associated validation options" do
        CustomField.all.each do |cf|
          cf.validation_options.create!(required: true)
        end

        delete reset_custom_fields_path

        expect(CustomFieldValidationOption.count).to eq(0)
      end

      it "redirects to the fields tab" do
        delete reset_custom_fields_path
        expect(response).to redirect_to(root_path(tab: "fields"))
      end
    end

    context "with no custom fields" do
      it "redirects without error" do
        delete reset_custom_fields_path
        expect(response).to redirect_to(root_path(tab: "fields"))
      end
    end

    it "does not touch bulk operations" do
      create_list(:bulk_operation, 3)
      create_list(:custom_field, 2)

      delete reset_custom_fields_path

      expect(BulkOperation.count).to eq(3)
    end
  end
end
