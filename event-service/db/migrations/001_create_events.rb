Sequel.migration do
  up do
    create_table :events do
      String :id, primary_key: true
      String :aggregate_id, null: false
      String :aggregate_type, null: false
      String :event_type, null: false
      Text :event_data, null: false
      Text :metadata
      Bignum :version, null: false, default: 1
      Bignum :timestamp, null: false
      String :correlation_id
      String :causation_id
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      
      index [:aggregate_id, :aggregate_type]
      index [:aggregate_id, :version], unique: true
      index [:event_type]
      index [:timestamp]
      index [:correlation_id]
    end
  end

  down do
    drop_table :events
  end
end