import dotenv from "dotenv";
dotenv.config();

import User from "../models/user.model.js";
import EventServiceClient from "../clients/event.client.js";
import { createClerkClient } from "@clerk/backend";
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
      const result = await clerkClient.users.getUserList(filterOptions);

      if (!result || !Array.isArray(result.data)) {
        throw new Error("Invalid response from Clerk API");
      }

      // Transform user data
      const users = result.data.map((user) => transformUser(user));

      // Success response
      callback(null, {
        users,
        total_count: result.totalCount || 0,
        limit: parsedLimit,
        offset: parsedOffset,
        has_more: parsedOffset + parsedLimit < (result.totalCount || 0),
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

      const user = await clerkClient.users.getUser(user_id);

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

      // Publish Event
      await this.eventClient.publishEvent({
        aggregateId: newUser.id,
        aggregateType: "User",
        eventType: "user.created",
        eventData: {
          userId: newUser.id,
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
        user: transformUser(newUser),
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
      const { user_id, username, first_name, last_name, role } = call.request;

      if (!user_id) {
        throw new Error("User ID is required");
      }

      // Validate username if provided
      if (username && !/^[a-zA-Z0-9_]{3,20}$/.test(username)) {
        throw new Error(
          "Username must be 3-20 characters long and can only contain letters, numbers, and underscores"
        );
      }

      const updatedUser = await clerkClient.users.updateUser(user_id, {
        username,
        firstName: first_name,
        lastName: last_name,
        publicMetadata: role ? { role } : {},
      });

      // Publish Event
      await eventClient.publishEvent({
        aggregateId: updatedUser.id,
        aggregateType: "User",
        eventType: "user.updated",
        eventData: {
          userId: updatedUser.id,
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

      const deletedUser = await clerkClient.users.deleteUser(user_id);

      // Publish Event
      await eventClient.publishEvent({
        aggregateId: deletedUser.id,
        aggregateType: "User",
        eventType: "user.deleted",
        eventData: {
          userId: deletedUser.id,
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

      // Publish Event
      await eventClient.publishEvent({
        aggregateId: updatedUser.id,
        aggregateType: "User",
        eventType: "user.updated",
        eventData: {
          userId: updatedUser.id,
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
        user: transformUser(updatedUser),
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
