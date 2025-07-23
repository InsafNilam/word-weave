using CommentService.GrpcServices;
using CommentService.Models;
using CommentService.Repositories;
using CommentService.Services;
using Microsoft.EntityFrameworkCore;
using Serilog;
using System.Reflection;

var builder = WebApplication.CreateBuilder(args);

// Configure logging with Serilog
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .WriteTo.File("logs/comment-service-.txt", rollingInterval: RollingInterval.Day)
    .CreateLogger();

builder.Host.UseSerilog();

// Add services to the container
builder.Services.AddGrpc(options =>
{
    options.EnableDetailedErrors = builder.Environment.IsDevelopment();
    options.MaxReceiveMessageSize = 4 * 1024 * 1024; // 4MB
    options.MaxSendMessageSize = 4 * 1024 * 1024; // 4MB
});

builder.Services.AddGrpcReflection();

// Database configuration
builder.Services.AddDbContext<CommentDbContext>(options =>
{
    var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
    options.UseMySql(connectionString, ServerVersion.AutoDetect(connectionString), mysqlOptions =>
    {
        mysqlOptions.MigrationsAssembly(Assembly.GetExecutingAssembly().GetName().Name);
        mysqlOptions.EnableRetryOnFailure(
            maxRetryCount: 5,
            maxRetryDelay: TimeSpan.FromSeconds(30),
            errorNumbersToAdd: null);
    });

    if (builder.Environment.IsDevelopment())
    {
        options.EnableSensitiveDataLogging();
        options.EnableDetailedErrors();
    }
});

// Redis configuration
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
    options.InstanceName = "CommentService";
});

// Register services
builder.Services.AddScoped<ICommentRepository, CommentRepository>();
builder.Services.AddScoped<IExternalServices, ExternalServices>();

// Health checks
builder.Services.AddHealthChecks()
    .AddMySql(builder.Configuration.GetConnectionString("DefaultConnection")!)
    .AddRedis(builder.Configuration.GetConnectionString("Redis")!)
    .AddCheck("self", () => Microsoft.Extensions.Diagnostics.HealthChecks.HealthCheckResult.Healthy());

// Add CORS
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(builder =>
    {
        builder.AllowAnyOrigin()
               .AllowAnyMethod()
               .AllowAnyHeader()
               .WithExposedHeaders("Grpc-Status", "Grpc-Message", "Grpc-Encoding", "Grpc-Accept-Encoding");
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
    app.MapGrpcReflectionService();
}

app.UseCors();
app.UseRouting();

// Map gRPC services
app.MapGrpcService<CommentGrpcService>();

// Health check endpoints
app.MapHealthChecks("/health");
app.MapHealthChecks("/health/ready");
app.MapHealthChecks("/health/live");

// Default endpoint
app.MapGet("/", () => "Communication with gRPC endpoints must be made through a gRPC client. To learn how to create a client, visit: https://go.microsoft.com/fwlink/?linkid=2086909");

// Database migration
using (var scope = app.Services.CreateScope())
{
    try
    {
        var context = scope.ServiceProvider.GetRequiredService<CommentDbContext>();

        Log.Information("Applying database migrations...");
        await context.Database.MigrateAsync();
        Log.Information("Database migrations completed successfully");
    }
    catch (Exception ex)
    {
        Log.Fatal(ex, "An error occurred while migrating the database");
        throw;
    }
}

// Graceful shutdown handling
var lifetime = app.Services.GetRequiredService<IHostApplicationLifetime>();

lifetime.ApplicationStarted.Register(() =>
{
    Log.Information("🚀 Comment Service started successfully at {Time}", DateTime.UtcNow);
    Log.Information("🌐 Service running on: {Urls}", string.Join(", ", app.Urls));
});

lifetime.ApplicationStopping.Register(() =>
{
    Log.Information("🛑 Comment Service is stopping...");
});

lifetime.ApplicationStopped.Register(() =>
{
    Log.Information("✅ Comment Service stopped gracefully");
    Log.CloseAndFlush();
});

try
{
    Log.Information("Starting Comment Service...");
    await app.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "❌ Comment Service terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}