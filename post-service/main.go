package main

import (
	"fmt"
	"log"
	"os"
	"post-service/config"
	"post-service/database"
	"post-service/models"
	"post-service/server"

	"github.com/joho/godotenv"
)

func main() {
	err := godotenv.Load(".env")
	if err != nil {
		// Example: Only fail fatally if we are explicitly in a development environment
		// Otherwise, just warn and rely on system env vars or defaults
		if os.Getenv("APP_ENV") != "production" { // or check for an empty APP_ENV
			log.Printf("WARN: Could not load .env file: %v. Proceeding with system environment variables and defaults.\n", err)
		} else {
			log.Printf("INFO: Not in development mode, .env file not loaded. Relying on system environment variables.\n")
		}
	} else {
		fmt.Println("INFO: .env file loaded successfully.")
	}

	// Load configuration
	cfg := config.LoadConfig()

	// Connect to database
	db, err := database.ConnectDB(cfg)
	if err != nil {
		log.Fatalf("❌ Failed to connect to database: %v", err)
	}

	// Auto-migrate the schema
	err = db.AutoMigrate(&models.Post{})
	if err != nil {
		log.Fatalf("❌ Failed to migrate database: %v", err)
	}

	server.StartGRPCServer(cfg, db)
}
