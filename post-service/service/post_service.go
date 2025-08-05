package service

import (
	"context"
	"fmt"
	"strings"
	"time"

	"post-service/models"
	eventpb "post-service/protos/eventpb"
	pb "post-service/protos/postpb"
	"post-service/repository"

	event_client "post-service/clients"

	"google.golang.org/protobuf/types/known/timestamppb"
)

type PostServiceServer struct {
	pb.UnimplementedPostServiceServer
	repo        repository.PostRepository
	eventClient *event_client.EventServiceClient
}

func NewPostServiceServer(repo repository.PostRepository, eventClient *event_client.EventServiceClient) *PostServiceServer {
	return &PostServiceServer{repo: repo, eventClient: eventClient}
}

func (s *PostServiceServer) CreatePost(ctx context.Context, req *pb.CreatePostRequest) (*pb.PostResponse, error) {
	// Generate slug from title if not provided
	slug := req.Slug
	if slug == "" {
		slug = generateSlug(req.Title)
	}

	post := &models.Post{
		UserID:     req.UserId,
		Img:        req.Img,
		Title:      req.Title,
		Slug:       slug,
		Desc:       req.Desc,
		Category:   req.Category,
		Content:    req.Content,
		IsFeatured: req.IsFeatured,
	}

	err := s.repo.Create(post)
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to create post: %v", err),
		}, nil
	}

	// 📤 Publish domain event
	_, err = s.eventClient.PublishEvent(ctx, &eventpb.PublishEventRequest{
		AggregateId:   fmt.Sprintf("%d", post.ID),
		AggregateType: "post",
		EventType:     "post.created",
		EventData:     fmt.Sprintf(`{"title":"%s","userId":"%s"}`, post.Title, post.UserID),
		Metadata:      fmt.Sprintf(`{"user_id":"%s","created_at":"%s"}`, req.UserId, time.Now().UTC().Format(time.RFC3339)),
	})

	if err != nil {
		// Log but don't fail post creation
		fmt.Printf("⚠️ Failed to publish event: %v\n", err)
	}

	return &pb.PostResponse{
		Post:    s.modelToProto(post),
		Success: true,
		Message: "Post created successfully",
	}, nil
}

func (s *PostServiceServer) GetPost(ctx context.Context, req *pb.GetPostRequest) (*pb.PostResponse, error) {
	post, err := s.repo.GetByID(uint(req.Id))
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: err.Error(),
		}, nil
	}

	// Increment visit count
	err = s.repo.IncrementVisit(uint(req.Id))
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to increment visit: %v", err),
		}, nil
	}

	return &pb.PostResponse{
		Post:    s.modelToProto(post),
		Success: true,
		Message: "Post retrieved successfully",
	}, nil
}

func (s *PostServiceServer) GetPostBySlug(ctx context.Context, req *pb.GetPostBySlugRequest) (*pb.PostResponse, error) {
	post, err := s.repo.GetBySlug(req.Slug)
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: err.Error(),
		}, nil
	}

	// Increment visit count
	err = s.repo.IncrementVisit(uint(post.ID))
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to increment visit: %v", err),
		}, nil
	}

	return &pb.PostResponse{
		Post:    s.modelToProto(post),
		Success: true,
		Message: "Post retrieved successfully",
	}, nil
}

func (s *PostServiceServer) UpdatePost(ctx context.Context, req *pb.UpdatePostRequest) (*pb.PostResponse, error) {
	existingPost, err := s.repo.GetByID(uint(req.Id))
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: err.Error(),
		}, nil
	}

	// Check if user owns the post
	if existingPost.UserID != req.UserId {
		return &pb.PostResponse{
			Success: false,
			Message: "Unauthorized to update this post",
		}, nil
	}

	// Update fields
	existingPost.Img = req.Img
	existingPost.Title = req.Title
	existingPost.Slug = req.Slug
	existingPost.Desc = req.Desc
	existingPost.Category = req.Category
	existingPost.Content = req.Content
	existingPost.IsFeatured = req.IsFeatured

	err = s.repo.Update(existingPost)
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to update post: %v", err),
		}, nil
	}

	// 📤 Publish domain event
	_, err = s.eventClient.PublishEvent(ctx, &eventpb.PublishEventRequest{
		AggregateId:   fmt.Sprintf("%d", existingPost.ID),
		AggregateType: "post",
		EventType:     "post.updated",
		EventData:     fmt.Sprintf(`{"title":"%s","userId":"%s"}`, existingPost.Title, existingPost.UserID),
		Metadata:      fmt.Sprintf(`{"user_id":"%s","updated_at":"%s"}`, req.UserId, time.Now().UTC().Format(time.RFC3339)),
	})

	if err != nil {
		// Log but don't fail post update
		fmt.Printf("⚠️ Failed to publish event: %v\n", err)
	}

	return &pb.PostResponse{
		Post:    s.modelToProto(existingPost),
		Success: true,
		Message: "Post updated successfully",
	}, nil
}

