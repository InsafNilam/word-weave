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

	event_client "post-service/clients/event_client"
	user_client "post-service/clients/user_client"

	"google.golang.org/protobuf/types/known/timestamppb"
)

type PostServiceServer struct {
	pb.UnimplementedPostServiceServer
	repo        repository.PostRepository
	eventClient *event_client.EventServiceClient
	userClient  *user_client.UserServiceClient
}

func NewPostServiceServer(repo repository.PostRepository, eventClient *event_client.EventServiceClient, userClient *user_client.UserServiceClient) *PostServiceServer {
	return &PostServiceServer{repo: repo, eventClient: eventClient, userClient: userClient}
}

func (s *PostServiceServer) CreatePost(ctx context.Context, req *pb.CreatePostRequest) (*pb.PostResponse, error) {
	// Generate slug from title if not provided
	slug := req.Slug
	if slug == "" {
		slug = generateSlug(req.Title)
	}

	// Validate user exists
	if req.UserId != "" {
		exists, err := s.userClient.ValidateUser(ctx, req.UserId)
		if err != nil {
			return &pb.PostResponse{
				Success: false,
				Message: fmt.Sprintf("Failed to validate user: %v", err),
			}, nil
		}
		if !exists {
			return &pb.PostResponse{
				Success: false,
				Message: "User does not exist",
			}, nil
		}
	}

	user, err := s.userClient.GetUser(ctx, req.UserId)
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to get user details: %v", err),
		}, nil
	}

	post := &models.Post{
		UserID:     user.GetId(),
		Img:        req.Img,
		Title:      req.Title,
		Slug:       slug,
		Desc:       req.Desc,
		Category:   req.Category,
		Content:    req.Content,
		IsFeatured: req.IsFeatured,
	}

	err = s.repo.Create(post)
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to create post: %v", err),
		}, nil
	}

	// 📤 Publish domain event
	_, err = s.eventClient.PublishEvent(ctx, &eventpb.PublishEventRequest{
		AggregateId:   fmt.Sprintf("%d", post.ID),
		AggregateType: "Post",
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

	user, err := s.userClient.GetUser(ctx, req.UserId)
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to get user details: %v", err),
		}, nil
	}

	// Check if user owns the post
	if existingPost.UserID != user.GetId() {
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
		AggregateType: "Post",
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

func (s *PostServiceServer) PatchPost(ctx context.Context, req *pb.PatchPostRequest) (*pb.PostResponse, error) {
	// Get existing post
	existingPost, err := s.repo.GetByID(uint(req.Id))
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: fmt.Sprintf("Post not found: %v", err),
		}, nil
	}

	user, err := s.userClient.GetUser(ctx, req.UserId)
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to get user details: %v", err),
		}, nil
	}

	// Check if user owns the post
	if existingPost.UserID != user.GetId() {
		return &pb.PostResponse{
			Success: false,
			Message: "Unauthorized to update this post",
		}, nil
	}

	// Track what fields were updated for event publishing
	updatedFields := make([]string, 0)
	oldValues := make(map[string]interface{})

	// PATCH: Only update fields that are explicitly provided
	if req.Img != nil {
		if existingPost.Img != *req.Img {
			oldValues["img"] = existingPost.Img
			existingPost.Img = *req.Img
			updatedFields = append(updatedFields, "img")
		}
	}

	if req.Title != nil {
		if existingPost.Title != *req.Title {
			oldValues["title"] = existingPost.Title
			existingPost.Title = *req.Title
			updatedFields = append(updatedFields, "title")
		}
	}

	if req.Slug != nil {
		if existingPost.Slug != *req.Slug {
			// Validate slug uniqueness
			if err := s.repo.ValidateSlugUnique(*req.Slug, uint(req.Id)); err != nil {
				return &pb.PostResponse{
					Success: false,
					Message: "Slug already exists",
				}, nil
			}
			oldValues["slug"] = existingPost.Slug
			existingPost.Slug = *req.Slug
			updatedFields = append(updatedFields, "slug")
		}
	}

	if req.Desc != nil {
		if existingPost.Desc != *req.Desc {
			oldValues["desc"] = existingPost.Desc
			existingPost.Desc = *req.Desc
			updatedFields = append(updatedFields, "desc")
		}
	}

	if req.Category != nil {
		if existingPost.Category != *req.Category {
			oldValues["category"] = existingPost.Category
			existingPost.Category = *req.Category
			updatedFields = append(updatedFields, "category")
		}
	}

	if req.Content != nil {
		if existingPost.Content != *req.Content {
			oldValues["content"] = existingPost.Content
			existingPost.Content = *req.Content
			updatedFields = append(updatedFields, "content")
		}
	}

	if req.IsFeatured != nil {
		if existingPost.IsFeatured != *req.IsFeatured {
			oldValues["is_featured"] = existingPost.IsFeatured
			existingPost.IsFeatured = *req.IsFeatured
			updatedFields = append(updatedFields, "is_featured")
		}
	}

	// If no fields were updated, return success without database call
	if len(updatedFields) == 0 {
		return &pb.PostResponse{
			Post:    s.modelToProto(existingPost),
			Success: true,
			Message: "No changes detected",
		}, nil
	}

	// Update the post in database
	err = s.repo.Update(existingPost)
	if err != nil {
		return &pb.PostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to update post: %v", err),
		}, nil
	}

	// 📤 Publish domain event with detailed change information
	eventData := fmt.Sprintf(`{
        "id": "%d",
        "title": "%s",
        "userId": "%s",
        "updatedFields": ["%s"],
        "changes": %s
    }`,
		existingPost.ID,
		existingPost.Title,
		existingPost.UserID,
		strings.Join(updatedFields, `","`),
		s.buildChangesJSON(updatedFields, oldValues, existingPost),
	)

	_, err = s.eventClient.PublishEvent(ctx, &eventpb.PublishEventRequest{
		AggregateId:   fmt.Sprintf("%d", existingPost.ID),
		AggregateType: "Post",
		EventType:     "post.patched",
		EventData:     eventData,
		Metadata:      fmt.Sprintf(`{"user_id":"%s","updated_at":"%s","fields_count":%d}`, req.UserId, time.Now().UTC().Format(time.RFC3339), len(updatedFields)),
	})

	if err != nil {
		// Log but don't fail post update
		fmt.Printf("⚠️ Failed to publish patch event: %v\n", err)
	}

	return &pb.PostResponse{
		Post:    s.modelToProto(existingPost),
		Success: true,
		Message: fmt.Sprintf("Post updated successfully. %d field(s) changed.", len(updatedFields)),
	}, nil
}

