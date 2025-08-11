"""gRPC server interceptors for logging and error handling."""
import time
from typing import Callable, Any
import grpc

from src.utils.logger import get_logger


class LoggingInterceptor(grpc.ServerInterceptor):
    """Interceptor for logging gRPC requests and responses."""
    
    def __init__(self):
        self.logger = get_logger("gRPC.LoggingInterceptor")
    
    def intercept_service(self, continuation: Callable, handler_call_details: grpc.HandlerCallDetails):
        """Intercept and log gRPC service calls."""
        method_name = handler_call_details.method.split('/')[-1]
        start_time = time.time()
        
        # Log request start
        self.logger.info(
            "gRPC request started",
            method=method_name,
            full_method=handler_call_details.method
        )
        
        # Get the original handler
        handler = continuation(handler_call_details)
        if handler is None:
            return None
        
        def logging_wrapper(request, context):
            try:
                # Call the actual method
                response = handler.unary_unary(request, context)
                
                # Log successful completion
                duration = time.time() - start_time
                self.logger.info(
                    "gRPC request completed",
                    method=method_name,
                    duration_ms=round(duration * 1000, 2),
                    status="SUCCESS"
                )
                
                return response
                
            except Exception as e:
                # Log error
                duration = time.time() - start_time
                self.logger.error(
                    "gRPC request failed",
                    method=method_name,
                    duration_ms=round(duration * 1000, 2),
                    error=str(e),
                    status="ERROR"
                )
                raise
        
        # Return a new handler with the wrapped function
        return grpc.unary_unary_rpc_method_handler(
            logging_wrapper,
            request_deserializer=handler.request_deserializer,
            response_serializer=handler.response_serializer
        )


class ErrorHandlingInterceptor(grpc.ServerInterceptor):
    """Interceptor for consistent error handling across gRPC methods."""
    
    def __init__(self):
        self.logger = get_logger("gRPC.ErrorHandlingInterceptor")
    
    def intercept_service(self, continuation: Callable, handler_call_details: grpc.HandlerCallDetails):
        """Intercept and handle gRPC service errors."""
        
        # Get the original handler
        handler = continuation(handler_call_details)
        if handler is None:
            return None
        
        def error_handling_wrapper(request, context):
            try:
                return handler.unary_unary(request, context)
                
            except grpc.RpcError:
                # Re-raise gRPC errors as-is
                raise
                
            except Exception as e:
                # Handle unexpected errors
                method_name = handler_call_details.method.split('/')[-1]
                self.logger.error(
                    "Unhandled error in gRPC method",
                    method=method_name,
                    error=str(e),
                    error_type=type(e).__name__
                )
                
                # Set appropriate gRPC error
                context.set_code(grpc.StatusCode.INTERNAL)
                context.set_details(f"Internal server error: {str(e)}")
                
                # Return empty response or raise based on method expectations
                raise
        
        # Return a new handler with the wrapped function
        return grpc.unary_unary_rpc_method_handler(
            error_handling_wrapper,
            request_deserializer=handler.request_deserializer,
            response_serializer=handler.response_serializer
        )


class MetricsInterceptor(grpc.ServerInterceptor):
    """Interceptor for collecting metrics (optional, for production monitoring)."""
    
    def __init__(self):
        self.logger = get_logger("gRPC.MetricsInterceptor")
        self.request_count = {}
        self.request_duration = {}
    
    def intercept_service(self, continuation: Callable, handler_call_details: grpc.HandlerCallDetails):
        """Intercept and collect metrics for gRPC service calls."""
        method_name = handler_call_details.method.split('/')[-1]
        
        # Get the original handler
        handler = continuation(handler_call_details)
        if handler is None:
            return None
        
        def metrics_wrapper(request, context):
            start_time = time.time()
            
            # Initialize counters
            if method_name not in self.request_count:
                self.request_count[method_name] = 0
                self.request_duration[method_name] = []
            
            self.request_count[method_name] += 1
            
            try:
                response = handler.unary_unary(request, context)
                status = "success"
                return response
                
            except Exception as e:
                status = "error"
                raise
                
            finally:
                # Record duration
                duration = time.time() - start_time
                self.request_duration[method_name].append(duration)
                
                # Log metrics periodically (every 100 requests)
                if self.request_count[method_name] % 100 == 0:
                    avg_duration = sum(self.request_duration[method_name]) / len(self.request_duration[method_name])
                    self.logger.info(
                        "Method metrics",
                        method=method_name,
                        total_requests=self.request_count[method_name],
                        avg_duration_ms=round(avg_duration * 1000, 2)
                    )
                    
                    # Keep only last 1000 durations to prevent memory growth
                    if len(self.request_duration[method_name]) > 1000:
                        self.request_duration[method_name] = self.request_duration[method_name][-1000:]
        
        # Return a new handler with the wrapped function
        return grpc.unary_unary_rpc_method_handler(
            metrics_wrapper,
            request_deserializer=handler.request_deserializer,
            response_serializer=handler.response_serializer
        )