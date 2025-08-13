import User from "../models/user.model.js";

export class UserHandler {
  static async createUser(userData) {
    try {
      if (!userData.id) {
        throw new Error("Clerk user ID is required");
      }

      const newUser = new User({
        clerk_user_id: userData.id,
        username:
          userData.username || userData.email_addresses[0]?.email_address,
        email: userData.email_addresses[0]?.email_address,
        img: userData.profile_img_url,
      });

      await newUser.save();
      console.log(`✅ User created: ${newUser.username}`);
      return newUser;
    } catch (error) {
      console.error("❌ Error creating user:", error);
      throw error;
    }
  }

  static async deleteUser(clerkUserId) {
    try {
      const deletedUser = await User.findOneAndDelete({
        clerk_user_id: clerkUserId,
      });

      if (deletedUser) {
        console.log(`✅ User deleted: ${deletedUser.username}`);
      } else {
        console.warn(`⚠️ User not found for deletion: ${clerkUserId}`);
      }

      return deletedUser;
    } catch (error) {
      console.error("❌ Error deleting user:", error);
      throw error;
    }
  }

  static async updateUser(clerkUserId, userData) {
    try {
      const updatedUser = await User.findOneAndUpdate(
        { clerk_user_id: clerkUserId },
        {
          username:
            userData.username || userData.email_addresses[0]?.email_address,
          email: userData.email_addresses[0]?.email_address,
          img: userData.profile_img_url,
        },
        { new: true }
      );

      if (updatedUser) {
        console.log(`✅ User updated: ${updatedUser.username}`);
      }

      return updatedUser;
    } catch (error) {
      console.error("❌ Error updating user:", error);
      throw error;
    }
  }
}
