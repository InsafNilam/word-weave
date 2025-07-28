Sequel.migration do
  up do
    create_table :dead_letter_events do
      String :id, primary_key: true
      String :original_event_id, null: false
      String :exchange_name, null: false
      String :routing_key, null: false
      Text :event_payload, null: false
      Text :error_message
      Integer :retry_count, default: 0
      DateTime :failed_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      
      index [:original_event_id]
      index [:exchange_name]
      index [:failed_at]
    end
  end

  down do
    drop_table :dead_letter_events
  end
end