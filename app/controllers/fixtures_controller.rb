class FixturesController < ApplicationController
  FIELD_TEMPLATES = [
    -> { { title: "Department",       body: Faker::Commerce.department,         validation: { required: true, maxLength: 100 } } },
    -> { { title: "Cost Centre",      body: "CC-#{rand(100..999)}",             validation: { required: true, pattern: "^CC-\\d{3}$" } } },
    -> { { title: "Job Title",        body: Faker::Job.title,                   validation: { required: false, maxLength: 80 } } },
    -> { { title: "Office Location",  body: Faker::Address.city,                validation: { required: true } } },
    -> { { title: "Travel Tier",      body: %w[Standard Premium Executive].sample, validation: { allowedValues: %w[Standard Premium Executive] } } },
    -> { { title: "Team",             body: Faker::Commerce.department,         validation: { required: true, maxLength: 60 } } },
    -> { { title: "Manager",          body: Faker::Name.name,                   validation: { required: false, maxLength: 100 } } },
    -> { { title: "Budget Code",      body: "BUD-#{rand(1000..9999)}",          validation: { pattern: "^BUD-\\d{4}$" } } },
    -> { { title: "Project Code",     body: Faker::Alphanumeric.alphanumeric(number: 6).upcase, validation: { minLength: 6, maxLength: 6 } } },
    -> { { title: "Region",           body: Faker::Address.state,              validation: { allowedValues: %w[EMEA APAC AMER LATAM] } } },
    -> { { title: "Employer",         body: Faker::Company.name,               validation: { required: true } } },
    -> { { title: "Policy Holder",    body: Faker::Name.name,                  validation: { required: true, maxLength: 120 } } },
    -> { { title: "Reference Number", body: Faker::Alphanumeric.alphanumeric(number: 10).upcase, validation: { pattern: "^[A-Z0-9]{10}$" } } },
    -> { { title: "Approval Status",  body: %w[Pending Approved Rejected].sample, validation: { allowedValues: %w[Pending Approved Rejected] } } },
    -> { { title: "Country",          body: Faker::Address.country,            validation: { required: true } } },
  ].freeze

  def custom_fields
    count = rand(5..25)
    templates = FIELD_TEMPLATES.sample(count)

    operations = templates.map do |template|
      data = template.call
      vo = data[:validation]

      op = { "customField" => { "title" => data[:title], "body" => data[:body] } }
      op["validationOptions"] = build_validation_options(vo) if vo.present?
      op
    end

    render json: operations
  end

  private

  def build_validation_options(vo)
    {}.tap do |h|
      h["required"]       = vo[:required]       unless vo[:required].nil?
      h["minLength"]      = vo[:minLength]       if vo[:minLength]
      h["maxLength"]      = vo[:maxLength]       if vo[:maxLength]
      h["pattern"]        = vo[:pattern]         if vo[:pattern]
      h["allowedValues"]  = vo[:allowedValues]   if vo[:allowedValues]
    end
  end
end
