package clients

import (
	"context"
	"fmt"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	pb "post-service/protos/userpb" // adjust the import path
)

// UserServiceClient wraps the gRPC client for user service
type UserServiceClient struct {
	client pb.UserServiceClient
	conn   *grpc.ClientConn
}

// NewUserServiceClient initializes a new UserServiceClient
func NewUserServiceClient(serverAddress string) (*UserServiceClient, error) {
	if serverAddress == "" {
		serverAddress = "user-service:50051" // default if none provided
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	conn, err := grpc.DialContext(ctx, serverAddress,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to user service at %s: %w", serverAddress, err)
	}

	client := pb.NewUserServiceClient(conn)

	return &UserServiceClient{
		client: client,
		conn:   conn,
	}, nil
}

// GetUser fetches a user by ID via gRPC
func (c *UserServiceClient) GetUser(ctx context.Context, userID string) (*pb.User, error) {
	req := &pb.GetUserRequest{
		UserId: userID,
	}

	resp, err := c.client.GetUser(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("failed to call GetUser: %w", err)
	}

	if !resp.Success {
		return nil, fmt.Errorf("user not found or error: %s", resp.Message)
	}

	return resp.User, nil
}

func (c *UserServiceClient) ValidateUser(ctx context.Context, userID string) (bool, error) {
	req := &pb.GetUserRequest{
		UserId: userID,
	}

	resp, err := c.client.GetUser(ctx, req)
	if err != nil {
		return false, fmt.Errorf("failed to call GetUser: %w", err)
	}

	if !resp.Success {
		return false, fmt.Errorf("user not found or error: %s", resp.Message)
	}

	return resp.Success, nil
}

// Close closes the client connection
func (c *UserServiceClient) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}