func (s *PostServiceServer) DeletePost(ctx context.Context, req *pb.DeletePostRequest) (*pb.DeletePostResponse, error) {
	err := s.repo.Delete(uint(req.Id), req.UserId)
	if err != nil {
		return &pb.DeletePostResponse{
			Success: false,
			Message: err.Error(),
		}, nil
	}

	// 📤 Publish domain event
	_, err = s.eventClient.PublishEvent(ctx, &eventpb.PublishEventRequest{
		AggregateId:   fmt.Sprintf("%d", req.Id),
		AggregateType: "post",
		EventType:     "post.deleted",
		EventData:     fmt.Sprintf(`{"id":%d,"userId":"%s"}`, req.Id, req.UserId),
		Metadata:      fmt.Sprintf(`{"user_id":"%s","deleted_at":"%s"}`, req.UserId, time.Now().UTC().Format(time.RFC3339)),
	})

	if err != nil {
		// Log but don't fail post deletion
		fmt.Printf("⚠️ Failed to publish event: %v\n", err)
	}

	return &pb.DeletePostResponse{
		Success: true,
		Message: "Post deleted successfully",
	}, nil
}

func (s *PostServiceServer) ListPosts(ctx context.Context, req *pb.ListPostsRequest) (*pb.ListPostsResponse, error) {
	page := int(req.Page)
	limit := int(req.Limit)

	if page <= 0 {
		page = 1
	}
	if limit <= 0 {
		limit = 10
	}
	if limit > 100 {
		limit = 100 // Max limit
	}

	posts, total, err := s.repo.List(page, limit, req.Category, req.UserId)
	if err != nil {
		return &pb.ListPostsResponse{
			Success: false,
		}, nil
	}

	protoPosts := make([]*pb.Post, len(posts))
	for i, post := range posts {
		protoPosts[i] = s.modelToProto(&post)
	}

	return &pb.ListPostsResponse{
		Posts:   protoPosts,
		Total:   uint32(total),
		Page:    uint32(page),
		Limit:   uint32(limit),
		Success: true,
	}, nil
}

func (s *PostServiceServer) IncrementVisit(ctx context.Context, req *pb.IncrementVisitRequest) (*pb.PostResponse, error) {
	err := s.repo.IncrementVisit(uint(req.Id))
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to increment visit: %v", err),
		}, nil
	}

	// Get updated post
	post, err := s.repo.GetByID(uint(req.Id))
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: err.Error(),
		}, nil
	}

	return &pb.PostResponse{
		Post:    s.modelToProto(post),
		Success: true,
		Message: "Visit count incremented successfully",
	}, nil
}

func (s *PostServiceServer) GetFeaturedPosts(ctx context.Context, req *pb.GetFeaturedPostsRequest) (*pb.ListPostsResponse, error) {
	limit := int(req.Limit)
	if limit <= 0 {
		limit = 5
	}
	if limit > 50 {
		limit = 50
	}

	posts, err := s.repo.GetFeatured(limit)
	if err != nil {
		return &pb.ListPostsResponse{
			Success: false,
		}, nil
	}

	protoPosts := make([]*pb.Post, len(posts))
	for i, post := range posts {
		protoPosts[i] = s.modelToProto(&post)
	}

	return &pb.ListPostsResponse{
		Posts:   protoPosts,
		Total:   uint32(len(posts)),
		Success: true,
	}, nil
}

func (s *PostServiceServer) GetPostsByCategory(ctx context.Context, req *pb.GetPostsByCategoryRequest) (*pb.ListPostsResponse, error) {
	page := int(req.Page)
	limit := int(req.Limit)

	if page <= 0 {
		page = 1
	}
	if limit <= 0 {
		limit = 10
	}
	if limit > 100 {
		limit = 100
	}

	posts, total, err := s.repo.GetByCategory(req.Category, page, limit)
	if err != nil {
		return &pb.ListPostsResponse{
			Success: false,
		}, nil
	}

	protoPosts := make([]*pb.Post, len(posts))
	for i, post := range posts {
		protoPosts[i] = s.modelToProto(&post)
	}

	return &pb.ListPostsResponse{
		Posts:   protoPosts,
		Total:   uint32(total),
		Page:    uint32(page),
		Limit:   uint32(limit),
		Success: true,
	}, nil
}