func (s *PostServiceServer) DeletePost(ctx context.Context, req *pb.DeletePostRequest) (*pb.DeletePostResponse, error) {
	user, err := s.userClient.GetUser(ctx, req.UserId)
	if err != nil {
		return &pb.DeletePostResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to get user details: %v", err),
		}, nil
	}

	err = s.repo.Delete(uint(req.Id), user.GetId())
	if err != nil {
		return &pb.DeletePostResponse{
			Success: false,
			Message: err.Error(),
		}, nil
	}

	// 📤 Publish domain event
	_, err = s.eventClient.PublishEvent(ctx, &eventpb.PublishEventRequest{
		AggregateId:   fmt.Sprintf("%d", req.Id),
		AggregateType: "Post",
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

	var userId string
	if req.UserId != "" {
		user, err := s.userClient.GetUser(ctx, req.UserId)
		if err != nil {
			return &pb.ListPostsResponse{
				Success: false,
			}, nil
		}
		userId = user.GetId()
	}

	posts, total, err := s.repo.List(page, limit, req.Category, userId)
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

	user, err := s.userClient.GetUser(ctx, req.UserId)
	if err != nil {
		return &pb.ListPostsResponse{
			Success: false,
		}, nil
	}

	posts, total, err := s.repo.GetByUser(user.GetId(), page, limit)
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

	// Safely extract string values from potentially nil pointers
	query := safeStringDeref(req.Query)
	category := safeStringDeref(req.Category)
	title := safeStringDeref(req.Title)
	slug := safeStringDeref(req.Slug)
	author := safeStringDeref(req.Author)

	fmt.Println("Searching posts with the following parameters:")
	fmt.Printf("Query: %s\n", query)
	fmt.Printf("Category: %s\n", category)
	fmt.Printf("Title: %s\n", title)
	fmt.Printf("Slug: %s\n", slug)
	fmt.Printf("Author: %s\n", author)
	fmt.Printf("Sort By: %s\n", req.SortBy)
	fmt.Printf("Sort Order: %s\n", req.SortOrder)
	fmt.Printf("Page: %d\n", page)
	fmt.Printf("Limit: %d\n", limit)

	posts, total, err := s.repo.SearchPosts(query, category, title, slug, author, req.SortBy, req.SortOrder, page, limit)
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
	var mongoUserIds []string
	if len(req.UserIds) > 0 {
		mongoUserIds = make([]string, 0, len(req.UserIds))
		for _, userId := range req.UserIds {
			user, err := s.userClient.GetUser(ctx, userId)
			if err != nil {
				return &pb.DeletePostResponse{
					Success: false,
					Message: fmt.Sprintf("Failed to get user details for user %s: %v", userId, err),
				}, nil
			}
			mongoUserIds = append(mongoUserIds, user.GetId())
		}
	}

	err := s.repo.DeletePosts(req.Ids, mongoUserIds)
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
			AggregateType: "Post",
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

func (s *PostServiceServer) buildChangesJSON(updatedFields []string, oldValues map[string]interface{}, newPost *models.Post) string {
	changes := make([]string, 0, len(updatedFields))

	for _, field := range updatedFields {
		var newValue interface{}
		switch field {
		case "img":
			newValue = newPost.Img
		case "title":
			newValue = newPost.Title
		case "slug":
			newValue = newPost.Slug
		case "desc":
			newValue = newPost.Desc
		case "category":
			newValue = newPost.Category
		case "content":
			newValue = newPost.Content
		case "is_featured":
			newValue = newPost.IsFeatured
		}

		change := fmt.Sprintf(`"%s":{"old":"%v","new":"%v"}`, field, oldValues[field], newValue)
		changes = append(changes, change)
	}

	return fmt.Sprintf("{%s}", strings.Join(changes, ","))
}

// Helper function to convert model to proto
func (s *PostServiceServer) modelToProto(post *models.Post) *pb.Post {
	user, err := s.userClient.GetLocalUser(context.Background(), post.UserID)

	if err != nil {
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
			Author:     nil,
			CreatedAt:  timestamppb.New(post.CreatedAt),
			UpdatedAt:  timestamppb.New(post.UpdatedAt),
		}
	}

	// Create the protobuf Post object
	pbPost := &pb.Post{
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

	// Set the author from the user response
	if user != nil {
		pbPost.Author = &pb.Author{
			Id:       user.Id,
			Username: user.Username,
			Email:    user.Email,
		}
	}

	return pbPost
}

func safeStringDeref(ptr *string) string {
	if ptr == nil {
		return ""
	}
	return *ptr
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
