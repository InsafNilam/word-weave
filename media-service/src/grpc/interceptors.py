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
        
        def logging_wrapper(behavior, request_streaming, response_streaming):
            def new_behavior(request_or_iterator, context):
                try:
                    # Call the actual method
                    response = behavior(request_or_iterator, context)
                    
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
            
            return new_behavior
        
        return logging_wrapper(continuation(handler_call_details), False, False)


class ErrorHandlingInterceptor(grpc.ServerInterceptor):
    """Interceptor for consistent error handling across gRPC methods."""
    
    def __init__(self):
        self.logger = get_logger("gRPC.ErrorHandlingInterceptor")
    
    def intercept_service(self, continuation: Callable, handler_call_details: grpc.HandlerCallDetails):
        """Intercept and handle gRPC service errors."""
        
        def error_handling_wrapper(behavior, request_streaming, response_streaming):
            def new_behavior(request_or_iterator, context):
                try:
                    return behavior(request_or_iterator, context)
                    
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
            
            return new_behavior
        
        return error_handling_wrapper(continuation(handler_call_details), False, False)


class MetricsInterceptor(grpc.ServerInterceptor):
    """Interceptor for collecting metrics (optional, for production monitoring)."""
    
    def __init__(self):
        self.logger = get_logger("gRPC.MetricsInterceptor")
        self.request_count = {}
        self.request_duration = {}
    
    def intercept_service(self, continuation: Callable, handler_call_details: grpc.HandlerCallDetails):
        """Intercept and collect metrics for gRPC service calls."""
        method_name = handler_call_details.method.split('/')[-1]
        
        def metrics_wrapper(behavior, request_streaming, response_streaming):
            def new_behavior(request_or_iterator, context):
                start_time = time.time()
                
                # Initialize counters
                if method_name not in self.request_count:
                    self.request_count[method_name] = 0
                    self.request_duration[method_name] = []
                
                self.request_count[method_name] += 1
                
                try:
                    response = behavior(request_or_iterator, context)
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
            
            return new_behavior
        
        return metrics_wrapper(continuation(handler_call_details), False, False)