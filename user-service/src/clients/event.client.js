const grpc = require("@grpc/grpc-js");
const protoLoader = require("@grpc/proto-loader");
const path = require("path");

class EventServiceClient {
  constructor(serverAddress = "event-service:50055") {
    // Load the protobuf definition
    const PROTO_PATH = path.join(__dirname, "../protos/event.proto");
    const packageDefinition = protoLoader.loadSync(PROTO_PATH, {
      keepCase: true,
      longs: String,
      enums: String,
      defaults: true,
      oneofs: true,
    });

    const eventProto = grpc.loadPackageDefinition(packageDefinition).event;

    // Create the gRPC client
    this.client = new eventProto.EventService(
      process.env.EVENT_SERVICE_HOST || serverAddress,
      grpc.credentials.createInsecure()
    );
  }

  /**
   * Publish a domain event
   */
  async publishEvent({
    aggregateId,
    aggregateType,
    eventType,
    eventData,
    metadata = {},
    correlationId = "",
    causationId = "",
  }) {
    return new Promise((resolve, reject) => {
      const request = {
        aggregate_id: aggregateId,
        aggregate_type: aggregateType,
        event_type: eventType,
        event_data: JSON.stringify(eventData),
        metadata: JSON.stringify(metadata),
        correlation_id: correlationId,
        causation_id: causationId,
      };

      this.client.publishEvent(request, (error, response) => {
        if (error) {
          reject(error);
        } else if (!response.success) {
          reject(new Error(response.message));
        } else {
          resolve(response);
        }
      });
    });
  }

  /**
   * Get events by type or recent events
   */
  async getEvents({
    eventType = "",
    aggregateType = "",
    limit = 100,
    offset = 0,
  } = {}) {
    return new Promise((resolve, reject) => {
      const request = {
        event_type: eventType,
        aggregate_type: aggregateType,
        limit,
        offset,
      };

      this.client.getEvents(request, (error, response) => {
        if (error) {
          reject(error);
        } else if (!response.success) {
          reject(new Error(response.message));
        } else {
          resolve(response.events);
        }
      });
    });
  }

  /**
   * Get events for a specific aggregate
   */
  async getEventsByAggregate({ aggregateId, aggregateType, fromVersion = 1 }) {
    return new Promise((resolve, reject) => {
      const request = {
        aggregate_id: aggregateId,
        aggregate_type: aggregateType,
        from_version: fromVersion,
      };

      this.client.getEventsByAggregate(request, (error, response) => {
        if (error) {
          reject(error);
        } else if (!response.success) {
          reject(new Error(response.message));
        } else {
          resolve(response.events);
        }
      });
    });
  }

  /**
   * Subscribe to events
   */
  async subscribeToEvents({ consumerGroup, eventTypes = [], callbackUrl }) {
    return new Promise((resolve, reject) => {
      const request = {
        consumer_group: consumerGroup,
        event_types: eventTypes,
        callback_url: callbackUrl,
      };

      this.client.subscribeToEvents(request, (error, response) => {
        if (error) {
          reject(error);
        } else if (!response.success) {
          reject(new Error(response.message));
        } else {
          resolve(response);
        }
      });
    });
  }

  /**
   * Close the client connection
   */
  close() {
    this.client.close();
  }
}

module.exports = EventServiceClient;
