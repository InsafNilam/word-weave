// post-service/repository/post_repository.go
package repository

import (
	"errors"
	"post-service/models"

	"gorm.io/gorm"
)

type PostRepository interface {
	Create(post *models.Post) error
	GetByID(id uint) (*models.Post, error)
	GetBySlug(slug string) (*models.Post, error)
	Update(post *models.Post) error
	Delete(id uint, userID string) error
	List(page, limit int, category string, userID string) ([]models.Post, int64, error)
	IncrementVisit(id uint) error
	GetFeatured(limit int) ([]models.Post, error)
	GetByCategory(category string, page, limit int) ([]models.Post, int64, error)
	GetByUser(userID string, page, limit int) ([]models.Post, int64, error)
	SearchPosts(query string, page int, limit int) ([]models.Post, int64, error)
	CountPosts(user_id, category string, is_featured bool) (int64, error)
	DeletePosts(ids []uint32, userIds []string) error
}

type postRepository struct {
	db *gorm.DB
}

func NewPostRepository(db *gorm.DB) PostRepository {
	return &postRepository{db: db}
}

func (r *postRepository) Create(post *models.Post) error {
	return r.db.Create(post).Error
}

func (r *postRepository) GetByID(id uint) (*models.Post, error) {
	var post models.Post
	err := r.db.First(&post, id).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("post not found")
		}
		return nil, err
	}
	return &post, nil
}

func (r *postRepository) GetBySlug(slug string) (*models.Post, error) {
	var post models.Post
	err := r.db.Where("slug = ?", slug).First(&post).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("post not found")
		}
		return nil, err
	}
	return &post, nil
}

func (r *postRepository) Update(post *models.Post) error {
	return r.db.Save(post).Error
}

func (r *postRepository) Delete(id uint, userID string) error {
	result := r.db.Where("id = ? AND user_id = ?", id, userID).Delete(&models.Post{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return errors.New("post not found or unauthorized")
	}
	return nil
}

func (r *postRepository) List(page, limit int, category string, userID string) ([]models.Post, int64, error) {
	var posts []models.Post
	var total int64

	query := r.db.Model(&models.Post{})

	if category != "" && category != "all" {
		query = query.Where("category = ?", category)
	}

	if userID != "" {
		query = query.Where("user_id = ?", userID)
	}

	// Get total count
	query.Count(&total)

	// Apply pagination
	offset := (page - 1) * limit
	err := query.Offset(offset).Limit(limit).Order("created_at DESC").Find(&posts).Error

	return posts, total, err
}

func (r *postRepository) IncrementVisit(id uint) error {
	return r.db.Model(&models.Post{}).Where("id = ?", id).Update("visit", gorm.Expr("visit + ?", 1)).Error
}

func (r *postRepository) GetFeatured(limit int) ([]models.Post, error) {
	var posts []models.Post
	err := r.db.Where("is_featured = ?", true).Order("created_at DESC").Limit(limit).Find(&posts).Error
	return posts, err
}

func (r *postRepository) GetByCategory(category string, page, limit int) ([]models.Post, int64, error) {
	var posts []models.Post
	var total int64

	query := r.db.Model(&models.Post{}).Where("category = ?", category)

	// Get total count
	query.Count(&total)

	// Apply pagination
	offset := (page - 1) * limit
	err := query.Offset(offset).Limit(limit).Order("created_at DESC").Find(&posts).Error

	return posts, total, err
}

func (r *postRepository) GetByUser(userID string, page, limit int) ([]models.Post, int64, error) {
	var posts []models.Post
	var total int64

	query := r.db.Model(&models.Post{}).Where("user_id = ?", userID)

	// Get total count
	query.Count(&total)

	// Apply pagination
	offset := (page - 1) * limit
	err := query.Offset(offset).Limit(limit).Order("created_at DESC").Find(&posts).Error

	return posts, total, err
}

func (r *postRepository) SearchPosts(query string, page int, limit int) ([]models.Post, int64, error) {
	var posts []models.Post
	var total int64

	if query == "" {
		return nil, 0, errors.New("search query cannot be empty")
	}

	searchQuery := "%" + query + "%"

	// Build the query with search conditions
	dbQuery := r.db.Model(&models.Post{}).
		Where("title LIKE ?", searchQuery)

	// Get total count
	dbQuery.Count(&total)

	// Apply pagination
	offset := (page - 1) * limit
	err := dbQuery.Offset(offset).Limit(limit).Order("created_at DESC").Find(&posts).Error

	return posts, total, err
}

func (r *postRepository) CountPosts(user_id, category string, is_featured bool) (int64, error) {
	var count int64
	query := r.db.Model(&models.Post{})

	if user_id != "" {
		query = query.Where("user_id = ?", user_id)
	}

	if category != "" {
		query = query.Where("category = ?", category)
	}

	if is_featured {
		query = query.Where("is_featured = ?", is_featured)
	}

	err := query.Count(&count).Error
	if err != nil {
		return 0, err
	}

	return count, nil
}

func (r *postRepository) DeletePosts(ids []uint32, userIds []string) error {
	if len(ids) == 0 || len(userIds) == 0 {
		return errors.New("ids and userIds cannot be empty")
	}

	result := r.db.Where("id IN ? AND user_id IN ?", ids, userIds).Delete(&models.Post{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return errors.New("no posts found for the given ids and userIds")
	}
	return nil
}