func (s *PostServiceServer) GetPostsByUser(ctx context.Context, req *pb.GetPostsByUserRequest) (*pb.ListPostsResponse, error) {
	page := int(req.Page)
	limit := int(req.Limit)

	if page <= 0 {
		page = 1
	}
	if limit <= 0 {
		limit = 10
	}
	if limit > 100 {
		limit = 100
	}

	posts, total, err := s.repo.GetByUser(req.UserId, page, limit)
	if err != nil {
		return &pb.ListPostsResponse{
			Success: false,
		}, nil
	}

	protoPosts := make([]*pb.Post, len(posts))
	for i, post := range posts {
		protoPosts[i] = s.modelToProto(&post)
	}

	return &pb.ListPostsResponse{
		Posts:   protoPosts,
		Total:   uint32(total),
		Page:    uint32(page),
		Limit:   uint32(limit),
		Success: true,
	}, nil
}

func (s *PostServiceServer) SearchPosts(ctx context.Context, req *pb.SearchPostsRequest) (*pb.ListPostsResponse, error) {
	page := int(req.Page)
	limit := int(req.Limit)

	if page <= 0 {
		page = 1
	}
	if limit <= 0 {
		limit = 10
	}
	if limit > 100 {
		limit = 100
	}

	posts, total, err := s.repo.SearchPosts(req.Query, page, limit)
	if err != nil {
		return &pb.ListPostsResponse{
			Success: false,
		}, nil
	}

	protoPosts := make([]*pb.Post, len(posts))
	for i, post := range posts {
		protoPosts[i] = s.modelToProto(&post)
	}

	return &pb.ListPostsResponse{
		Posts:   protoPosts,
		Total:   uint32(total),
		Page:    uint32(page),
		Limit:   uint32(limit),
		Success: true,
	}, nil
}

func (s *PostServiceServer) CountPosts(ctx context.Context, req *pb.CountPostsRequest) (*pb.CountPostsResponse, error) {
	count, err := s.repo.CountPosts(req.UserId, req.Category, req.IsFeatured)
	if err != nil {
		return &pb.CountPostsResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to count posts: %v", err),
		}, nil
	}

	return &pb.CountPostsResponse{
		Total:   uint32(count),
		Success: true,
	}, nil
}

func (s *PostServiceServer) DeletePosts(ctx context.Context, req *pb.DeletePostsRequest) (*pb.DeletePostResponse, error) {
	err := s.repo.DeletePosts(req.Ids, req.UserIds)
	if err != nil {
		return &pb.DeletePostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to delete posts: %v", err),
		}, nil
	}

	// 📤 Publish domain event for each deleted post
	for _, id := range req.Ids {
		_, err = s.eventClient.PublishEvent(ctx, &eventpb.PublishEventRequest{
			AggregateId:   fmt.Sprintf("%d", id),
			AggregateType: "post",
			EventType:     "post.deleted",
			EventData:     fmt.Sprintf(`{"id":%d,"userId":"%s"}`, id, req.UserIds),
			Metadata:      fmt.Sprintf(`{"user_id":"%s","deleted_at":"%s"}`, req.UserIds, time.Now().UTC().Format(time.RFC3339)),
		})

		if err != nil {
			fmt.Printf("⚠️ Failed to publish delete event for post %d: %v\n", id, err)
		}
	}

	return &pb.DeletePostResponse{
		Success: true,
		Message: "Posts deleted successfully",
	}, nil
}

// Helper function to convert model to proto
func (s *PostServiceServer) modelToProto(post *models.Post) *pb.Post {
	return &pb.Post{
		Id:         uint32(post.ID),
		UserId:     post.UserID,
		Img:        post.Img,
		Title:      post.Title,
		Slug:       post.Slug,
		Desc:       post.Desc,
		Category:   post.Category,
		Content:    post.Content,
		IsFeatured: post.IsFeatured,
		Visit:      uint32(post.Visit),
		CreatedAt:  timestamppb.New(post.CreatedAt),
		UpdatedAt:  timestamppb.New(post.UpdatedAt),
	}
}

// Helper function to generate slug from title
func generateSlug(title string) string {
	slug := strings.ToLower(title)
	slug = strings.ReplaceAll(slug, " ", "-")
	slug = strings.ReplaceAll(slug, "_", "-")
	// Remove special characters (basic implementation)
	allowedChars := "abcdefghijklmnopqrstuvwxyz0123456789-"
	var result strings.Builder
	for _, char := range slug {
		if strings.ContainsRune(allowedChars, char) {
			result.WriteRune(char)
		}
	}
	slug = result.String()

	// Add timestamp to ensure uniqueness
	timestamp := time.Now().Unix()
	return fmt.Sprintf("%s-%d", slug, timestamp)
}
