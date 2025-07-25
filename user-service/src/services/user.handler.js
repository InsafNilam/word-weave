import User from "../models/user.model.js";

export class UserHandler {
  static async createUser(userData) {
    try {
      const newUser = new User({
        clerkUserId: userData.id,
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
      const deletedUser = await User.findOneAndDelete({ clerkUserId });

      if (deletedUser) {
        console.log(`✅ User deleted: ${deletedUser.username}`);
        // TODO: Publish user.deleted event for other services
        // await eventPublisher.publish("user.deleted", { userId: deletedUser._id });
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
        { clerkUserId },
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
