"""gRPC server implementation for the media service."""
import signal
import sys
from concurrent import futures
import grpc
from grpc_reflection.v1alpha import reflection

from src.generated import media_pb2, media_pb2_grpc
from src.services.media_service import MediaServiceImpl
from src.grpc.interceptors import LoggingInterceptor, ErrorHandlingInterceptor
from src.config.settings import settings
from src.utils.logger import configure_logging, get_logger


class MediaServiceServer:
    """Production-ready gRPC server for media service."""
    
    def __init__(self):
        self.logger = get_logger("MediaServiceServer")
        self.server = None
        
    def create_server(self) -> grpc.Server:
        """Create and configure the gRPC server."""
        # Create interceptors
        interceptors = [
            LoggingInterceptor(),
            ErrorHandlingInterceptor(),
        ]
        
        # Create server with thread pool
        server = grpc.server(
            futures.ThreadPoolExecutor(max_workers=settings.max_workers),
            interceptors=interceptors,
            options=[
                ('grpc.keepalive_time_ms', 30000),
                ('grpc.keepalive_timeout_ms', 5000),
                ('grpc.keepalive_permit_without_calls', True),
                ('grpc.http2.max_pings_without_data', 0),
                ('grpc.http2.min_time_between_pings_ms', 10000),
                ('grpc.http2.min_ping_interval_without_data_ms', 300000),
                ('grpc.max_connection_idle_ms', 300000),
                ('grpc.max_connection_age_ms', 300000),
                ('grpc.max_connection_age_grace_ms', 30000),
                ('grpc.max_receive_message_length', 100 * 1024 * 1024),  # 100MB
                ('grpc.max_send_message_length', 100 * 1024 * 1024),     # 100MB
            ]
        )
        
        # Add MediaService
        media_pb2_grpc.add_MediaServiceServicer_to_server(
            MediaServiceImpl(), server
        )
        
        # Enable reflection for development
        if settings.environment == "development":
            SERVICE_NAMES = (
                media_pb2.DESCRIPTOR.services_by_name['MediaService'].full_name,
                reflection.SERVICE_NAME,
            )
            reflection.enable_server_reflection(SERVICE_NAMES, server)
            self.logger.info("gRPC reflection enabled")
        
        # Add port
        listen_addr = f"{settings.grpc_host}:{settings.grpc_port}"
        server.add_insecure_port(listen_addr)
        
        self.logger.info(
            "gRPC server configured",
            address=listen_addr,
            max_workers=settings.max_workers,
            environment=settings.environment
        )
        
        return server
    
    def start(self):
        """Start the gRPC server."""
        self.server = self.create_server()
        self.server.start()
        
        self.logger.info(
            "Media service started",
            host=settings.grpc_host,
            port=settings.grpc_port,
            environment=settings.environment
        )
        
        # Setup signal handlers for graceful shutdown
        def signal_handler(signum, frame):
            self.logger.info("Received shutdown signal", signal=signum)
            self.stop()
            sys.exit(0)
        
        signal.signal(signal.SIGTERM, signal_handler)
        signal.signal(signal.SIGINT, signal_handler)
        
    def stop(self, grace_period: int = 30):
        """Stop the gRPC server gracefully."""
        if self.server:
            self.logger.info("Shutting down server", grace_period=grace_period)
            self.server.stop(grace_period)
            self.logger.info("Server shutdown complete")
    
    def wait_for_termination(self):
        """Wait for server termination."""
        if self.server:
            self.server.wait_for_termination()


def main():
    """Main entry point for the server."""
    # Configure logging
    configure_logging()
    logger = get_logger("main")
    
    logger.info(
        "Starting media service",
        version="1.0.0",
        environment=settings.environment,
        imagekit_endpoint=settings.imagekit_url_endpoint
    )
    
    # Create and start server
    server = MediaServiceServer()
    try:
        server.start()
        logger.info("Server ready to accept connections")
        server.wait_for_termination()
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt")
        server.stop()
    except Exception as e:
        logger.error("Server error", error=str(e))
        server.stop()
        sys.exit(1)


if __name__ == "__main__":
    main()