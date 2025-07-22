import { createBrowserRouter } from "react-router-dom";
import AppLayout from "@/components/AppLayout";

import HomePage from "@/pages/HomePage";
import PostListPage from "@/pages/PostListPage";
import PostDetailsPage from "@/pages/PostDetailsPage";
import WritePage from "@/pages/WritePage";
import LoginPage from "@/pages/LoginPage";
import RegisterPage from "@/pages/RegisterPage";

export const router = createBrowserRouter([
  {
    element: <AppLayout />,
    children: [
      {
        path: "/",
        element: <HomePage />,
      },
      {
        path: "/posts",
        element: <PostListPage />,
      },
      {
        path: "/write",
        element: <WritePage />,
      },
      {
        path: "/login",
        element: <LoginPage />,
      },
      {
        path: "/register",
        element: <RegisterPage />,
      },
      {
        path: "/:slug",
        element: <PostDetailsPage />,
      },
    ],
  },
]);
