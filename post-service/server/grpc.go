package server

import (
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"post-service/config"
	"post-service/proto/postpb"
	"post-service/repository"
	"post-service/service"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
	"gorm.io/gorm"
)

func StartGRPCServer(cfg *config.Config, db *gorm.DB) {
	// Initialize repository
	postRepo := repository.NewPostRepository(db)

	// Initialize service
	postService := service.NewPostServiceServer(postRepo)

	// Create gRPC server
	grpcServer := grpc.NewServer()

	// Register gRPC service
	postpb.RegisterPostServiceServer(grpcServer, postService)

	// Enable reflection for debugging
	reflection.Register(grpcServer)

	// Setup listener
	address := fmt.Sprintf(":%s", cfg.GRPCPort)
	listener, err := net.Listen("tcp", address)
	if err != nil {
		log.Fatalf("❌ Failed to listen on %s: %v", address, err)
	}

	// Handle graceful shutdown
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	// Run gRPC server in a goroutine
	go func() {
		log.Printf("🚀 Post gRPC server running on %s", address)
		if err := grpcServer.Serve(listener); err != nil {
			log.Fatalf("❌ Failed to serve gRPC server: %v", err)
		}
	}()

	// Wait for shutdown signal
	<-stop
	log.Println("\n🛑 Shutting down Post gRPC server...")

	// Graceful stop
	grpcServer.GracefulStop()
	log.Println("✅ Post gRPC server stopped gracefully")
}
