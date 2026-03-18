require "rails_helper"

RSpec.describe "GET /graphiql", type: :request do
  it "returns 200" do
    get "/graphiql"
    expect(response).to have_http_status(:ok)
  end

  it "renders a full HTML page" do
    get "/graphiql"
    expect(response.content_type).to include("text/html")
    expect(response.body).to include("<!DOCTYPE html>")
  end

  it "loads GraphiQL 3.x from CDN" do
    get "/graphiql"
    expect(response.body).to include("graphiql@3")
  end

  it "configures defaultTabs in the page" do
    get "/graphiql"
    expect(response.body).to include("defaultTabs")
  end

  it "includes a tab for each named operation" do
    get "/graphiql"
    body = response.body
    expect(body).to include("Preview Inline")
    expect(body).to include("Create via URL")
    expect(body).to include("Upsert (create or update)")
    expect(body).to include("Error Case")
    expect(body).to include("Poll Job")
  end

  it "points the fetcher at /graphql" do
    get "/graphiql"
    expect(response.body).to include("/graphql")
  end
end
