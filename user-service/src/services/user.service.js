import dotenv from "dotenv";
dotenv.config();

import EventServiceClient from "../clients/event.client.js";
import { createClerkClient } from "@clerk/backend";
import User from "../models/user.model.js";
import {
  getGrpcErrorCode,
  normalizeToArray,
  transformUser,
  generateCorrelationId,
  generateRequestId,
} from "../utils/helper.js";

const clerkClient = createClerkClient({
  secretKey: process.env.CLERK_SECRET_KEY,
});

const eventClient = new EventServiceClient();

export const userService = {
  async publishErrorEvent(eventType, error, requestData) {
    try {
      await this.eventClient.publishEvent({
        aggregateId: "user-service",
        aggregateType: "UserService",
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
  },

  async ListUsers(call, callback) {
    try {
      // Extract and validate request parameters
      const {
        limit = 10,
        offset = 0,
        email_address,
        username,
        user_id,
      } = call.request;

      // Input validation
      const parsedLimit = Math.max(1, Math.min(parseInt(limit) || 10, 100)); // Cap at 100
      const parsedOffset = Math.max(0, parseInt(offset) || 0);

      // Construct filter options
      const filterOptions = {
        limit: parsedLimit,
        offset: parsedOffset,
      };

      // Add filters only if they have meaningful values
      const emailAddresses = normalizeToArray(email_address);
      if (emailAddresses) {
        filterOptions.emailAddress = emailAddresses;
      }

      const usernames = normalizeToArray(username);
      if (usernames) {
        filterOptions.username = usernames;
      }

      const userIds = normalizeToArray(user_id);
      if (userIds) {
        filterOptions.userId = userIds;
      }

      // Fetch users from Clerk
      const clerkResult = await clerkClient.users.getUserList(filterOptions);

      if (!clerkResult || !Array.isArray(clerkResult.data)) {
        throw new Error("Invalid response from Clerk API");
      }

      // 2️⃣ Get local DB users for enrichment
      const clerkIds = clerkResult.data.map((u) => u.id);
      const localUsers = await User.find({
        clerkUserId: { $in: clerkIds },
      }).lean();

      const localUserMap = new Map(localUsers.map((u) => [u.clerkUserId, u]));

      // Merge Clerk + local DB data
      const users = clerkResult.data.map((clerkUser) => {
        const localData = localUserMap.get(clerkUser.id);
        return transformUser({
          ...clerkUser,
          _id: localData._id || null,
          bio: localData.bio || null,
        });
      });

      // Success response
      callback(null, {
        users,
        total_count: clerkResult.totalCount || 0,
        limit: parsedLimit,
        offset: parsedOffset,
        has_more: parsedOffset + parsedLimit < (clerkResult.totalCount || 0),
        message: "Users retrieved successfully",
      });
    } catch (error) {
      console.error("Error in ListUsers:", {
        message: error.message,
        stack: error.stack,
        request: call.request,
      });

      const grpcError = new Error(`Failed to list users: ${error.message}`);
      grpcError.code = getGrpcErrorCode(error);

      callback(grpcError);
    }
  },

  async GetUser(call, callback) {
    try {
      const { user_id } = call.request;

      if (!user_id) {
        throw new Error("User ID is required");
      }

      const clerkUser = await clerkClient.users.getUser(user_id);
      if (!clerkUser) {
        throw new Error(`User not found in Clerk: ${user_id}`);
      }

      // Fetch local DB user
      const localUser = await User.findOne({ clerkUserId: user_id }).lean();

      // Merge Clerk + local DB data
      const user = {
        ...clerkUser,
        _id: localUser._id || null,
        bio: localUser.bio || null,
      };

      callback(null, {
        user: transformUser(user),
        message: "User retrieved successfully",
        success: true,
      });
    } catch (error) {
      console.error("Error in GetUser:", {
        message: error.message,
        stack: error.stack,
        request: call.request,
      });

      const grpcError = new Error(`Failed to get user: ${error.message}`);
      grpcError.code = getGrpcErrorCode(error);

      callback(grpcError);
    }
  },

  async CreateUser(call, callback) {
    try {
      const { email, password, username, first_name, last_name, role } =
        call.request;

      if (!email || !password || !username) {
        throw new Error("email, password, and username are required");
      }

      // Validate email format
      if (!/\S+@\S+\.\S+/.test(email)) {
        throw new Error("Invalid email format");
      }

      // Validate password strength
      if (password.length < 8) {
        throw new Error("Password must be at least 8 characters long");
      }

      // Validate username
      if (!/^[a-zA-Z0-9_]{3,20}$/.test(username)) {
        throw new Error(
          "Username must be 3-20 characters long and can only contain letters, numbers, and underscores"
        );
      }

      const newUser = await clerkClient.users.createUser({
        emailAddress: [email],
        password,
        username,
        firstName: first_name,
        lastName: last_name,
        publicMetadata: role ? { role } : {},
      });

      // Fetch local DB user
      const localUser = await User.findOne({ clerkUserId: newUser.id }).lean();
      // Merge Clerk + local DB data
      const user = {
        ...clerkUser,
        _id: localUser._id || null,
        bio: localUser.bio || null,
      };

      // Publish Event
      await this.eventClient.publishEvent({
        aggregateId: user._id || user.id,
        aggregateType: "User",
        eventType: "user.created",
        eventData: {
          userId: user._id,
          clerkId: user.id,
          email: newUser.emailAddresses[0]?.emailAddress,
          username: newUser.username,
          firstName: newUser.firstName,
          lastName: newUser.lastName,
          createdAt: newUser.createdAt,
        },
        metadata: {
          service: "user-service",
          version: "1.0.0",
        },
      });

      callback(null, {
        user: transformUser(user),
        message: "User created successfully",
      });
    } catch (error) {
      console.error("Error in CreateUser:", {
        message: error.message,
        stack: error.stack,
        request: call.request,
      });

      const grpcError = new Error(`Failed to create user: ${error.message}`);
      grpcError.code = getGrpcErrorCode(error);

      await this.publishErrorEvent("UserCreationFailed", error, call.request);
      callback(grpcError);
    }
  },

  async UpdateUser(call, callback) {
    try {
      const { user_id, username, first_name, last_name, role, bio } =
        call.request;

      if (!user_id) {
        throw new Error("User ID is required");
      }

      // Validate username if provided
      if (username && !/^[a-zA-Z0-9_]{3,20}$/.test(username)) {
        throw new Error(
          "Username must be 3-20 characters long and can only contain letters, numbers, and underscores"
        );
      }

      const updatedClerkUser = await clerkClient.users.updateUser(user_id, {
        ...(username && { username }),
        ...(first_name && { firstName: first_name }),
        ...(last_name && { lastName: last_name }),
        ...(role && { publicMetadata: { role } }),
      });

      let updatedLocalUser = null;
      if (bio || username) {
        updatedLocalUser = await User.findOneAndUpdate(
          { clerkUserId: user_id },
          {
            ...(username && { username }),
            ...(bio && { bio }),
          },
          { new: true, upsert: false }
        ).lean();
      }

      const updatedUser = {
        ...updatedClerkUser,
        _id: updatedLocalUser?._id || null,
        bio: updatedLocalUser?.bio || null,
      };

      // Publish Event
      await eventClient.publishEvent({
        aggregateId: updatedUser._id,
        aggregateType: "User",
        eventType: "user.updated",
        eventData: {
          userId: updatedUser._id,
          clerkId: updatedUser.id,
          email: updatedUser.emailAddresses[0]?.emailAddress,
          username: updatedUser.username,
          firstName: updatedUser.firstName,
          lastName: updatedUser.lastName,
          updatedAt: updatedUser.updatedAt,
        },
        metadata: {
          service: "user-service",
          version: "1.0.0",
        },
      });

      callback(null, {
        user: transformUser(updatedUser),
        message: "User updated successfully",
      });
    } catch (error) {
      console.error("Error in UpdateUser:", {
        message: error.message,
        stack: error.stack,
        request: call.request,
      });

      const grpcError = new Error(`Failed to update user: ${error.message}`);
      grpcError.code = getGrpcErrorCode(error);

      await this.publishErrorEvent("UserUpdateFailed", error, call.request);
      callback(grpcError);
    }
  },

  async DeleteUser(call, callback) {
    try {
      const { user_id } = call.request;

      if (!user_id) {
        throw new Error("User ID is required");
      }

      // Fetch local DB user
      const localDeletedUser = await User.findOne({
        clerkUserId: user_id,
      }).lean();
      const clerkDeletedUser = await clerkClient.users.deleteUser(user_id);

      const deletedUser = {
        ...clerkDeletedUser,
        _id: localDeletedUser._id || null,
        bio: localDeletedUser.bio || null,
      };

      // Publish Event
      await eventClient.publishEvent({
        aggregateId: deletedUser._id,
        aggregateType: "User",
        eventType: "user.deleted",
        eventData: {
          userId: localDeletedUser._id,
          clerkId: deletedUser.id,
          email: deletedUser.emailAddresses[0]?.emailAddress,
          username: deletedUser.username,
          firstName: deletedUser.firstName,
          lastName: deletedUser.lastName,
          deletedAt: deletedUser.deletedAt,
        },
        metadata: {
          service: "user-service",
          version: "1.0.0",
        },
      });

      callback(null, {
        user: transformUser(deletedUser),
        message: "User deleted successfully",
      });
    } catch (error) {
      console.error("Error in DeleteUser:", {
        message: error.message,
        stack: error.stack,
        request: call.request,
      });
      const grpcError = new Error(`Failed to delete user: ${error.message}`);
      grpcError.code = getGrpcErrorCode(error);

      await this.publishErrorEvent("UserDeletionFailed", error, call.request);
      callback(grpcError);
    }
  },

  async GetUserCount(call, callback) {
    try {
      const { email_address, username, user_id } = call.request || {};

      // Construct filter options
      const filterOptions = {};

      // Add filters only if they have meaningful values
      const emailAddresses = normalizeToArray(email_address);
      if (emailAddresses) {
        filterOptions.emailAddress = emailAddresses;
      }

      const usernames = normalizeToArray(username);
      if (usernames) {
        filterOptions.username = usernames;
      }

      const userIds = normalizeToArray(user_id);
      if (userIds) {
        filterOptions.userId = userIds;
      }

      const count = await clerkClient.users.getCount(filterOptions);

      callback(null, {
        count,
        message: "User count retrieved successfully",
      });
    } catch (error) {
      console.error("Error in GetUserCount:", {
        message: error.message,
        stack: error.stack,
        request: call.request,
      });
      const grpcError = new Error(`Failed to get user count: ${error.message}`);
      grpcError.code = getGrpcErrorCode(error);

      callback(grpcError);
    }
  },

  async UpdateUserRole(call, callback) {
    try {
      const { user_id, role } = call.request;

      if (!user_id || !role) {
        throw new Error("User ID and role are required");
      }

      const updatedUser = await clerkClient.users.updateUserMetadata(user_id, {
        publicMetadata: { role },
      });
      // Fetch local DB user
      const localUser = await User.findOne({ clerkUserId: user_id }).lean();

      // Merge local user data with updated user data
      const user = {
        ...updatedUser,
        _id: localUser._id || null,
        bio: localUser.bio || null,
      };

      // Publish Event
      await eventClient.publishEvent({
        aggregateId: user._id,
        aggregateType: "User",
        eventType: "user.updated",
        eventData: {
          userId: localUser._id,
          clerkId: updatedUser.id,
          role: updatedUser.publicMetadata?.role,
          updatedAt: updatedUser.updatedAt,
        },
        metadata: {
          service: "user-service",
          version: "1.0.0",
          requestId: this.generateRequestId(),
        },
      });

      callback(null, {
        user: transformUser(user),
        message: "User role updated successfully",
      });
    } catch (error) {
      console.error("Error in UpdateUserRole:", {
        message: error.message,
        stack: error.stack,
        request: call.request,
      });
      const grpcError = new Error(
        `Failed to update user role: ${error.message}`
      );
      grpcError.code = getGrpcErrorCode(error);

      await this.publishErrorEvent("UserRoleUpdateFailed", error, call.request);
      callback(grpcError);
    }
  },

  async GetOAuthAccessToken(call, callback) {
    try {
      const { user_id, provider } = call.request;

      if (!user_id || !provider) {
        throw new Error("User ID and provider are required");
      }

      const validProviders = ["google", "github", "facebook"];
      // Validate provider format
      if (!validProviders.includes(provider)) {
        throw new Error("Invalid OAuth provider");
      }

      const token = await clerkClient.users.getUserOauthAccessToken(
        user_id,
        validProviders[validProviders.indexOf(provider)]
      );

      callback(null, {
        token: token.data,
        message: "OAuth access tokens retrieved successfully",
      });
    } catch (error) {
      console.error("Error in GetOAuthAccessToken:", {
        message: error.message,
        stack: error.stack,
        request: call.request,
      });
      const grpcError = new Error(
        `Failed to get OAuth access token: ${error.message}`
      );
      grpcError.code = getGrpcErrorCode(error);

      callback(grpcError);
    }
  },
};
