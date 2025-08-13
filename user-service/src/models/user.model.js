import mongoose from "mongoose";
const { Schema } = mongoose;

const userSchema = new Schema(
  {
    clerk_user_id: {
      type: String,
      required: true,
      unique: true,
    },
    username: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      minLength: 3,
    },
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      match: /^\S+@\S+\.\S+$/,
    },
    img: {
      type: String,
    },
    bio: {
      type: String,
      maxLength: 500,
    },
  },
  {
    timestamps: true,
    indexes: [{ clerk_user_id: 1 }, { email: 1 }, { username: 1 }],
  }
);

// Add compound index for pagination queries
userSchema.index({ createdAt: -1 });

export default mongoose.model("User", userSchema);
