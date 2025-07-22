package models

import "time"

type Post struct {
	ID         uint      `json:"id" gorm:"primaryKey;autoIncrement"`
	UserID     string    `json:"user_id" gorm:"not null;index"`
	Img        string    `json:"img" gorm:"type:text"`
	Title      string    `json:"title" gorm:"not null;type:varchar(255)"`
	Slug       string    `json:"slug" gorm:"not null;unique;type:varchar(255);index"`
	Desc       string    `json:"desc" gorm:"type:text"`
	Category   string    `json:"category" gorm:"default:'general';type:varchar(100);index"`
	Content    string    `json:"content" gorm:"not null;type:text"`
	IsFeatured bool      `json:"is_featured" gorm:"default:false;index"`
	Visit      uint      `json:"visit" gorm:"default:0"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

func (Post) TableName() string {
	return "posts"
}
