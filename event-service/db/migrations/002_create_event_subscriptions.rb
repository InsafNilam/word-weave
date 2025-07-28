Sequel.migration do
  up do
    create_table :event_subscriptions do
      String :id, primary_key: true
      String :consumer_group, null: false
      String :event_types, null: false # JSON array
      String :callback_url
      String :status, default: 'active'
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      
      index [:consumer_group]
      index [:status]
    end
  end

  down do
    drop_table :event_subscriptions
  end
end