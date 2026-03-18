if Rails.env.development?
  GraphiQL::Rails.config.initial_query = \
    Rails.root.join("graphql/examples/custom_fields.graphql").read
end
