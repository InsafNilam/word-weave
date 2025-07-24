using Microsoft.EntityFrameworkCore;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CommentService.Models
{
    [Table("comments")]
    public class Comment
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        [Column("user_id")]
        [MaxLength(255)]
        public string UserId { get; set; } = string.Empty;

        [Required]
        [Column("post_id")]
        public int PostId { get; set; }

        [Required]
        [Column("description")]
        [MaxLength(1000)]
        public string Description { get; set; } = string.Empty;

        [Column("created_at")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("updated_at")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        // Navigation properties for potential future use
        [NotMapped]
        public string? UserName { get; set; }

        [NotMapped]
        public string? PostTitle { get; set; }
    }

    public class CommentDbContext : DbContext
    {
        public CommentDbContext(DbContextOptions<CommentDbContext> options)
        : base(options) { }

        public DbSet<Comment> Comments { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            modelBuilder.Entity<Comment>(entity =>
            {
                entity.HasKey(e => e.Id);

                entity.Property(e => e.UserId)
                    .IsRequired()
                    .HasMaxLength(255);

                entity.Property(e => e.PostId)
                    .IsRequired();

                entity.Property(e => e.Description)
                    .IsRequired()
                    .HasMaxLength(1000);

                entity.Property(e => e.CreatedAt)
                    .IsRequired()
                    .HasColumnType("timestamp")
                    .HasDefaultValueSql("CURRENT_TIMESTAMP");

                entity.Property(e => e.UpdatedAt)
                    .IsRequired()
                    .HasColumnType("timestamp")
                    .HasDefaultValueSql("CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP");

                // Indexes for better performance
                entity.HasIndex(e => e.UserId)
                    .HasDatabaseName("IX_Comments_UserId");

                entity.HasIndex(e => e.PostId)
                    .HasDatabaseName("IX_Comments_PostId");

                entity.HasIndex(e => e.CreatedAt)
                    .HasDatabaseName("IX_Comments_CreatedAt");

                // Composite index for common queries
                entity.HasIndex(e => new { e.PostId, e.CreatedAt })
                    .HasDatabaseName("IX_Comments_PostId_CreatedAt");
            });
        }
    }
}