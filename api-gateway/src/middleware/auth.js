/**
 * Authorization middleware to check user roles
 * This middleware checks if the user is authenticated and has the required role(s) to access the route
 * @param {Array} allowedRoles - Array of roles that are allowed to access the route
 * If empty, any authenticated user can access the route
 *
 * @return {Function} - Express middleware function
 * @throws {Error} - If the user is not authenticated or does not have the required role
 * @example
 * // Allow only admin users
 *    app.get("/admin", authorizeByRole(["admin"]), (req, res) => {
 *       res.send("Welcome Admin");
 *   });
 */
export function authorizeByRole(allowedRoles = []) {
  return (req, res, next) => {
    const auth = req.auth() || {};

    const userId = auth?.userId;
    const userRole = auth?.sessionClaims?.metadata?.role;

    if (!userId) {
      return res.status(401).json({ error: "Unauthorized: Not authenticated" });
    }

    // If no specific role is required, allow any authenticated user
    if (allowedRoles.length === 0) {
      return next();
    }

    // If no role is assigned to the user, deny access
    if (!userRole) {
      return res.status(403).json({ error: "Forbidden: No role assigned" });
    }

    // If role is not in the allowed list, deny access
    if (!allowedRoles.includes(userRole)) {
      return res
        .status(403)
        .json({ error: `Forbidden: Role '${userRole}' not allowed` });
    }

    next(); // All good
  };
}
