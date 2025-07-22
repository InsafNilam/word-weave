// Helper method to check if a value is a valid string
export const isValidString = (val) => {
  return typeof val === "string" && val.trim().length > 0;
};

// Helper method to validate strings
export const normalizeToArray = (val) => {
  if (Array.isArray(val)) return val.filter(isValidString).map((v) => v.trim());
  if (isValidString(val)) return [val.trim()];
  return undefined;
};

// Helper method to transform user data
export const transformUser = (user) => {
  if (!user || !user.id) {
    throw new Error("Invalid user data received from Clerk");
  }

  return {
    id: user.id,
    username: user.username || "",
    email: user.emailAddresses?.[0]?.emailAddress || "",
    image_url: user.hasImage ? user.imageUrl : "",
    role: user.publicMetadata?.role || "user",
    created_at: user.createdAt ? new Date(user.createdAt).toISOString() : null,
    updated_at: user.updatedAt ? new Date(user.updatedAt).toISOString() : null,
    last_active_at: user.lastActiveAt
      ? new Date(user.lastActiveAt).toISOString()
      : null,
    is_active: user.lastActiveAt
      ? new Date(user.lastActiveAt).toISOString()
      : null,
    activity_status: user.lastActiveAt
      ? getActivityStatus(user.lastActiveAt)
      : "inactive",
  };
};

// Helper method to get detailed activity status
export const getActivityStatus = (lastActiveAt) => {
  if (!lastActiveAt) return "never_active";

  const lastActiveTime = new Date(lastActiveAt).getTime();
  const currentTime = Date.now();
  const diffInHours = (currentTime - lastActiveTime) / (60 * 60 * 1000);
  const diffInDays = diffInHours / 24;

  if (diffInHours < 1) return "online"; // Within last hour
  if (diffInHours < 24) return "today"; // Within last 24 hours
  if (diffInDays < 2) return "recent"; // Within last 2 days
  if (diffInDays < 7) return "this_week"; // Within last week
  if (diffInDays < 30) return "this_month"; // Within last month

  return "inactive"; // More than 30 days
};

// Helper method to map errors to appropriate gRPC codes
export const getGrpcErrorCode = (error) => {
  if (error.message?.includes("not found")) return 5; // NOT_FOUND
  if (
    error.message?.includes("permission") ||
    error.message?.includes("unauthorized")
  )
    return 7; // PERMISSION_DENIED
  if (
    error.message?.includes("invalid") ||
    error.message?.includes("validation")
  )
    return 3; // INVALID_ARGUMENT
  if (error.message?.includes("quota") || error.message?.includes("rate limit"))
    return 8; // RESOURCE_EXHAUSTED

  return 13; // INTERNAL
};
