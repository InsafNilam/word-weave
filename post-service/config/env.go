package config

import (
	"os"
)

type Config struct {
	DBHost              string
	DBPort              string
	DBUser              string
	DBPassword          string
	DBName              string
	GRPCPort            string
	UserServiceAddress  string
	EventServiceAddress string
}

func LoadConfig() *Config {
	return &Config{
		DBHost:              getEnv("DB_HOST", "localhost"),
		DBPort:              getEnv("DB_PORT", "5432"),
		DBUser:              getEnv("DB_USER", "postgres"),
		DBPassword:          getEnv("DB_PASSWORD", "47@n2EEr"),
		DBName:              getEnv("DB_NAME", "post_db"),
		GRPCPort:            getEnv("GRPC_PORT", "50052"),
		UserServiceAddress:  getEnv("USER_SERVICE_ADDRESS", "localhost:50052"),
		EventServiceAddress: getEnv("EVENT_SERVICE_ADDRESS", "localhost:50055"),
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
