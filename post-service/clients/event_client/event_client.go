package clients

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	pb "post-service/protos/eventpb"
)

// EventServiceClient wraps the gRPC client for event service
type EventServiceClient struct {
	client pb.EventServiceClient
	conn   *grpc.ClientConn
}

// NewEventServiceClient creates a new event service client
func NewEventServiceClient(serverAddress string) (*EventServiceClient, error) {
	if serverAddress == "" {
		serverAddress = "event-service:50055"
	}

	// Create connection with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	conn, err := grpc.DialContext(ctx, serverAddress,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to event service at %s: %w", serverAddress, err)
	}

	client := pb.NewEventServiceClient(conn)

	return &EventServiceClient{
		client: client,
		conn:   conn,
	}, nil
}

// PublishEvent publishes a domain event
func (c *EventServiceClient) PublishEvent(ctx context.Context, req *pb.PublishEventRequest) (*pb.PublishEventResponse, error) {
	// Marshal event data to JSON
	eventDataJSON, err := json.Marshal(req.EventData)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal event data: %w", err)
	}

	// Marshal metadata to JSON
	metadataJSON, err := json.Marshal(req.Metadata)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal metadata: %w", err)
	}

	// Create gRPC request
	grpcReq := &pb.PublishEventRequest{
		AggregateId:   req.AggregateId,
		AggregateType: req.AggregateType,
		EventType:     req.EventType,
		EventData:     string(eventDataJSON),
		Metadata:      string(metadataJSON),
		CorrelationId: req.CorrelationId,
		CausationId:   req.CausationId,
	}

	// Call the service
	response, err := c.client.PublishEvent(ctx, grpcReq)
	if err != nil {
		return nil, fmt.Errorf("failed to publish event: %w", err)
	}

	if !response.Success {
		return nil, fmt.Errorf("event publishing failed: %s", response.Message)
	}

	return response, nil
}

// GetEvents retrieves events by type or recent events
func (c *EventServiceClient) GetEvents(ctx context.Context, req *pb.GetEventsRequest) ([]*pb.Event, error) {
	// Set defaults
	if req.Limit == 0 {
		req.Limit = 100
	}

	grpcReq := &pb.GetEventsRequest{
		EventType:     req.EventType,
		AggregateType: req.AggregateType,
		Limit:         req.Limit,
		Offset:        req.Offset,
	}

	response, err := c.client.GetEvents(ctx, grpcReq)
	if err != nil {
		return nil, fmt.Errorf("failed to get events: %w", err)
	}

	if !response.Success {
		return nil, fmt.Errorf("get events failed: %s", response.Message)
	}

	return response.Events, nil
}

// GetEventsByAggregate retrieves events for a specific aggregate
func (c *EventServiceClient) GetEventsByAggregate(ctx context.Context, req *pb.GetEventsByAggregateRequest) ([]*pb.Event, error) {
	// Set default
	if req.FromVersion == 0 {
		req.FromVersion = 1
	}

	grpcReq := &pb.GetEventsByAggregateRequest{
		AggregateId:   req.AggregateId,
		AggregateType: req.AggregateType,
		FromVersion:   req.FromVersion,
	}

	response, err := c.client.GetEventsByAggregate(ctx, grpcReq)
	if err != nil {
		return nil, fmt.Errorf("failed to get events by aggregate: %w", err)
	}

	if !response.Success {
		return nil, fmt.Errorf("get events by aggregate failed: %s", response.Message)
	}

	return response.Events, nil
}

// SubscribeToEvents subscribes to events
func (c *EventServiceClient) SubscribeToEvents(ctx context.Context, req *pb.SubscribeToEventsRequest) (*pb.SubscribeToEventsResponse, error) {
	grpcReq := &pb.SubscribeToEventsRequest{
		ConsumerGroup: req.ConsumerGroup,
		EventTypes:    req.EventTypes,
		CallbackUrl:   req.CallbackUrl,
	}

	response, err := c.client.SubscribeToEvents(ctx, grpcReq)
	if err != nil {
		return nil, fmt.Errorf("failed to subscribe to events: %w", err)
	}

	if !response.Success {
		return nil, fmt.Errorf("subscription failed: %s", response.Message)
	}

	return response, nil
}

// Close closes the client connection
func (c *EventServiceClient) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}
