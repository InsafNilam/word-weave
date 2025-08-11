# Comment Service

## Overview

This service manages user comments on posts and exposes a gRPC API for CRUD operations and querying comments. It uses **.NET**, **Entity Framework Core** with **MySQL** (via Pomelo), and gRPC for inter-service communication.

---

## Features

- Create, read, update, delete comments
- Query comments by post or by user with pagination
- Bulk delete comments
- Get comment counts per post
- gRPC interface for external communication
- EF Core migrations to manage database schema

---

## Proto Definitions

The service uses Protocol Buffers v3 syntax (`proto3`) with the C# namespace `CommentService.Grpc`.

Example snippet of the proto file defining the service and messages:

```proto
syntax = "proto3";

option csharp_namespace = "CommentService.Grpc";

package comment;

// Comment Service RPCs
service CommentService {
  rpc CreateComment(CreateCommentRequest) returns (CommentResponse);
  rpc GetComment(GetCommentRequest) returns (CommentResponse);
  rpc GetCommentsByPost(GetCommentsByPostRequest) returns (GetCommentsResponse);
  rpc GetCommentsByUser(GetCommentsByUserRequest) returns (GetCommentsResponse);
  rpc UpdateComment(UpdateCommentRequest) returns (CommentResponse);
  rpc DeleteComment(DeleteCommentRequest) returns (DeleteCommentResponse);
  rpc GetCommentCount(GetCommentCountRequest) returns (GetCommentCountResponse);
  rpc DeleteComments(DeleteCommentsRequest) returns (DeleteCommentResponse);
}

// Message definitions...
```

---

## External gRPC Clients

The service also communicates with external microservices (User, Post, Event services) via gRPC clients using the following proto definitions in namespace `CommentService.ExternalGrpc`.

Example services:

- UserService
- PostService
- EventService (for publishing and subscribing to events)

---

## Getting Started

### Prerequisites

- [.NET SDK](https://dotnet.microsoft.com/download) (6.0 or later recommended)
- MySQL database server
- Protobuf compiler (`protoc`)
- `dotnet-ef` tool installed globally

### Install `dotnet-ef` tool

```bash
dotnet tool install --global dotnet-ef
```

Or update it if already installed:

```bash
dotnet tool update --global dotnet-ef
```

### Add required EF Core packages

```bash
dotnet add package Microsoft.EntityFrameworkCore.Design
dotnet add package Microsoft.EntityFrameworkCore.Tools
dotnet add package Pomelo.EntityFrameworkCore.MySql
```

---

## Database Migrations

Create a new migration:

```bash
dotnet ef migrations add InitialCreate
```

Remove the last migration if needed:

```bash
dotnet ef migrations remove
```

For projects with separate startup and project files:

```bash
dotnet ef migrations add InitialCreate --project CommentService --startup-project CommentService
```

---

## Cleaning Build Cache

If you have issues with cached build files, remove them with:

```bash
git rm -r --cached obj/
```

---

## Project Structure

```
CommentService/
├── Protos/
│   ├── comment.proto           # Main comment service proto
│   ├── external.proto          # External grpc client proto definitions
├── Migrations/                 # EF Core migrations
├── Services/                   # gRPC service implementations
├── CommentService.csproj
├── Program.cs
└── README.md
```

---

## Running the Service

1. Configure your MySQL connection string in `appsettings.json` or environment variables.
2. Apply migrations:

```bash
dotnet ef database update
```

3. Run the service:

```bash
dotnet run
```

The gRPC server will start listening for requests defined in the proto files.

---

## Contributing

Feel free to submit issues or pull requests.

---

## License

MIT License

---

## Contact

Your Name — [insafnilam.2000@gmail.com](mailto:insafnilam.2000@gmail.com)

---
