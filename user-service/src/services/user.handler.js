import User from "../models/user.model.js";
import EventServiceClient from "../clients/event.client.js";

export class UserHandler {
  constructor() {
    this.eventClient = new EventServiceClient();
  }

  // Static method to get instance (singleton pattern)
  static getInstance() {
    if (!UserHandler.instance) {
      UserHandler.instance = new UserHandler();
    }
    return UserHandler.instance;
  }

  async publishEvent(eventType, eventData, metadata = {}) {
    try {
      await this.eventClient.publishEvent({
        aggregateId: eventData.userId || eventData.clerkId || "user-service",
        aggregateType: "user",
        eventType,
        eventData,
        metadata: {
          service: "user-service",
          version: "1.0.0",
          ...metadata,
        },
      });
      console.log(`✅ Event published: ${eventType}`);
    } catch (eventError) {
      console.warn(
        `⚠️ Failed to publish ${eventType} event:`,
        eventError.message
      );
      // Don't throw error - event publishing failure shouldn't break the main flow
    }
  }

  async publishErrorEvent(eventType, error, requestData) {
    try {
      await this.eventClient.publishEvent({
        aggregateId: "user-service",
        aggregateType: "user",
        eventType,
        eventData: {
          error: error.message,
          requestData,
          timestamp: new Date().toISOString(),
        },
        metadata: {
          service: "user-service",
          version: "1.0.0",
        },
      });
    } catch (eventError) {
      console.warn(`Failed to publish ${eventType} event:`, eventError.message);
    }
  }

  async createUser(userData) {
    try {
      if (!userData.id) {
        throw new Error("Clerk user ID is required");
      }

      // Check if user already exists to prevent duplicates
      const existingUser = await User.findOne({ clerk_user_id: userData.id });
      if (existingUser) {
        console.log(`ℹ️ User already exists: ${existingUser.username}`);
        return existingUser;
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

      // Publish user created event
      await this.publishEvent("user.created", {
        userId: newUser._id,
        clerkId: newUser.clerk_user_id,
        email: newUser.email,
        username: newUser.username,
        img: newUser.img,
        createdAt: newUser.createdAt,
      });

      return newUser;
    } catch (error) {
      // Handle duplicate key errors gracefully
      if (error.code === 11000) {
        console.log(`ℹ️ User with clerk_user_id ${userData.id} already exists`);
        return await User.findOne({ clerk_user_id: userData.id });
      }

      console.error("❌ Error creating user:", error);

      // Publish error event
      await this.publishErrorEvent("UserCreationFailed", error, userData);

      throw error;
    }
  }

  async deleteUser(clerkUserId) {
    try {
      if (!clerkUserId) {
        throw new Error("Clerk user ID is required for deletion");
      }

      const deletedUser = await User.findOne({
        clerk_user_id: clerkUserId,
      });

      if (deletedUser) {
        console.log(`✅ User deleted: ${deletedUser.username}`);

        // Publish user deleted event
        await this.publishEvent("user.deleted", {
          userId: deletedUser._id,
          clerkId: deletedUser.clerk_user_id,
          email: deletedUser.email,
          username: deletedUser.username,
          deletedAt: new Date().toISOString(),
        });
      } else {
        console.warn(`⚠️ User not found for deletion: ${clerkUserId}`);
      }

      return deletedUser;
    } catch (error) {
      console.error("❌ Error deleting user:", error);

      // Publish error event
      await this.publishErrorEvent("UserDeletionFailed", error, {
        clerkUserId,
      });

      throw error;
    }
  }

  async updateUser(clerkUserId, userData) {
    try {
      if (!clerkUserId) {
        throw new Error("Clerk user ID is required for update");
      }

      const updatedUser = await User.findOneAndUpdate(
        { clerk_user_id: clerkUserId },
        {
          $set: {
            username:
              userData.username || userData.email_addresses[0]?.email_address,
            email: userData.email_addresses[0]?.email_address,
            img: userData.profile_img_url,
            updatedAt: new Date(),
          },
        },
        { new: true, runValidators: true }
      );

      if (updatedUser) {
        console.log(`✅ User updated: ${updatedUser.username}`);

        // Publish user updated event
        await this.publishEvent("user.updated", {
          userId: updatedUser._id,
          clerkId: updatedUser.clerk_user_id,
          email: updatedUser.email,
          username: updatedUser.username,
          img: updatedUser.img,
          updatedAt: updatedUser.updatedAt,
        });
      } else {
        console.warn(`⚠️ User not found for update: ${clerkUserId}`);
      }

      return updatedUser;
    } catch (error) {
      console.error("❌ Error updating user:", error);

      // Publish error event
      await this.publishErrorEvent("UserUpdateFailed", error, {
        clerkUserId,
        userData,
      });

      throw error;
    }
  }

  // Additional utility method to get user by clerk ID
  async getUserByClerkId(clerkUserId) {
    try {
      if (!clerkUserId) {
        throw new Error("Clerk user ID is required");
      }

      const user = await User.findOne({ clerk_user_id: clerkUserId });
      return user;
    } catch (error) {
      console.error("❌ Error fetching user:", error);
      throw error;
    }
  }

  // Method to handle webhook events
  async handleWebhookEvent(eventType, userData) {
    try {
      switch (eventType) {
        case "user.created":
          return await this.createUser(userData);

        case "user.updated":
          return await this.updateUser(userData.id, userData);

        case "user.deleted":
          return await this.deleteUser(userData.id);

        default:
          console.warn(`⚠️ Unhandled webhook event: ${eventType}`);
          return null;
      }
    } catch (error) {
      console.error(`❌ Error handling webhook event ${eventType}:`, error);
      throw error;
    }
  }

  // Static methods for backward compatibility (if you prefer static usage)
  static async createUser(userData) {
    const instance = UserHandler.getInstance();
    return await instance.createUser(userData);
  }

  static async deleteUser(clerkUserId) {
    const instance = UserHandler.getInstance();
    return await instance.deleteUser(clerkUserId);
  }

  static async updateUser(clerkUserId, userData) {
    const instance = UserHandler.getInstance();
    return await instance.updateUser(clerkUserId, userData);
  }

  static async handleWebhookEvent(eventType, userData) {
    const instance = UserHandler.getInstance();
    return await instance.handleWebhookEvent(eventType, userData);
  }
}
